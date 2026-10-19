"""The OAuth round trip, and the sealing of what it returns.

Two jobs, both security-critical:

**PKCE, held server-side.** The app never sees the code verifier. It gets a
`challengeId` and, from the browser redirect, an authorization `code` — and
neither is enough to mint a token, because the verifier that binds them stays
in Firestore under rules that deny every client read. An attacker who
intercepts the redirect (a malicious app registering the same custom scheme is
the realistic version) has half of a two-part secret.

**Refresh tokens sealed at rest.** A Drive refresh token is a permanent key to
someone's entire drive — the highest-value secret in the system, and the one
whose loss the user cannot detect. Firestore encrypts at rest already; this is
the layer that survives the *next* mistake in `firestore.rules`, a leaked
service-account key, or a stray export. Ciphertext without `CONNECTOR_KEY` is
noise.
"""

from __future__ import annotations

import base64
import hashlib
import os
import secrets
from datetime import UTC, datetime, timedelta
from urllib.parse import urlencode

from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from firebase_admin import firestore

from connectors import REDIRECT_URI, ScopeLevel, profile_for

CHALLENGES = "oauthChallenges"

#: Long enough to sign in to a provider on a phone, including a password
#: manager detour and a 2FA prompt; short enough that a leaked challenge id is
#: worthless by the time anyone finds it.
CHALLENGE_TTL = timedelta(minutes=15)

#: How early a token is treated as expired. Covers clock skew plus the time
#: the request itself takes — refreshing 60s early is far cheaper than a
#: mid-sync 401.
SKEW = timedelta(seconds=90)


# --------------------------------------------------------------------- PKCE


def _verifier() -> str:
    # 32 bytes → 43 base64url characters, inside RFC 7636's 43–128.
    return base64.urlsafe_b64encode(secrets.token_bytes(32)).decode().rstrip("=")


def _challenge(verifier: str) -> str:
    digest = hashlib.sha256(verifier.encode("ascii")).digest()
    return base64.urlsafe_b64encode(digest).decode().rstrip("=")


def begin(uid: str, provider: str, level: ScopeLevel) -> dict:
    """Create a challenge and the URL the browser should open."""
    profile = profile_for(provider)
    verifier = _verifier()
    state = secrets.token_urlsafe(24)
    now = datetime.now(UTC)

    db = firestore.client()
    doc = db.collection(CHALLENGES).document()
    doc.set(
        {
            "userId": uid,
            "provider": provider,
            "scopeLevel": str(level),
            "verifier": verifier,
            "state": state,
            "createdAt": now,
            "expiresAt": now + CHALLENGE_TTL,
            "consumed": False,
        }
    )

    from connectors.registry import _credentials

    client_id, _ = _credentials(provider)
    params = {
        "client_id": client_id,
        "redirect_uri": REDIRECT_URI,
        "response_type": "code",
        "scope": profile.scope_string(level),
        "state": state,
        "code_challenge": _challenge(verifier),
        "code_challenge_method": "S256",
        **profile.authorize_params,
    }

    return {
        "challengeId": doc.id,
        "authorizationUrl": f"{profile.authorize_url}?{urlencode(params)}",
        "redirectUri": REDIRECT_URI,
        "state": state,
    }


class ChallengeError(RuntimeError):
    pass


def claim(uid: str, challenge_id: str, state: str) -> dict:
    """Spend a challenge, returning the verifier exactly once.

    Single-use and transactional. A challenge that could be redeemed twice
    would let a replayed redirect attach a second connection, and "consumed"
    checked outside a transaction is a race, not a check.
    """
    db = firestore.client()
    ref = db.collection(CHALLENGES).document(challenge_id)

    @firestore.transactional
    def _claim(transaction) -> dict:  # type: ignore[no-untyped-def]
        snapshot = ref.get(transaction=transaction)
        if not snapshot.exists:
            raise ChallengeError("That sign-in attempt has expired. Try again.")

        data = snapshot.to_dict() or {}

        # Every failure below says the same thing on purpose: which check
        # failed is information about someone else's session.
        if (
            data.get("userId") != uid
            or data.get("consumed")
            or not secrets.compare_digest(str(data.get("state", "")), state)
            or _as_datetime(data["expiresAt"]) < datetime.now(UTC)
        ):
            raise ChallengeError("That sign-in attempt has expired. Try again.")

        transaction.update(ref, {"consumed": True, "consumedAt": datetime.now(UTC)})
        return data

    return _claim(db.transaction())


# ------------------------------------------------------------------ sealing


def _key() -> AESGCM:
    raw = os.environ.get("CONNECTOR_KEY", "")
    if not raw:
        raise RuntimeError(
            "CONNECTOR_KEY is not set. Refusing to store a refresh token in the clear."
        )
    # Accepts either a base64 32-byte key or a passphrase; hashing makes both
    # a valid AES-256 key without a second config format to get wrong.
    try:
        key = base64.b64decode(raw, validate=True)
        if len(key) != 32:
            raise ValueError
    except (ValueError, base64.binascii.Error):
        key = hashlib.sha256(raw.encode()).digest()
    return AESGCM(key)


def seal(plaintext: str, *, aad: str) -> str:
    """Encrypt a token, bound to `aad`.

    `aad` is the account id: ciphertext copied onto a different account fails
    to decrypt rather than silently granting that account someone else's
    storage.
    """
    nonce = secrets.token_bytes(12)
    blob = _key().encrypt(nonce, plaintext.encode(), aad.encode())
    return base64.b64encode(nonce + blob).decode()


def unseal(ciphertext: str, *, aad: str) -> str:
    raw = base64.b64decode(ciphertext)
    return _key().decrypt(raw[:12], raw[12:], aad.encode()).decode()


# ------------------------------------------------------------------- tokens


def store_tokens(account_ref, tokens, *, account_id: str) -> None:
    """Write the sealed grant to the private subcollection.

    Not on the account document. `firestore.rules` lets the owner read their
    own account row — which is right, the app renders it — so anything on that
    row is readable by the client by definition.
    """
    payload = {
        "accessToken": seal(tokens.access_token, aad=account_id),
        "accessExpiresAt": tokens.expires_at,
        "grantedScopes": list(tokens.granted_scopes),
        "updatedAt": datetime.now(UTC),
    }
    if tokens.refresh_token:
        # Only present on first consent at every provider. Overwriting with a
        # null on refresh would sever the connection at the next expiry.
        payload["refreshToken"] = seal(tokens.refresh_token, aad=account_id)

    account_ref.collection("private").document("oauth").set(payload, merge=True)


async def access_token(account_ref, *, account_id: str, provider: str) -> str:
    """A usable access token, refreshing first if it is close to expiry."""
    from connectors import connector_for

    snapshot = account_ref.collection("private").document("oauth").get()
    if not snapshot.exists:
        raise ChallengeError("This connection is no longer authorised.")

    data = snapshot.to_dict() or {}
    expires = data.get("accessExpiresAt")

    if expires and _as_datetime(expires) - SKEW > datetime.now(UTC):
        return unseal(data["accessToken"], aad=account_id)

    sealed_refresh = data.get("refreshToken")
    if not sealed_refresh:
        raise ChallengeError("This connection is no longer authorised.")

    tokens = await connector_for(provider).refresh(unseal(sealed_refresh, aad=account_id))
    store_tokens(account_ref, tokens, account_id=account_id)
    return tokens.access_token


def _as_datetime(value: object) -> datetime:
    if isinstance(value, datetime):
        return value if value.tzinfo else value.replace(tzinfo=UTC)
    return datetime.fromtimestamp(float(value), tz=UTC)  # type: ignore[arg-type]
