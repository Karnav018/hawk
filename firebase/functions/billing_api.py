"""The payment surface: buy, restore, and the stores telling us what changed.

Three functions, and the third is the one that makes billing *correct* rather
than merely possible — see the `subscriptions` module docstring.
"""

from __future__ import annotations

from datetime import UTC, datetime

from firebase_admin import firestore
from firebase_functions import https_fn, options

import billing
import products
import subscriptions

#: Declared on the functions that talk to a store.
#:
#: Apple's three are absent from Secret Manager, so they are NOT listed —
#: Firebase refuses to deploy a function referencing a missing secret, which
#: fails the whole deploy and can leave unrelated functions returning 403.
#: Create them, then add: "APPLE_KEY_P8", "APPLE_KEY_ID", "APPLE_ISSUER_ID".
#: Google needs no secret at all: the function's own service account is the
#: credential, once it is granted access in Play Console.
STORE_SECRETS: list[str] = []


def _uid(req: https_fn.CallableRequest) -> str:
    if req.auth is None or not req.auth.uid:
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.UNAUTHENTICATED, "Sign in first.")
    return req.auth.uid


def _store_error(error: subscriptions.StoreError) -> https_fn.HttpsError:
    if isinstance(error, subscriptions.NotConfigured):
        # Deliberately not UNAVAILABLE: nothing will change by retrying, and
        # the app should say "purchases are not available in this build"
        # rather than "try again".
        return https_fn.HttpsError(https_fn.FunctionsErrorCode.FAILED_PRECONDITION, str(error))
    return https_fn.HttpsError(
        https_fn.FunctionsErrorCode.UNAVAILABLE
        if error.retryable
        else https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
        str(error),
    )


def _record_receipt(db, uid: str, verified: subscriptions.Verified) -> None:
    """Keep the charge this verification proves, for screen 2J.

    Keyed by the store's per-charge id, so the same period verified twice —
    a restore, a duplicate notification, a retried call — writes one receipt,
    not two. Clients may read these and never write them (firestore.rules):
    a receipt the user could author would be worth nothing.
    """
    receipt = verified.receipt
    if receipt is None:
        return
    product = products.product_for(verified.product_id)
    doc_id = receipt.receipt_id.replace("/", "_")
    db.collection("users").document(uid).collection("receipts").document(doc_id).set(
        {
            "productId": verified.product_id,
            "tier": verified.tier,
            "months": product.months if product else None,
            "store": verified.store,
            "chargedAt": receipt.charged_at,
            "amountMicros": receipt.amount_micros,
            "currency": receipt.currency,
            "trial": receipt.trial,
            "recordedAt": datetime.now(UTC),
        },
        merge=True,
    )


def _write(uid: str, verified: subscriptions.Verified) -> dict:
    db = firestore.client()
    doc = subscriptions.snapshot(verified)

    db.collection("users").document(uid).collection("subscription").document("current").set(
        doc, merge=True
    )

    # A second index, keyed by the store's own subscription identity, so a
    # later notification — which arrives with no Firebase uid attached — can
    # find the user it belongs to. Without it, a renewal or a cancellation has
    # nowhere to land.
    db.collection("storeSubscriptions").document(verified.transaction_id).set(
        {
            "userId": uid,
            "store": verified.store,
            "productId": verified.product_id,
            "updatedAt": datetime.now(UTC),
        },
        merge=True,
    )

    _record_receipt(db, uid, verified)

    entitlements = billing.resolve(doc)
    return {
        "tier": entitlements.tier,
        "status": doc["status"],
        "currentPeriodEnd": verified.period_end.isoformat(),
        "autoRenewing": verified.auto_renewing,
    }


@https_fn.on_call(region="us-central1", memory=options.MemoryOption.MB_256)
def list_products(req: https_fn.CallableRequest) -> dict:
    """What the paywall offers.

    Prices come from the store SDK on the device wherever the store lists the
    product — they are localised, tax-inclusive where required, and change
    without a deploy. `referencePrice` is only what the paywall shows until
    then (no console set up yet, a device with no store), so the screen is a
    real price screen rather than an apology; the app never sells at it.
    """
    _uid(req)
    return {
        "productIds": products.ids(),
        "products": [
            {
                "productId": p.product_id,
                "tier": p.tier,
                "months": p.months,
                "referencePrice": p.reference_price,
                "referenceAmount": p.reference_amount,
                "currency": p.currency,
                # The Android app's Razorpay price (razorpay_payments).
                "inrPrice": f"₹{p.inr_paise // 100}" if p.inr_paise else None,
                "inrAmount": p.inr_paise / 100 if p.inr_paise else None,
            }
            for p in products.CATALOGUE.values()
        ],
        # What each tier includes, from the table the backend enforces —
        # so screen 1S never prints the design's sample numbers.
        "plans": billing.plan_summaries(),
    }


@https_fn.on_call(
    region="us-central1",
    memory=options.MemoryOption.MB_256,
    timeout_sec=60,
    secrets=STORE_SECRETS,
)
def verify_purchase(req: https_fn.CallableRequest) -> dict:
    """Validate a purchase the client just made, and grant the tier.

    The client sends a product id, a store, and a token. The token is a lookup
    key and nothing more — every field that decides what the user gets comes
    back from the store's own API. A client that could name its own tier could
    grant itself Premium.
    """
    uid = _uid(req)
    store = str(req.data.get("store") or "")
    product_id = str(req.data.get("productId") or "")
    token = str(req.data.get("token") or "")

    if not product_id or not token:
        raise https_fn.HttpsError(
            https_fn.FunctionsErrorCode.INVALID_ARGUMENT, "Incomplete purchase."
        )
    if products.product_for(product_id) is None:
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.INVALID_ARGUMENT, "Unknown product.")

    try:
        verified = (
            subscriptions.verify_google(product_id, token)
            if store == "google_play"
            else subscriptions.verify_apple(product_id, token)
        )
    except subscriptions.StoreError as error:
        raise _store_error(error) from error

    # A token already bound to someone else is either a bug or an attempt to
    # transfer a subscription by replaying a receipt. Refused either way.
    db = firestore.client()
    existing = db.collection("storeSubscriptions").document(verified.transaction_id).get()
    if existing.exists:
        owner = (existing.to_dict() or {}).get("userId")
        if owner and owner != uid:
            raise https_fn.HttpsError(
                https_fn.FunctionsErrorCode.PERMISSION_DENIED,
                "That purchase belongs to another account.",
            )

    return _write(uid, verified)


@https_fn.on_call(
    region="us-central1",
    memory=options.MemoryOption.MB_256,
    timeout_sec=60,
    secrets=STORE_SECRETS,
)
def restore_purchases(req: https_fn.CallableRequest) -> dict:
    """Re-validate what the device already owns.

    Needed on a new phone, after a reinstall, and because both stores require
    a visible Restore action. Takes the same shape as a purchase: the device
    reports what it holds, the store is asked whether it is true.
    """
    uid = _uid(req)
    items = req.data.get("purchases")
    if not isinstance(items, list) or not items:
        return {"restored": 0, "tier": billing.FREE}

    best: subscriptions.Verified | None = None
    for item in items:
        if not isinstance(item, dict):
            continue
        product_id = str(item.get("productId") or "")
        token = str(item.get("token") or "")
        store = str(item.get("store") or "")
        if products.product_for(product_id) is None or not token:
            continue

        try:
            verified = (
                subscriptions.verify_google(product_id, token)
                if store == "google_play"
                else subscriptions.verify_apple(product_id, token)
            )
        except subscriptions.StoreError:
            # One bad receipt must not fail the restore — a device can hold
            # expired purchases from years ago alongside a live one.
            continue

        # Keep the one that grants the most: a device can legitimately hold an
        # expired Standard and a live Premium, and restoring the wrong one
        # would downgrade a paying customer.
        if verified.status in (subscriptions.ACTIVE, subscriptions.IN_GRACE) and (
            best is None or verified.period_end > best.period_end
        ):
            best = verified

    if best is None:
        return {"restored": 0, "tier": billing.FREE}

    result = _write(uid, best)
    return {"restored": 1, **result}


@https_fn.on_request(
    region="us-central1",
    memory=options.MemoryOption.MB_256,
    secrets=STORE_SECRETS,
)
def store_notification(req: https_fn.Request) -> https_fn.Response:
    """Renewals, lapses, refunds and cancellations.

    The half of billing that has nothing to do with the app being open, and
    the reason a subscription does not stay Premium forever after the card
    stops working.

    Returns 200 even on a body it cannot use. Both stores retry non-2xx with
    backoff and eventually give up — so a 500 on a malformed notification
    loses every *subsequent* one for that subscription. What gets logged
    matters more than what gets returned.
    """
    try:
        payload = req.get_json(silent=True) or {}
    except Exception:
        payload = {}

    # Google sends a Pub/Sub envelope; Apple posts a signed JWS directly.
    handled = False
    if "message" in payload:
        handled = _handle_google(payload)
    elif "signedPayload" in payload:
        handled = _handle_apple(payload)

    if not handled:
        print(f"[knowra] store_notification unhandled keys={sorted(payload)}")

    return https_fn.Response("", status=200)


def _handle_google(envelope: dict) -> bool:
    import base64
    import json

    data = ((envelope.get("message") or {}).get("data")) or ""
    try:
        notice = json.loads(base64.b64decode(data))
    except Exception:
        return False

    sub = notice.get("subscriptionNotification") or {}
    token = str(sub.get("purchaseToken") or "")
    product_id = str(sub.get("subscriptionId") or "")
    if not token or not product_id:
        return False

    # Re-fetch rather than trusting the notification's own type field. The
    # notification says *something happened*; the API says what is true now,
    # and out-of-order delivery makes the difference matter.
    try:
        verified = subscriptions.verify_google(product_id, token)
    except subscriptions.StoreError as error:
        print(f"[knowra] google_notification_unverified error={error}")
        return True

    return _apply(verified)


def _handle_apple(payload: dict) -> bool:
    signed = str(payload.get("signedPayload") or "")
    if not signed:
        return False

    # NOTE: this JWS arrives from the open internet, so unlike the App Store
    # API response in `subscriptions`, its signature MUST be verified against
    # Apple's root certificates before any claim is trusted. Until that is in
    # place the payload is used only to find the transaction id, and the
    # entitlement itself is re-fetched from the authenticated API.
    claims = subscriptions._apple_claims(signed)
    data = claims.get("data") or {}
    tx = subscriptions._apple_claims(str(data.get("signedTransactionInfo") or ""))

    transaction_id = str(tx.get("originalTransactionId") or "")
    product_id = str(tx.get("productId") or "")
    if not transaction_id or products.product_for(product_id) is None:
        return False

    try:
        verified = subscriptions.verify_apple(product_id, transaction_id)
    except subscriptions.StoreError as error:
        print(f"[knowra] apple_notification_unverified error={error}")
        return True

    return _apply(verified)


def _apply(verified: subscriptions.Verified) -> bool:
    """Write a verified change to whichever user owns it."""
    db = firestore.client()
    index = db.collection("storeSubscriptions").document(verified.transaction_id).get()
    uid = (index.to_dict() or {}).get("userId") if index.exists else None

    if not uid:
        # A notification for a subscription we have never seen a purchase
        # for. Recorded rather than dropped: the usual cause is a purchase
        # made before the app ever called verify_purchase, and it will
        # resolve itself when the user next opens the app and restores.
        db.collection("storeSubscriptions").document(verified.transaction_id).set(
            {
                "userId": None,
                "store": verified.store,
                "productId": verified.product_id,
                "pendingStatus": verified.status,
                "updatedAt": datetime.now(UTC),
            },
            merge=True,
        )
        print(
            "[knowra] store_notification_unclaimed "
            f"tx={verified.transaction_id} status={verified.status}"
        )
        return True

    db.collection("users").document(uid).collection("subscription").document("current").set(
        subscriptions.snapshot(verified), merge=True
    )
    # A renewal arrives here, not through verify_purchase — so this is where
    # every period after the first gets its receipt. `verified` was re-fetched
    # from the store's authenticated API above; the notification's own
    # unverified payload contributed only the transaction id.
    _record_receipt(db, uid, verified)

    print(f"[knowra] subscription_updated uid={uid} tier={verified.tier} status={verified.status}")
    return True
