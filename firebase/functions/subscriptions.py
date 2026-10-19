"""Turning a store receipt into an entitlement — and keeping it true after.

The purchase is the easy half. What makes billing correct is the *second*
half: a subscription renews, lapses, is refunded, is cancelled, gets a billing
retry, moves between tiers — and almost none of that involves the app being
open. So there are two entry points and they are not interchangeable:

* **`verify_purchase`** — the client just bought something and wants its tier
  now. Validates with the store and writes the snapshot.
* **`store_notification`** — the store telling us something changed. This is
  what keeps a lapsed subscription from staying Premium forever, and it is the
  one that cannot be skipped.

**The client is never believed.** It reports a purchase token, and the token
is only ever a lookup key: every field that decides what the user gets comes
from the store's own API. A client that could name its own tier would be a
client that could grant itself Premium.

Credentials are not wired yet, and this is honest about that: without them
validation *refuses* rather than trusting the client. A payments path that
falls back to trusting the app when its credentials are missing is worse than
one that is switched off.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

import httpx

import billing
import products

#: Google Play Developer API. Needs a service account with the
#: "View financial data" permission, linked in Play Console → API access.
GOOGLE_API = "https://androidpublisher.googleapis.com/androidpublisher/v3"

#: App Store Server API. Needs a .p8 key, its key id, and the issuer id.
APPLE_API_PROD = "https://api.storekit.itunes.apple.com/inApps/v1"
APPLE_API_SANDBOX = "https://api.storekit-sandbox.itunes.apple.com/inApps/v1"

ANDROID_PACKAGE = os.environ.get("ANDROID_PACKAGE", "in.hawkapp.app")

#: Statuses the plan table treats as entitled. Mirrors `billing.resolve`.
ACTIVE = "active"
IN_GRACE = "in_grace"
EXPIRED = "expired"
REFUNDED = "refunded"


class StoreError(RuntimeError):
    """A store said no, or could not be asked."""

    def __init__(self, message: str, *, retryable: bool = False):
        super().__init__(message)
        self.retryable = retryable


class NotConfigured(StoreError):
    """No credentials for this store in this deployment.

    Distinct from a refusal so the caller can say "payments are not live in
    this build" rather than "your card was declined" — and so that it never
    reads as a reason to trust the client instead.
    """


@dataclass(frozen=True, slots=True)
class Receipt:
    """One charge, as the store's own authenticated API reported it.

    Screen 2J's receipts are built from these and from nothing else. The
    catalogue deliberately holds no prices (they change; product ids do
    not), and a price sent up by the client would be the client describing
    its own purchase. The store's authenticated response is the only source
    here that can be trusted to say what was actually charged.
    """

    #: Unique per charge: Apple's `transactionId` (a new one every renewal,
    #: unlike `originalTransactionId`), Play's `latestOrderId` ("…..0",
    #: "…..1"). The document id, so re-verifying a period writes it once.
    receipt_id: str
    charged_at: datetime
    #: Micros of `currency`. None when the store did not say — an older API
    #: version, or a plan type with no recurring price. Shown as missing,
    #: never guessed.
    amount_micros: int | None
    currency: str | None
    trial: bool


@dataclass(frozen=True, slots=True)
class Verified:
    """What a store told us, normalised."""

    tier: str
    product_id: str
    status: str
    period_end: datetime
    #: The store's own subscription identity, for deduplicating renewals and
    #: for matching a later notification to this user.
    transaction_id: str
    store: str
    auto_renewing: bool
    grace_until: datetime | None = None
    #: The charge this verification is evidence of, when it could be read.
    receipt: Receipt | None = None


def months_before(end: datetime, months: int) -> datetime:
    """`end` moved back by whole calendar months, clamping the day.

    Calendar months, not 30-day blocks: this dates a receipt, and a yearly
    charge printed five days early because 12 x 30 is 360 is the kind of
    error a user notices on the one screen about money.
    """
    year, index = divmod(end.year * 12 + (end.month - 1) - months, 12)
    month = index + 1
    first_of_next = (
        datetime(year + 1, 1, 1, tzinfo=end.tzinfo)
        if month == 12
        else datetime(year, month + 1, 1, tzinfo=end.tzinfo)
    )
    last_day = (first_of_next - timedelta(days=1)).day
    return end.replace(year=year, month=month, day=min(end.day, last_day))


def apple_receipt(claims: dict) -> Receipt | None:
    """A receipt from a decoded `signedTransactionInfo`.

    Only ever called on claims from the App Store Server API response, which
    this deployment fetched with its own credentials over TLS — never on a
    notification's payload, whose signature is not yet verified.
    """
    receipt_id = str(claims.get("transactionId") or "")
    if not receipt_id:
        return None

    purchased = claims.get("purchaseDate")
    charged_at = (
        datetime.fromtimestamp(int(purchased) / 1000, tz=UTC) if purchased else datetime.now(UTC)
    )

    # `price` is in milliunits of `currency`.
    price = claims.get("price")
    amount = int(price) * 1000 if price is not None else None
    currency = claims.get("currency")

    trial = claims.get("offerDiscountType") == "FREE_TRIAL"
    return Receipt(
        receipt_id=receipt_id,
        charged_at=charged_at,
        amount_micros=0 if trial else amount,
        currency=str(currency) if currency else None,
        trial=trial,
    )


def google_receipt(body: dict, period_end: datetime, months: int) -> Receipt | None:
    """A receipt from a Play `subscriptionsv2` response."""
    receipt_id = str(body.get("latestOrderId") or "")
    if not receipt_id:
        return None

    items = body.get("lineItems") or []
    item = items[0] if items else {}

    # `offerPhase` names which phase the current period is in. A free trial
    # charges nothing, whatever the recurring price says.
    trial = "freeTrial" in (item.get("offerPhase") or {})

    price = (item.get("autoRenewingPlan") or {}).get("recurringPrice") or {}
    units = price.get("units")
    amount = (
        int(units) * 1_000_000 + int(price.get("nanos") or 0) // 1000 if units is not None else None
    )

    return Receipt(
        receipt_id=receipt_id,
        # Play gives the period's end, not its start; the charge is at the
        # start. `startTime` is only the *first* period's.
        charged_at=months_before(period_end, months),
        amount_micros=0 if trial else amount,
        currency=price.get("currencyCode") or None,
        trial=trial,
    )


def _months_from(start: datetime, months: int) -> datetime:
    # Calendar-naive on purpose: this is only a fallback for stores that give
    # a start and no expiry, and a day either way on a fallback is not worth
    # a date library.
    return start + timedelta(days=30 * months)


# ----------------------------------------------------------------- google


def _google_token() -> str:
    """An access token for the Play Developer API.

    Uses the function's own service-account identity via the metadata server,
    so there is no key file to store or rotate — the same reason Firestore
    needs no credentials here. The service account still has to be granted
    access in Play Console, which is the part that cannot be automated.
    """
    try:
        import google.auth
        import google.auth.transport.requests

        credentials, _ = google.auth.default(
            scopes=["https://www.googleapis.com/auth/androidpublisher"]
        )
        credentials.refresh(google.auth.transport.requests.Request())
        return str(credentials.token)
    except Exception as error:
        raise NotConfigured("Google Play access is not configured for this deployment.") from error


def verify_google(product_id: str, token: str) -> Verified:
    product = products.product_for(product_id)
    if product is None:
        raise StoreError(f"Unknown product {product_id}.")

    access = _google_token()
    url = f"{GOOGLE_API}/applications/{ANDROID_PACKAGE}/purchases/subscriptionsv2/tokens/{token}"
    response = httpx.get(url, headers={"Authorization": f"Bearer {access}"}, timeout=20)

    if response.status_code == 404:
        raise StoreError("That purchase could not be found.")
    if response.status_code in (401, 403):
        raise NotConfigured("Google Play refused this deployment's credentials.")
    if response.status_code >= 500 or response.status_code == 429:
        raise StoreError("Google Play is unavailable.", retryable=True)
    if response.status_code >= 400:
        raise StoreError(f"Google Play rejected the purchase ({response.status_code}).")

    body = response.json()
    state = str(body.get("subscriptionState") or "")
    line_items = body.get("lineItems") or []
    expiry_raw = (line_items[0].get("expiryTime") if line_items else None) or body.get("expiryTime")

    status = {
        "SUBSCRIPTION_STATE_ACTIVE": ACTIVE,
        "SUBSCRIPTION_STATE_IN_GRACE_PERIOD": IN_GRACE,
        # Cancelled but not yet expired: still entitled until the period ends,
        # which is what `billing.resolve` decides from `currentPeriodEnd`.
        "SUBSCRIPTION_STATE_CANCELED": ACTIVE,
        "SUBSCRIPTION_STATE_ON_HOLD": EXPIRED,
        "SUBSCRIPTION_STATE_PAUSED": EXPIRED,
        "SUBSCRIPTION_STATE_EXPIRED": EXPIRED,
    }.get(state, EXPIRED)

    period_end = (
        _parse(expiry_raw) if expiry_raw else _months_from(datetime.now(UTC), product.months)
    )

    return Verified(
        tier=product.tier,
        product_id=product_id,
        status=status,
        period_end=period_end,
        transaction_id=str(body.get("latestOrderId") or token),
        store="google_play",
        auto_renewing=state == "SUBSCRIPTION_STATE_ACTIVE",
        receipt=google_receipt(body, period_end, product.months),
    )


# ------------------------------------------------------------------ apple


def _apple_jwt() -> str:
    """A signed JWT for the App Store Server API.

    Apple has no metadata-server equivalent, so this genuinely needs a private
    key. Absent one, refuse — never fall through to trusting the receipt the
    client handed us, which is exactly what an attacker would supply.
    """
    key = os.environ.get("APPLE_KEY_P8", "")
    key_id = os.environ.get("APPLE_KEY_ID", "")
    issuer = os.environ.get("APPLE_ISSUER_ID", "")
    bundle = os.environ.get("APPLE_BUNDLE_ID", "in.hawkapp.app")

    if not (key and key_id and issuer):
        raise NotConfigured("App Store access is not configured for this deployment.")

    import jwt  # PyJWT

    now = datetime.now(UTC)
    return jwt.encode(
        {
            "iss": issuer,
            "iat": int(now.timestamp()),
            "exp": int((now + timedelta(minutes=20)).timestamp()),
            "aud": "appstoreconnect-v1",
            "bid": bundle,
        },
        key,
        algorithm="ES256",
        headers={"kid": key_id, "typ": "JWT"},
    )


def verify_apple(product_id: str, transaction_id: str) -> Verified:
    product = products.product_for(product_id)
    if product is None:
        raise StoreError(f"Unknown product {product_id}.")

    auth = {"Authorization": f"Bearer {_apple_jwt()}"}

    # Production first, then sandbox. Apple does not tell you which
    # environment a transaction belongs to, and a TestFlight build's purchase
    # 404s against production — which reads as fraud rather than as testing.
    for base in (APPLE_API_PROD, APPLE_API_SANDBOX):
        response = httpx.get(f"{base}/subscriptions/{transaction_id}", headers=auth, timeout=20)
        if response.status_code == 404:
            continue
        if response.status_code in (401, 403):
            raise NotConfigured("Apple refused this deployment's credentials.")
        if response.status_code >= 500 or response.status_code == 429:
            raise StoreError("The App Store is unavailable.", retryable=True)
        if response.status_code >= 400:
            raise StoreError(f"The App Store rejected the purchase ({response.status_code}).")

        groups = response.json().get("data") or []
        transactions = (groups[0].get("lastTransactions") if groups else []) or []
        if not transactions:
            continue

        latest = transactions[0]
        state = int(latest.get("status") or 0)
        # 1 active, 2 expired, 3 billing retry, 4 grace, 5 revoked.
        status = {1: ACTIVE, 2: EXPIRED, 3: IN_GRACE, 4: IN_GRACE, 5: REFUNDED}.get(state, EXPIRED)

        signed = latest.get("signedTransactionInfo") or ""
        claims = _apple_claims(signed)
        expires_ms = claims.get("expiresDate")

        return Verified(
            tier=product.tier,
            product_id=str(claims.get("productId") or product_id),
            status=status,
            period_end=(
                datetime.fromtimestamp(int(expires_ms) / 1000, tz=UTC)
                if expires_ms
                else _months_from(datetime.now(UTC), product.months)
            ),
            transaction_id=str(claims.get("originalTransactionId") or transaction_id),
            store="app_store",
            auto_renewing=state == 1,
            receipt=apple_receipt(claims),
        )

    raise StoreError("That purchase could not be found.")


def _apple_claims(signed: str) -> dict:
    """Read an Apple JWS payload.

    The signature is *not* verified here, and that is safe only because of
    where this value came from: Apple's own authenticated API response, over
    TLS, in reply to a request signed with our private key. A JWS arriving
    from anywhere else — a client, a webhook body — must be verified against
    Apple's root certificates before a single claim is read.
    """
    import base64
    import json

    parts = signed.split(".")
    if len(parts) != 3:
        return {}
    payload = parts[1] + "=" * (-len(parts[1]) % 4)
    try:
        return json.loads(base64.urlsafe_b64decode(payload))
    except Exception:
        return {}


def _parse(raw: object) -> datetime:
    if isinstance(raw, datetime):
        return raw if raw.tzinfo else raw.replace(tzinfo=UTC)
    text = str(raw)
    if text.isdigit():
        return datetime.fromtimestamp(int(text) / 1000, tz=UTC)
    return datetime.fromisoformat(text.replace("Z", "+00:00"))


# ------------------------------------------------------------- persistence


def snapshot(verified: Verified) -> dict:
    """The subscription document.

    Writes the *entitlements as they are today*, not just the tier. This is
    what `billing.resolve` reads in preference to the live plan table, so a
    later pricing change cannot shrink an existing subscriber's memory window
    — which would destroy data they paid to keep.
    """
    entitlements = billing.entitlements_for(verified.tier)
    now = datetime.now(UTC)

    return {
        "tier": verified.tier,
        "status": verified.status,
        "productId": verified.product_id,
        "store": verified.store,
        "transactionId": verified.transaction_id,
        "autoRenewing": verified.auto_renewing,
        "currentPeriodEnd": verified.period_end,
        "graceUntil": verified.grace_until,
        **billing.snapshot_fields(entitlements),
        "updatedAt": now,
    }
