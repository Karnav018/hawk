"""Provider lookup, and the credentials each one needs.

The one place that knows which provider modules exist. Everything else asks
for a connector by id, which is what keeps `if provider == "google_drive"`
out of the callables — and is why removing a provider is an edit to this
dict rather than a hunt through the callables.

Google Drive is the only provider today. The registry stays a dict because
the alternative — inlining Drive everywhere — is what the indirection was
bought to avoid, and re-buying it later costs more than keeping it.
"""

from __future__ import annotations

import os
from collections.abc import Callable

from . import google_drive
from .base import GOOGLE_DRIVE, ProviderProfile, StorageConnector

#: Where every provider sends the browser back to.
#:
#: https, not the app's custom scheme, because Google rejects a custom scheme
#: outright on any client requesting restricted scopes — and `drive.readonly`
#: is restricted. The endpoint behind this URL (`connector_callback.py`) does
#: nothing but 302 on to `com.knowra.knowra://oauth/callback`.
#:
#: One value for every provider on purpose. A provider that would accept the
#: custom scheme directly still uses this, because a redirect that varies by
#: provider *and* by platform is exactly the provider-specific branching this
#: package exists to prevent.
#:
#: `<project>.firebaseapp.com` rather than a Cloud Run URL: it is the same
#: Hosting site, it is stable across redeploys, and Firebase Auth has already
#: registered it as an authorised domain on the consent screen.
#:
#: Whatever lands here is still useless on its own — the code cannot be
#: exchanged without the PKCE verifier, which never leaves the server.
REDIRECT_URI = "https://knowra-506719.firebaseapp.com/oauth/callback"

_BUILDERS: dict[str, tuple[ProviderProfile, Callable[[str, str], StorageConnector], str]] = {
    GOOGLE_DRIVE: (google_drive.PROFILE, google_drive.GoogleDriveConnector, "GOOGLE_DRIVE"),
}

PROFILES: dict[str, ProviderProfile] = {k: v[0] for k, v in _BUILDERS.items()}


class ProviderNotConfigured(RuntimeError):
    """The provider is known but this deployment has no credentials for it.

    Distinct from "no such provider" because the *user-facing* consequence is
    different: screen 3F shows an unconfigured provider dimmed with a reason,
    rather than pretending it does not exist. A build missing credentials
    should not look like a deliberate product decision.
    """


def source_url(provider: str, file_id: object) -> str | None:
    """The link that opens this file at its provider, if there is one.

    Answers for *any* provider, including ones this deployment has no
    credentials for and ones that were removed from the product — a link is
    derived from an id, and neither of those stops an already-indexed memory
    from being openable.
    """
    profile = PROFILES.get(provider)
    return profile.file_url(str(file_id)) if profile and file_id else None


def profile_for(provider: str) -> ProviderProfile:
    if provider not in PROFILES:
        raise KeyError(provider)
    return PROFILES[provider]


def is_configured(provider: str) -> bool:
    try:
        _credentials(provider)
    except (KeyError, ProviderNotConfigured):
        return False
    return True


def connector_for(provider: str) -> StorageConnector:
    _, build, _ = _BUILDERS[provider]
    client_id, client_secret = _credentials(provider)
    return build(client_id, client_secret)


def _credentials(provider: str) -> tuple[str, str]:
    profile, _, env_prefix = _BUILDERS[provider]
    client_id = os.environ.get(f"{env_prefix}_CLIENT_ID", "")
    client_secret = os.environ.get(f"{env_prefix}_CLIENT_SECRET", "")

    if not client_id:
        raise ProviderNotConfigured(f"{env_prefix}_CLIENT_ID is not set.")
    if profile.requires_client_secret and not client_secret:
        raise ProviderNotConfigured(f"{env_prefix}_CLIENT_SECRET is not set.")
    return client_id, client_secret
