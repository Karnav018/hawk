"""One HTTP client and one error translation, shared by every connector.

Every provider signals the two things we actually care about the same way —
401 means the grant is gone, 429/5xx means try later — so translating that
once here keeps three connectors from each inventing their own retry policy.
"""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from typing import Any

import httpx

from .base import ConnectorError, OAuthTokens

#: Providers are not fast, and a hung connector holds a function instance.
TIMEOUT = httpx.Timeout(20.0, connect=10.0)


def client() -> httpx.AsyncClient:
    return httpx.AsyncClient(timeout=TIMEOUT, follow_redirects=False)


#: 403 reasons that mean the grant is genuinely gone.
#:
#: Everything else behind a 403 is transient or a configuration problem, and
#: must NOT be read as revocation: flipping an account to REVOKED is close to
#: irreversible from the user's side — it stops syncing and asks them to
#: reconnect — so doing it on a rate limit destroys a working connection over
#: a bad minute.
_REVOKED_REASONS = frozenset(
    {
        "authError",
        "insufficientPermissions",
        "insufficientFilePermissions",
        "forbidden",
    }
)

#: 403 reasons that are throttling. Drive uses 403 rather than 429 for these,
#: which is the specific trap this whole function exists to avoid.
_THROTTLE_REASONS = frozenset(
    {
        "rateLimitExceeded",
        "userRateLimitExceeded",
        "quotaExceeded",
        "sharingRateLimitExceeded",
        "backendError",
        "internalError",
    }
)


def _reason(response: httpx.Response) -> str:
    """The provider's own machine-readable reason for a refusal.

    Google puts it in `error.errors[].reason`. The other shapes handled below
    — `error.code`, `error.status`, and a bare string — are what other
    providers use; they cost two lines and mean a new connector does not have
    to re-learn this. Returns an empty string when there is nothing to read,
    which the caller treats as "cannot tell".
    """
    try:
        body = response.json()
    except Exception:
        return ""

    if not isinstance(body, dict):
        return ""
    error = body.get("error")
    if isinstance(error, str):
        return error
    if not isinstance(error, dict):
        return ""

    errors = error.get("errors")
    if isinstance(errors, list) and errors and isinstance(errors[0], dict):
        return str(errors[0].get("reason") or "")
    return str(error.get("code") or error.get("status") or "")


def raise_for(response: httpx.Response, *, what: str) -> None:
    if response.is_success:
        return

    status = response.status_code

    # 401 is unambiguous: the token was rejected.
    if status == 401:
        raise ConnectorError(f"{what} was refused — access has been revoked.", revoked=True)

    if status == 403:
        reason = _reason(response)

        if reason in _THROTTLE_REASONS:
            raise ConnectorError(f"{what} hit a rate limit. Trying again shortly.", retryable=True)
        if reason == "accessNotConfigured":
            # The API is not enabled on the project. Nothing to do with the
            # user's grant, and telling them to reconnect would be a lie.
            raise ConnectorError(f"{what} is not enabled for this app. Enable the provider API.")
        if reason in _REVOKED_REASONS:
            raise ConnectorError(f"{what} was refused — access has been revoked.", revoked=True)

        # Unrecognised 403. Deliberately NOT treated as revocation: the cost
        # of guessing wrong that way is a working connection destroyed, and
        # the cost of guessing wrong the other way is one failed sync.
        raise ConnectorError(f"{what} was refused ({reason or status}).", retryable=True)

    if status == 429 or status >= 500:
        raise ConnectorError(f"{what} is temporarily unavailable.", retryable=True)

    raise ConnectorError(f"{what} failed ({status}).")


def tokens_from(payload: dict[str, Any]) -> OAuthTokens:
    """Normalise the one response shape all three providers share.

    `expires_in` is converted to an absolute instant here rather than stored
    as a duration: a duration is only meaningful next to the moment it was
    issued, and that moment is exactly what gets lost on the way to Firestore.
    """
    expires_in = int(payload.get("expires_in", 3600))
    scope = payload.get("scope") or ""
    return OAuthTokens(
        access_token=payload["access_token"],
        expires_at=datetime.now(UTC) + timedelta(seconds=expires_in),
        refresh_token=payload.get("refresh_token"),
        granted_scopes=tuple(scope.split()) if scope else (),
    )
