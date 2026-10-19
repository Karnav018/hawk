"""Razorpay: rupee payments in the Android and iOS apps, sold as 30-day passes.

User decisions (2026-10-14): Razorpay Standard Checkout inside the Android
app, ₹199 Standard / ₹399 Premium, one payment = 30 days of the plan; later
the same day, inside the iOS app too, knowing App Store rule 3.1.1 makes App
Review rejection likely. Google Play requires its own billing for in-app digital
goods unless the app is enrolled in its alternative billing programme for
India; that enrolment is in Play Console, not here.

Two callables, and the client is never believed:

* **`create_razorpay_order`** — the app names a product; the *server* sets
  the price from `PRICES_PAISE` and asks Razorpay for an order. The order is
  recorded against the caller, so a payment for it can only ever unlock this
  user's plan.
* **`verify_razorpay_payment`** — the checkout hands back an order id, a
  payment id and a signature. The plan is granted only when all three hold:
  the signature is Razorpay's (HMAC-SHA256 of "order_id|payment_id" with the
  key secret), the order is this user's, and Razorpay's own API says the
  payment is for that order and amount. An authorised-but-uncaptured payment
  is captured here, or Razorpay would refund it after a few days.

* **`razorpay_webhook`** — Razorpay's own server calling ours on
  `payment.captured` (grants the pass even if the app never reported back)
  and `refund.processed` (a full refund ends the pass it paid for). Signed
  with RAZORPAY_WEBHOOK_SECRET, the secret chosen in the Razorpay Dashboard.
  The app and the webhook share one transactional grant, so a payment is
  granted exactly once whichever arrives first.

A pass is written as an ordinary subscription (`billing_api._write`), so the
plan, its receipt and the billing screen work exactly as for a store
purchase. Buying the same plan again while it is active adds 30 days to its
end rather than starting over.

Secrets: `RAZORPAY_KEY_SECRET` lives in Secret Manager. `RAZORPAY_KEY_ID` is
public — it is in `.env` and sent to the app with each order.
"""

from __future__ import annotations

import hashlib
import hmac
import json
import os
from datetime import UTC, datetime, timedelta

import httpx
from firebase_admin import firestore
from firebase_functions import https_fn, options

import billing_api
import products
import subscriptions

RAZORPAY_API = "https://api.razorpay.com/v1"
SECRETS = ["RAZORPAY_KEY_SECRET"]

STORE = "razorpay"
CURRENCY = "INR"
PASS_DAYS = 30

#: What each product costs, in paise, from the catalogue. Set on the server
#: and nowhere else: a price the app sent would be the app choosing what to pay.
PRICES_PAISE: dict[str, int] = {
    p.product_id: p.inr_paise for p in products.CATALOGUE.values() if p.inr_paise
}

#: Razorpay refuses orders below ₹1.
MIN_PAISE = 100

ORDERS = "razorpayOrders"


def price_paise(product_id: str) -> int | None:
    price = PRICES_PAISE.get(product_id)
    return price if price is not None and price >= MIN_PAISE else None


def signature_valid(order_id: str, payment_id: str, signature: str, secret: str) -> bool:
    """Razorpay's checkout signature: HMAC-SHA256 of "order_id|payment_id"."""
    if not (order_id and payment_id and signature and secret):
        return False
    expected = hmac.new(
        secret.encode(), f"{order_id}|{payment_id}".encode(), hashlib.sha256
    ).hexdigest()
    return hmac.compare_digest(expected, signature)


def _as_datetime(value: object) -> datetime | None:
    if isinstance(value, datetime):
        return value if value.tzinfo else value.replace(tzinfo=UTC)
    if isinstance(value, str):
        try:
            parsed = datetime.fromisoformat(value)
        except ValueError:
            return None
        return parsed if parsed.tzinfo else parsed.replace(tzinfo=UTC)
    return None


def period_end(current: dict | None, tier: str, now: datetime) -> datetime:
    """When the new pass ends.

    The same plan, still running: 30 days on from its current end, so paying
    early never loses days. Anything else — no plan, an expired one, a switch
    between Standard and Premium — starts 30 days from now.
    """
    if current and current.get("tier") == tier and current.get("status") == "active":
        end = _as_datetime(current.get("currentPeriodEnd"))
        if end and end > now:
            return end + timedelta(days=PASS_DAYS)
    return now + timedelta(days=PASS_DAYS)


def blocks_purchase(current: dict | None, now: datetime) -> bool:
    """Whether a store subscription that renews by itself is still running.

    A pass written over it would orphan the store's record, and the person
    would be charged twice for the same months.
    """
    if not current or current.get("store") in (None, STORE):
        return False
    if not current.get("autoRenewing"):
        return False
    end = _as_datetime(current.get("currentPeriodEnd"))
    return bool(end and end > now)


def verified_pass(
    product: products.Product, payment_id: str, paise: int, end: datetime, now: datetime
) -> subscriptions.Verified:
    """A paid pass in the shape every store purchase takes."""
    return subscriptions.Verified(
        tier=product.tier,
        product_id=product.product_id,
        status=subscriptions.ACTIVE,
        period_end=end,
        transaction_id=payment_id,
        store=STORE,
        auto_renewing=False,
        receipt=subscriptions.Receipt(
            receipt_id=payment_id,
            charged_at=now,
            amount_micros=paise * 10_000,
            currency=CURRENCY,
            trial=False,
        ),
    )


# ------------------------------------------------------------------- calls


def _fail(code: https_fn.FunctionsErrorCode, message: str) -> https_fn.HttpsError:
    return https_fn.HttpsError(code, message)


def _uid(req: https_fn.CallableRequest) -> str:
    if req.auth is None or not req.auth.uid:
        raise _fail(https_fn.FunctionsErrorCode.UNAUTHENTICATED, "Sign in first.")
    return req.auth.uid


def _keys() -> tuple[str, str]:
    key_id = os.environ.get("RAZORPAY_KEY_ID", "").strip()
    secret = os.environ.get("RAZORPAY_KEY_SECRET", "").strip()
    if not key_id or not secret:
        # FAILED_PRECONDITION, not UNAUTHENTICATED: the app treats that one
        # as a dead session and would sign the user out.
        raise _fail(
            https_fn.FunctionsErrorCode.FAILED_PRECONDITION,
            "Payments are not set up yet.",
        )
    return key_id, secret


def _razorpay(method: str, path: str, body: dict | None = None) -> dict:
    """One call to Razorpay's API, its failures turned into callable errors."""
    key_id, secret = _keys()
    try:
        response = httpx.request(
            method, f"{RAZORPAY_API}{path}", json=body, auth=(key_id, secret), timeout=20
        )
    except httpx.HTTPError as error:
        raise _fail(
            https_fn.FunctionsErrorCode.UNAVAILABLE, "Couldn't reach the payment service."
        ) from error

    if response.status_code == 401:
        print("[knowra] razorpay_auth_failed")
        raise _fail(
            https_fn.FunctionsErrorCode.FAILED_PRECONDITION,
            "Payments are not set up correctly.",
        )
    if response.status_code >= 500 or response.status_code == 429:
        raise _fail(
            https_fn.FunctionsErrorCode.UNAVAILABLE,
            "The payment service is busy. Try again in a moment.",
        )
    if response.status_code >= 400:
        detail = ""
        try:
            detail = str(response.json().get("error", {}).get("description") or "")
        except ValueError:
            pass
        print(f"[knowra] razorpay_error status={response.status_code} {detail}")
        raise _fail(https_fn.FunctionsErrorCode.INTERNAL, "The payment service refused that.")
    return response.json()


def _current_subscription(db, uid: str) -> dict | None:
    doc = db.collection("users").document(uid).collection("subscription").document("current")
    snapshot = doc.get()
    return snapshot.to_dict() if snapshot.exists else None


@https_fn.on_call(region="us-central1", memory=options.MemoryOption.MB_256, secrets=SECRETS)
def create_razorpay_order(req: https_fn.CallableRequest) -> dict:
    """An order for one 30-day pass, priced by the server."""
    uid = _uid(req)
    product_id = str((req.data or {}).get("productId") or "")
    product = products.product_for(product_id)
    paise = price_paise(product_id)
    if product is None or paise is None:
        raise _fail(https_fn.FunctionsErrorCode.INVALID_ARGUMENT, "That plan is not for sale.")

    db = firestore.client()
    now = datetime.now(UTC)
    if blocks_purchase(_current_subscription(db, uid), now):
        raise _fail(
            https_fn.FunctionsErrorCode.FAILED_PRECONDITION,
            "You already have a plan that renews through your app store.",
        )

    key_id, _ = _keys()
    order = _razorpay(
        "POST",
        "/orders",
        {
            "amount": paise,
            "currency": CURRENCY,
            # Razorpay caps receipts at 40 characters.
            "receipt": f"hawk_{uid[:12]}_{int(now.timestamp())}",
            "notes": {"uid": uid, "productId": product_id},
        },
    )
    order_id = str(order.get("id") or "")
    if not order_id:
        raise _fail(https_fn.FunctionsErrorCode.INTERNAL, "The payment service sent no order.")

    db.collection(ORDERS).document(order_id).set(
        {
            "userId": uid,
            "productId": product_id,
            "amount": paise,
            "currency": CURRENCY,
            "status": "created",
            "createdAt": now,
        }
    )
    print(f"[knowra] razorpay_order_created product={product_id}")

    email = (req.auth.token or {}).get("email") if req.auth else None
    return {
        "orderId": order_id,
        "amount": paise,
        "currency": CURRENCY,
        "keyId": key_id,
        "name": "Hawk",
        "description": f"Hawk {product.tier.title()} · {PASS_DAYS} days",
        "email": email,
    }


@https_fn.on_call(region="us-central1", memory=options.MemoryOption.MB_256, secrets=SECRETS)
def verify_razorpay_payment(req: https_fn.CallableRequest) -> dict:
    """Grants the pass once the payment is proven, and not before."""
    uid = _uid(req)
    data = req.data or {}
    order_id = str(data.get("orderId") or "").strip()
    payment_id = str(data.get("paymentId") or "").strip()
    signature = str(data.get("signature") or "").strip()
    if not (order_id and payment_id and signature):
        raise _fail(
            https_fn.FunctionsErrorCode.INVALID_ARGUMENT, "The payment details are missing."
        )

    _, secret = _keys()
    if not signature_valid(order_id, payment_id, signature, secret):
        print("[knowra] razorpay_signature_mismatch")
        raise _fail(
            https_fn.FunctionsErrorCode.INVALID_ARGUMENT, "That payment could not be verified."
        )

    db = firestore.client()
    order_ref = db.collection(ORDERS).document(order_id)
    order_doc = order_ref.get()
    order = order_doc.to_dict() if order_doc.exists else None
    if not order or order.get("userId") != uid:
        raise _fail(https_fn.FunctionsErrorCode.PERMISSION_DENIED, "That order isn't yours.")

    product = products.product_for(str(order.get("productId") or ""))
    paise = int(order.get("amount") or 0)
    if product is None or paise < MIN_PAISE:
        raise _fail(https_fn.FunctionsErrorCode.INTERNAL, "That order is damaged.")

    # Already granted: a retried call, a double tap, or the webhook got there
    # first. Answer, never extend.
    if order.get("status") == "paid":
        if order.get("paymentId") != payment_id:
            raise _fail(
                https_fn.FunctionsErrorCode.FAILED_PRECONDITION, "That order is already paid."
            )
        return _plan_now(db, uid, product)

    payment = _razorpay("GET", f"/payments/{payment_id}")
    if payment.get("order_id") != order_id or int(payment.get("amount") or 0) != paise:
        print("[knowra] razorpay_payment_mismatch")
        raise _fail(
            https_fn.FunctionsErrorCode.INVALID_ARGUMENT, "That payment is not for this order."
        )
    status = payment.get("status")
    if status == "authorized":
        payment = _razorpay(
            "POST", f"/payments/{payment_id}/capture", {"amount": paise, "currency": CURRENCY}
        )
        status = payment.get("status")
    if status != "captured":
        raise _fail(
            https_fn.FunctionsErrorCode.FAILED_PRECONDITION,
            "The payment did not go through. You have not been charged for a plan.",
        )

    result = grant(db, order_ref, payment_id, source="app")
    return result if result is not None else _plan_now(db, uid, product)


def _plan_now(db, uid: str, product: products.Product) -> dict:
    """The caller's plan as it stands, in the shape a grant returns."""
    current = _current_subscription(db, uid) or {}
    end = _as_datetime(current.get("currentPeriodEnd"))
    return {
        "tier": current.get("tier", product.tier),
        "status": current.get("status", subscriptions.ACTIVE),
        "currentPeriodEnd": end.isoformat() if end else None,
        "autoRenewing": False,
    }


def grant(db, order_ref, payment_id: str, *, source: str) -> dict | None:
    """Claims a paid order and grants its pass. None if it was already granted.

    The app's verification and Razorpay's webhook can arrive for the same
    payment at the same moment. The claim is a transaction, so exactly one of
    them flips the order to paid and grants; the other sees it done. A pass
    granted twice would add 60 days for one payment.
    """

    @firestore.transactional
    def _claim(transaction) -> dict | None:  # type: ignore[no-untyped-def]
        snapshot = order_ref.get(transaction=transaction)
        data = snapshot.to_dict() or {}
        if not snapshot.exists or data.get("status") in ("paid", "refunded"):
            return None
        transaction.update(
            order_ref,
            {"status": "paid", "paymentId": payment_id, "paidAt": datetime.now(UTC)},
        )
        return data

    order = _claim(db.transaction())
    if order is None:
        return None

    uid = str(order.get("userId") or "")
    product = products.product_for(str(order.get("productId") or ""))
    paise = int(order.get("amount") or 0)
    if not uid or product is None:
        print(f"[knowra] razorpay_order_damaged order={order_ref.id}")
        return None

    now = datetime.now(UTC)
    try:
        end = period_end(_current_subscription(db, uid), product.tier, now)
        result = billing_api._write(uid, verified_pass(product, payment_id, paise, end, now))
    except Exception:
        # Not granted after all: hand the order back, so a retry — the app's,
        # or Razorpay's own webhook retry — can try again.
        order_ref.update(
            {
                "status": "created",
                "paymentId": firestore.DELETE_FIELD,
                "paidAt": firestore.DELETE_FIELD,
            }
        )
        raise
    print(
        f"[knowra] razorpay_pass_granted via={source} tier={product.tier} "
        f"until={end.date().isoformat()}"
    )
    return result


# ----------------------------------------------------------------- webhook

#: The secret chosen when the webhook was added in the Razorpay Dashboard.
#: Separate from the key secret: Razorpay signs webhooks with this one.
WEBHOOK_SECRETS = ["RAZORPAY_WEBHOOK_SECRET"]


def webhook_signature_valid(body: bytes, signature: str, secret: str) -> bool:
    """Razorpay's webhook signature: HMAC-SHA256 of the raw body, hex."""
    if not (body and signature and secret):
        return False
    expected = hmac.new(secret.encode(), body, hashlib.sha256).hexdigest()
    return hmac.compare_digest(expected, signature)


def _entity(event: dict, name: str) -> dict:
    return ((event.get("payload") or {}).get(name) or {}).get("entity") or {}


def captured_for_order(payment: dict, order: dict) -> bool:
    """Whether a captured payment really pays this order, in full."""
    return (
        payment.get("status") == "captured"
        and int(payment.get("amount") or 0) == int(order.get("amount") or -1)
        and str(payment.get("currency") or "") == CURRENCY
    )


def full_refund(refund: dict, order: dict) -> bool:
    """Whether a refund returns the whole price — the only kind that ends a pass."""
    return int(refund.get("amount") or 0) >= int(order.get("amount") or 1)


def _on_captured(db, payment: dict) -> str:
    order_id = str(payment.get("order_id") or "")
    if not order_id:
        return "no_order"
    ref = db.collection(ORDERS).document(order_id)
    snapshot = ref.get()
    if not snapshot.exists:
        # A payment from outside the app (a payment link, another product).
        return "not_ours"
    if not captured_for_order(payment, snapshot.to_dict() or {}):
        print(f"[knowra] razorpay_webhook_mismatch order={order_id}")
        return "mismatch"
    granted = grant(db, ref, str(payment.get("id") or ""), source="webhook")
    return "granted" if granted is not None else "already"


def _on_refund(db, refund: dict) -> str:
    payment_id = str(refund.get("payment_id") or "")
    if not payment_id:
        return "no_payment"
    found = list(db.collection(ORDERS).where("paymentId", "==", payment_id).limit(1).stream())
    if not found:
        return "not_ours"
    order_ref, order = found[0].reference, found[0].to_dict() or {}
    if not full_refund(refund, order):
        print(f"[knowra] razorpay_partial_refund order={order_ref.id}")
        return "partial"

    order_ref.update({"status": "refunded", "refundedAt": datetime.now(UTC)})
    uid = str(order.get("userId") or "")
    sub_ref = db.collection("users").document(uid).collection("subscription").document("current")
    current = sub_ref.get()
    if current.exists and (current.to_dict() or {}).get("transactionId") == payment_id:
        sub_ref.set({"status": subscriptions.REFUNDED, "updatedAt": datetime.now(UTC)}, merge=True)
        return "revoked"
    # An earlier pass whose days were already followed by a newer one: the
    # plan stays, and the refund is left for a person to reconcile.
    print(f"[knowra] razorpay_refund_of_older_pass order={order_ref.id}")
    return "older_pass"


@https_fn.on_request(
    region="us-central1", memory=options.MemoryOption.MB_256, secrets=WEBHOOK_SECRETS
)
def razorpay_webhook(req: https_fn.Request) -> https_fn.Response:
    """Razorpay telling the backend a payment was captured or refunded.

    The safety net under `verify_razorpay_payment`: when the app is closed
    or loses signal right after paying, the pass is still granted here.
    Answers 200 for anything handled or ignored, 400 for a bad signature,
    and 500 when granting failed — Razorpay retries non-2xx answers.
    """
    secret = os.environ.get("RAZORPAY_WEBHOOK_SECRET", "").strip()
    if not secret:
        print("[knowra] razorpay_webhook_not_configured")
        return https_fn.Response("not configured", status=500)

    body = req.get_data() or b""
    if not webhook_signature_valid(body, req.headers.get("X-Razorpay-Signature", ""), secret):
        print("[knowra] razorpay_webhook_bad_signature")
        return https_fn.Response("bad signature", status=400)

    try:
        event = json.loads(body)
    except ValueError:
        return https_fn.Response("bad body", status=400)

    kind = str(event.get("event") or "")
    db = firestore.client()
    try:
        if kind == "payment.captured":
            outcome = _on_captured(db, _entity(event, "payment"))
        elif kind == "refund.processed":
            outcome = _on_refund(db, _entity(event, "refund"))
        else:
            outcome = "ignored"
    except Exception as error:
        print(f"[knowra] razorpay_webhook_failed event={kind} cause={type(error).__name__}")
        return https_fn.Response("retry", status=500)

    print(f"[knowra] razorpay_webhook event={kind} outcome={outcome}")
    return https_fn.Response("ok", status=200)
