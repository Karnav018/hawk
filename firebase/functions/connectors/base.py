"""The connector contract.

Architecture §9: *"The core application should not depend directly on Google
Drive-specific logic."* Everything above this module talks to a
[StorageConnector] and a [ProviderProfile]; only the modules in this package
know that Drive calls a folder a "file with a folder mimetype" while another
provider might call it a path.

Where providers genuinely differ, the difference is declared as data on
[ProviderProfile] rather than branched on at the call site — so adding a
provider is a new module, not an edit to five `if provider ==` chains.

Drive is currently the only provider. The contract stays because it is what
keeps Drive's vocabulary out of the callables, and that is worth having with
one provider as much as with three.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from enum import StrEnum
from typing import Protocol

GOOGLE_DRIVE = "google_drive"


class ScopeLevel(StrEnum):
    """§46 — request the minimum permission required.

    Two levels, not a scope list, because the *user-facing* question on screen
    3G is binary: may Vault read your files, or may it also move and delete
    them. The provider scope strings that implement each level are the
    provider's business.
    """

    #: Read and index. Required — there is no product without it.
    READ = "read"
    #: Archive, move and delete, always behind an explicit confirmation.
    MANAGE = "manage"


class ConnectorState(StrEnum):
    """§40. A connection is a relationship, not a boolean.

    `REVOKED` is deliberately distinct from disconnected: the user pulled
    access at the provider, and we still hold an index built from files we can
    no longer reach. That is a state the UI has to be able to explain.
    """

    CONNECTED = "connected"
    SYNCING = "syncing"
    PAUSED = "paused"
    REVOKED = "revoked"
    ERROR = "error"


class ConnectorError(RuntimeError):
    """A provider said no.

    [retryable] separates "the provider is having a bad minute" from "this
    connection is finished" — the first is a backoff, the second flips the
    account to REVOKED and tells the user.
    """

    def __init__(self, message: str, *, retryable: bool = False, revoked: bool = False):
        super().__init__(message)
        self.retryable = retryable
        self.revoked = revoked


@dataclass(frozen=True, slots=True)
class OAuthTokens:
    access_token: str
    expires_at: datetime
    #: Absent on a refresh: most providers only issue one at first consent,
    #: and overwriting the stored one with None would sever the connection.
    refresh_token: str | None = None
    granted_scopes: tuple[str, ...] = ()


@dataclass(frozen=True, slots=True)
class ProviderAccount:
    """Which account this is, in the user's own words.

    Shown on screen 3F so somebody with three Google accounts can tell which
    one they connected.
    """

    account_id: str
    email: str | None
    display_name: str | None


@dataclass(frozen=True, slots=True)
class ProviderFolder:
    """A candidate for screen 3K.

    [file_count] and [bytes] are what the screen actually renders
    ("412 FILES · 8.2 GB"), and they are the reason folder listing is a
    connector concern rather than a generic tree walk: Drive can answer it
    from a query, where another provider may need a recursive walk.
    """

    id: str
    name: str
    path: str
    file_count: int = 0
    bytes: int = 0
    parent_id: str | None = None


@dataclass(frozen=True, slots=True)
class ProviderFile:
    id: str
    name: str
    mime_type: str
    bytes: int
    modified_at: datetime | None = None
    #: Provider-computed content hash where one exists. §16 dedupes on this
    #: before we spend a byte of egress downloading the file.
    content_hash: str | None = None
    parent_id: str | None = None
    #: True when the provider removed it — `get_changes` reports deletions in
    #: the same stream as edits.
    deleted: bool = False


@dataclass(frozen=True, slots=True)
class ChangeSet:
    """§39. Incremental sync state.

    [cursor] is opaque and provider-specific — Drive's page token, or
    whatever a future provider's equivalent is. Callers persist it and hand it
    back; they must never try to interpret it.
    """

    files: tuple[ProviderFile, ...]
    cursor: str
    has_more: bool = False


@dataclass(frozen=True, slots=True)
class ProviderProfile:
    """Everything about a provider that is configuration rather than code."""

    id: str
    label: str
    authorize_url: str
    token_url: str
    revoke_url: str | None
    scopes: dict[ScopeLevel, tuple[str, ...]]
    #: Extra query parameters the authorization request needs. Google wants
    #: `access_type=offline` or it never issues a refresh token — the single
    #: most common way to build a connector that works until the hour is up.
    authorize_params: dict[str, str] = field(default_factory=dict)
    #: Providers that reject a token request without a client secret even
    #: under PKCE. Where True, the secret is required configuration.
    requires_client_secret: bool = True
    #: How to build a link that opens one file at the provider — a template
    #: with an `{id}` placeholder.
    #:
    #: Data rather than a method because it is exactly the per-provider
    #: difference this dataclass exists to hold: without it, "where does this
    #: file open?" becomes an `if provider == "google_drive"` in every caller
    #: that has a memory and wants to show it. Derived from the id rather
    #: than fetched and stored, so it costs nothing per file and needs no
    #: backfill for files indexed before it existed.
    file_url_template: str | None = None

    def file_url(self, file_id: str | None) -> str | None:
        """Where this file opens at the provider, if it can be linked to."""
        if not self.file_url_template or not file_id:
            return None
        return self.file_url_template.format(id=file_id)

    def scope_string(self, level: ScopeLevel) -> str:
        """MANAGE is cumulative — it never drops the read scopes."""
        scopes = list(self.scopes[ScopeLevel.READ])
        if level is ScopeLevel.MANAGE:
            scopes += [s for s in self.scopes[ScopeLevel.MANAGE] if s not in scopes]
        return " ".join(scopes)


class StorageConnector(Protocol):
    """§9's conceptual interface, as the code the rest of the app calls.

    Deliberately narrower than the spec's list: `upload_file` and `rename_file`
    have no caller yet, and a protocol method with no implementation is a
    promise nobody checked. They get added when §37's archive flow needs them.
    """

    profile: ProviderProfile

    async def exchange_code(self, code: str, verifier: str, redirect_uri: str) -> OAuthTokens: ...

    async def refresh(self, refresh_token: str) -> OAuthTokens: ...

    async def revoke(self, token: str) -> None: ...

    async def get_account(self, access_token: str) -> ProviderAccount: ...

    async def list_folders(
        self, access_token: str, *, parent_id: str | None = None
    ) -> list[ProviderFolder]: ...

    async def list_files(
        self, access_token: str, *, folder_id: str, page_token: str | None = None
    ) -> ChangeSet: ...

    async def get_changes(self, access_token: str, *, cursor: str | None) -> ChangeSet: ...

    async def get_file(self, access_token: str, *, file_id: str) -> ProviderFile: ...

    async def download_file(self, access_token: str, *, file_id: str) -> bytes: ...

    async def delete_file(self, access_token: str, *, file_id: str) -> None: ...

    async def move_file(self, access_token: str, *, file_id: str, to_folder_id: str) -> None: ...
