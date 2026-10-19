"""Tests for the parts of the connector layer that can be wrong silently.

Deliberately not testing "does httpx call the right URL" — that fails loudly
the first time anyone connects. These cover the things that would work in a
demo and be wrong in production: scope escalation that quietly drops a scope,
a sealed token that decrypts under the wrong account, a Drive listing that
indexes an empty Google Doc export.
"""

from __future__ import annotations

import os

import pytest

os.environ.setdefault("CONNECTOR_KEY", "test-key-not-a-real-one")
os.environ.setdefault("GOOGLE_DRIVE_CLIENT_ID", "gd-client")
os.environ.setdefault("GOOGLE_DRIVE_CLIENT_SECRET", "gd-secret")

from connectors import PROFILES, ScopeLevel, base, google_drive, is_configured
from connectors.http import tokens_from


class TestScopes:
    def test_manage_is_cumulative(self):
        """Escalating to MANAGE must not drop the read scopes.

        Google's incremental auth would otherwise return a token that can
        delete files but not list them — which fails at the worst moment,
        halfway through an archive.
        """
        profile = PROFILES["google_drive"]
        read = set(profile.scope_string(ScopeLevel.READ).split())
        manage = set(profile.scope_string(ScopeLevel.MANAGE).split())
        assert read < manage

    def test_read_never_includes_a_write_scope(self):
        """§46: never request delete permission for a search-only user."""
        for profile in PROFILES.values():
            read = profile.scope_string(ScopeLevel.READ)
            assert "drive.readonly" in read or "write" not in read

    def test_google_requests_offline_access(self):
        """No `access_type=offline`, no refresh token, dead connection in 1h."""
        assert PROFILES["google_drive"].authorize_params["access_type"] == "offline"

    def test_every_provider_can_issue_a_refresh_token(self):
        """A connection that cannot refresh is dead within the hour.

        Asserted across every registered profile rather than naming one, so a
        new provider added without offline access fails here rather than in
        somebody's vault a day later.
        """
        for profile in PROFILES.values():
            offline = (
                profile.authorize_params.get("access_type") == "offline"
                or profile.authorize_params.get("token_access_type") == "offline"
                or "offline_access" in profile.scopes[ScopeLevel.READ]
            )
            assert offline, profile.id


class TestRegistry:
    def test_missing_credentials_is_unconfigured_not_a_crash(self):
        """Screen 3F dims what this build cannot do; it must not 500."""
        assert is_configured("google_drive") is True
        assert is_configured("no_such_provider") is False

    def test_unknown_provider_raises(self):
        with pytest.raises(KeyError):
            base.ProviderProfile  # noqa: B018
            from connectors import profile_for

            profile_for("icloud")


class TestSealing:
    def test_round_trip(self):
        import connector_oauth as oauth

        sealed = oauth.seal("refresh-abc", aad="account-1")
        assert sealed != "refresh-abc"
        assert oauth.unseal(sealed, aad="account-1") == "refresh-abc"

    def test_ciphertext_is_bound_to_its_account(self):
        """Copying a sealed token onto another account must fail closed.

        Without the AAD binding, a bug that crossed account ids would hand one
        user another user's storage and look like a successful decrypt.
        """
        from cryptography.exceptions import InvalidTag

        import connector_oauth as oauth

        sealed = oauth.seal("refresh-abc", aad="account-1")
        with pytest.raises(InvalidTag):
            oauth.unseal(sealed, aad="account-2")

    def test_nonce_is_not_reused(self):
        import connector_oauth as oauth

        a = oauth.seal("same", aad="account-1")
        b = oauth.seal("same", aad="account-1")
        assert a != b

    def test_refuses_to_store_without_a_key(self, monkeypatch):
        import connector_oauth as oauth

        monkeypatch.delenv("CONNECTOR_KEY", raising=False)
        with pytest.raises(RuntimeError, match="CONNECTOR_KEY"):
            oauth.seal("refresh-abc", aad="account-1")


class TestPkce:
    def test_challenge_is_the_sha256_of_the_verifier(self):
        import base64
        import hashlib

        import connector_oauth as oauth

        verifier = oauth._verifier()
        expected = (
            base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest())
            .decode()
            .rstrip("=")
        )
        assert oauth._challenge(verifier) == expected

    def test_verifier_length_is_within_rfc7636(self):
        import connector_oauth as oauth

        assert 43 <= len(oauth._verifier()) <= 128


class TestDriveNormalisation:
    def test_google_native_docs_are_not_indexed(self):
        """A Google Doc has no bytes to download — only an export.

        Indexing one before the export path exists produces a memory whose
        content is empty, which reads as a broken index rather than an
        unsupported file type.
        """
        assert not google_drive._is_indexable({"mimeType": "application/vnd.google-apps.document"})
        assert not google_drive._is_indexable({"mimeType": google_drive.FOLDER_MIME})
        assert google_drive._is_indexable({"mimeType": "application/pdf"})

    def test_missing_size_is_zero_not_a_crash(self):
        """Drive omits `size` for anything it does not store bytes for."""
        f = google_drive._file({"id": "1", "name": "x", "mimeType": "application/pdf"})
        assert f.bytes == 0

    def test_expiry_is_absolute_not_a_duration(self):
        """A duration loses meaning the moment it is written to Firestore."""
        from datetime import UTC, datetime

        tokens = tokens_from({"access_token": "a", "expires_in": 3600})
        assert (tokens.expires_at - datetime.now(UTC)).total_seconds() > 3500

    def test_refresh_token_absent_is_none_not_empty(self):
        """Distinguishing absent from empty is what stops `store_tokens`
        overwriting a good refresh token on every renewal."""
        assert tokens_from({"access_token": "a"}).refresh_token is None


class TestSyncClassification:
    def test_mime_type_wins(self):
        import connector_sync as sync

        assert sync._kind("audio/mpeg", "x") == "recording"
        assert sync._kind("image/png", "x") == "image"
        assert sync._kind("application/pdf", "x") == "document"

    def test_falls_back_to_the_extension_when_the_mime_is_useless(self):
        """Drive returns application/octet-stream for plenty of real files."""
        import connector_sync as sync

        assert sync._kind("", "interview.m4a") == "recording"
        assert sync._kind("", "receipt.HEIC") == "image"
        assert sync._kind("", "notes.txt") == "document"

    def test_unknown_is_a_document_not_a_crash(self):
        import connector_sync as sync

        assert sync._kind("", "no-extension") == "document"


class TestOAuthCallback:
    """The https landing pad.

    Public and unauthenticated by necessity — a provider redirects a browser
    here with no credential of ours attached — so the properties that matter
    are about what it *cannot* be talked into doing.
    """

    def _redirect(self, query: dict) -> str:
        import connector_callback as callback

        params = {k: query[k] for k in callback.FORWARDED if k in query}
        from urllib.parse import urlencode

        return f"{callback.APP_REDIRECT}?{urlencode(params)}" if params else callback.APP_REDIRECT

    def test_forwards_the_code_and_state(self):
        target = self._redirect({"code": "abc123", "state": "xyz"})
        assert target.startswith("com.knowra.knowra://oauth/callback?")
        assert "code=abc123" in target
        assert "state=xyz" in target

    def test_forwards_a_refusal_so_the_app_can_say_so(self):
        # A user who declines consent arrives here looking like success —
        # the provider reports refusal in the redirect, not as a transport
        # error. Dropping `error` would leave the app spinning.
        target = self._redirect({"error": "access_denied"})
        assert "error=access_denied" in target

    def test_cannot_be_steered_to_another_destination(self):
        """The one thing a public redirect endpoint must never become.

        The destination is a hard-coded constant and the parameters are a
        whitelist, so a crafted link cannot make this bounce a victim
        anywhere else, nor smuggle extra parameters into the app.
        """
        target = self._redirect(
            {
                "code": "abc",
                "redirect_uri": "https://evil.example/steal",
                "next": "https://evil.example",
                "state": "xyz",
            }
        )
        assert target.startswith("com.knowra.knowra://oauth/callback?")
        assert "evil.example" not in target
        assert "redirect_uri" not in target
        assert "next=" not in target

    def test_survives_an_empty_callback(self):
        assert self._redirect({}) == "com.knowra.knowra://oauth/callback"

    def test_redirect_uri_is_https_because_google_requires_it(self):
        """Google rejects a custom scheme on any client asking for restricted
        scopes, and `drive.readonly` is restricted. This is the constraint
        that put an https hop in the flow at all."""
        from connectors import REDIRECT_URI

        assert REDIRECT_URI.startswith("https://")

    def test_one_redirect_for_every_provider(self):
        """A redirect that varied by provider — or worse, by provider *and*
        platform — is the provider-specific branching this package exists to
        keep out of the core."""
        import connectors

        assert connectors.REDIRECT_URI.endswith("/oauth/callback")
        # The bounce target is the app scheme the manifest and plist register.
        import connector_callback

        assert connector_callback.APP_REDIRECT.startswith("com.knowra.knowra://")


class TestMemoryTypeMapping:
    def test_every_work_kind_maps_to_a_real_memory_type(self):
        """The app's `MemoryType` enum has no "image" or "recording".

        Writing one is not a crash — `MemoryType.parse` degrades unknown
        values to `file` — which is exactly why it would have shipped: a Drive
        photo would appear in the library with a generic file icon and nobody
        would know why.
        """
        import connector_sync as sync

        # Mirrors memory_enums.dart. If that enum changes, this fails here
        # rather than as a wrong icon on a screen.
        app_types = {
            "text",
            "note",
            "link",
            "pdf",
            "document",
            "screenshot",
            "photo",
            "video",
            "audio",
            "voiceNote",
            "file",
        }
        assert set(sync.MEMORY_TYPE) == set(sync.KINDS)
        for kind, wire in sync.MEMORY_TYPE.items():
            assert wire in app_types, f"{kind} -> {wire} is not a MemoryType"


class TestForbiddenClassification:
    """A 403 from Drive is not evidence of revocation.

    Drive returns 403 for rate limits — not 429 — and also for an API that is
    not enabled. Treating every 403 as revocation flipped healthy accounts to
    REVOKED, which stops syncing and asks the user to reconnect. That is close
    to irreversible from their side, over a bad minute.
    """

    def _response(self, status: int, reason: str | None = None):
        import httpx

        body = {"error": {"code": status, "errors": [{"reason": reason}]}} if reason else {}
        return httpx.Response(
            status,
            json=body,
            request=httpx.Request("GET", "https://example.test"),
        )

    def _raises(self, status: int, reason: str | None = None):
        from connectors.http import raise_for

        try:
            raise_for(self._response(status, reason), what="Listing")
        except Exception as error:
            return error
        raise AssertionError("expected a ConnectorError")

    def test_401_is_revocation(self):
        error = self._raises(401)
        assert error.revoked is True

    def test_a_rate_limit_403_is_retryable_not_revocation(self):
        for reason in ("rateLimitExceeded", "userRateLimitExceeded", "quotaExceeded"):
            error = self._raises(403, reason)
            assert error.revoked is False, reason
            assert error.retryable is True, reason

    def test_a_disabled_api_is_neither(self):
        # Nothing to do with the user's grant — telling them to reconnect
        # would be a lie, and retrying forever would not help either.
        error = self._raises(403, "accessNotConfigured")
        assert error.revoked is False
        assert error.retryable is False

    def test_a_genuine_permission_403_is_revocation(self):
        for reason in ("authError", "insufficientPermissions", "forbidden"):
            error = self._raises(403, reason)
            assert error.revoked is True, reason

    def test_an_unreadable_403_fails_safe(self):
        """No reason to read: retry rather than revoke.

        Guessing "revoked" costs a working connection; guessing "retry" costs
        one failed sync. The asymmetry decides it.
        """
        error = self._raises(403)
        assert error.revoked is False
        assert error.retryable is True

    def test_a_non_json_403_does_not_crash_the_classifier(self):
        import httpx

        from connectors.http import raise_for

        response = httpx.Response(
            403,
            text="<html>Forbidden</html>",
            request=httpx.Request("GET", "https://example.test"),
        )
        try:
            raise_for(response, what="Listing")
        except Exception as error:
            assert error.revoked is False
        else:
            raise AssertionError("expected a ConnectorError")

    def test_5xx_stays_retryable(self):
        assert self._raises(503).retryable is True


class TestDeviceVault:
    """The phone vault is a source, not a connector.

    Every test here is a guard against it being treated as one — which fails
    as a KeyError deep in an async task, or, worse, as a free user being told
    their plan is full because they picked the phone in their hand.
    """

    def test_it_never_occupies_a_plan_slot(self):
        import device_vault

        drive = {"provider": "google_drive"}
        phone = {"provider": device_vault.PROVIDER}
        assert device_vault.counts_against_plan(drive) is True
        assert device_vault.counts_against_plan(phone) is False

    def test_it_is_not_in_the_oauth_registry(self):
        """`connector_for` must never be reachable with it.

        The registry is what the sync sweep and every token refresh go
        through, so a phone vault listed here would be polled for changes
        against a provider that does not exist.
        """
        import device_vault

        assert device_vault.PROVIDER not in PROFILES

    def test_the_catalogue_offers_it_alongside_the_providers(self):
        """Screen 3F's two options come from one list, distinguished by kind."""
        import device_vault

        entry = device_vault.descriptor()
        assert entry["kind"] == device_vault.KIND
        assert entry["kind"] != device_vault.OAUTH_KIND
        # A phone cannot be missing credentials the way a provider can.
        assert entry["configured"] is True

    def test_the_provider_id_matches_what_a_capture_already_carries(self):
        """`internal`, not a new id.

        The app parses a memory with no provider to `internal`, so reusing it
        means the library's source chip and the account row agree without a
        migration. Changing this string is a data migration, not a rename.
        """
        import device_vault

        assert device_vault.PROVIDER == "internal"

    def test_one_phone_vault_per_account(self):
        """The id is deterministic so a double tap cannot list two phones."""
        import device_vault

        assert device_vault.account_id("abc") == device_vault.account_id("abc")
        assert device_vault.account_id("abc") != device_vault.account_id("xyz")

    def test_a_capture_belongs_to_the_device_and_a_synced_file_does_not(self):
        import device_vault

        assert device_vault.owns_memory({"bytes": 10}) is True
        assert device_vault.owns_memory({"storageAccountId": ""}) is True
        assert device_vault.owns_memory({"storageAccountId": "acc_1"}) is False

    def test_a_device_name_cannot_be_a_payload(self):
        """It is untrusted text that lands on a document every screen reads."""
        import device_vault

        assert device_vault._clean_name("  Karnav's  iPhone ") == "Karnav's iPhone"
        assert len(device_vault._clean_name("x" * 500)) == device_vault.MAX_NAME
        assert device_vault._clean_name("   ") is None
        assert device_vault._clean_name(None) is None

    def test_the_row_reads_as_the_phone_vault_not_as_internal(self):
        """`_redact` is what 3F renders; the raw id is not a label."""
        import connector_api
        import device_vault

        row = connector_api._redact(
            "device_u1", {"provider": device_vault.PROVIDER, "state": "connected"}
        )
        assert row["label"] == device_vault.LABEL
        assert row["kind"] == device_vault.KIND

        drive = connector_api._redact("a1", {"provider": "google_drive"})
        assert drive["label"] == PROFILES["google_drive"].label
        assert drive["kind"] == device_vault.OAUTH_KIND

    def test_a_removed_provider_still_renders_rather_than_crashing(self):
        """Dropbox was removed while accounts still pointed at it."""
        import connector_api

        row = connector_api._redact("a2", {"provider": "dropbox"})
        assert row["label"] == "dropbox"

    def test_the_oauth_callables_refuse_it_by_name(self):
        """ "Unknown storage provider" would send a reader hunting a typo."""
        import connector_api
        import device_vault

        with pytest.raises(Exception) as caught:
            connector_api._provider(device_vault.PROVIDER)
        # `str()` on an HttpsError is empty; the sentence is on `.message`.
        assert "connect_device_vault" in caught.value.message

    def test_folder_selection_refuses_it(self):
        """3K is a provider screen; the phone's files come from the picker."""
        import connector_api
        import device_vault

        with pytest.raises(Exception):
            connector_api._reject_device({"provider": device_vault.PROVIDER})
        connector_api._reject_device({"provider": "google_drive"})

    def test_only_a_capture_that_brought_bytes_counts_as_a_file(self):
        """Both triggers ask this one question, so they cannot disagree.

        A create side that counted links and a delete side that did not is
        how a row ends up claiming 4 files for 3.
        """
        import device_vault

        assert device_vault._countable({"bytes": 2048}) == 2048
        # A saved link is a memory, not a file on the device.
        assert device_vault._countable({"url": "https://example.com"}) is None
        assert device_vault._countable({"bytes": 0}) is None
        # Synced from Drive: belongs to that account's counts, not the phone's.
        assert device_vault._countable({"bytes": 99, "storageAccountId": "a1"}) is None

    def test_unlisting_the_phone_does_not_claim_a_provider_revoked_it(self):
        """`_mark_revoked`'s sentence is nonsense on a row with no grant.

        The shared disconnect path would otherwise show "Access was revoked
        at the provider" against a phone that has no provider.
        """
        import device_vault

        written = {}

        class _Ref:
            def set(self, data, merge=False):
                written.update(data)

        device_vault.pause(_Ref())
        assert written["state"] == "paused"
        assert written["error"] is None


class TestOriginalsAreNeverTouched:
    """Deleting a memory deletes the index, never the user's file.

    §7/§10, and the product's plainest promise: "we keep the index, not the
    files". The protocol has `delete_file` and `move_file` because §37's
    archive flow will need them behind a per-file confirmation — until then
    a caller anywhere in the delete path would silently turn "forget this"
    into "destroy this", which is not recoverable and not what was asked.
    """

    def test_nothing_in_the_backend_deletes_a_provider_file(self):
        import pathlib

        here = pathlib.Path(__file__).parent
        callers = []
        for path in here.glob("*.py"):
            if path.name.startswith("test_"):
                continue
            for number, line in enumerate(path.read_text().splitlines(), 1):
                stripped = line.strip()
                if stripped.startswith("#") or stripped.startswith("*"):
                    continue
                if ".delete_file(" in line or ".move_file(" in line:
                    callers.append(f"{path.name}:{number}")
        assert not callers, "a provider file would be destroyed from: " + ", ".join(callers)

    def test_disconnecting_keeps_the_memories_by_default(self):
        """`deleteMemories` has to be asked for by name.

        The default branch marks them dormant, which a reconnect undoes.
        """
        import pathlib

        source = (pathlib.Path(__file__).parent / "connector_api.py").read_text()
        assert 'delete_memories = bool(req.data.get("deleteMemories"))' in source


class TestPerFileIndexing:
    """Screen 1L's row button — index one file, or drop its index."""

    def test_a_file_maps_to_the_library_type_its_icon_uses(self):
        import connector_api as api

        assert api._memory_type("image/jpeg") == "photo"
        assert api._memory_type("audio/m4a") == "audio"
        assert api._memory_type("video/mp4") == "video"
        assert api._memory_type("application/pdf") == "document"
        # Unknown types are documents rather than a fifth state: the library
        # needs an icon for every row, and "unknown" is not one it draws.
        assert api._memory_type("") == "document"

    def test_unindexing_never_reaches_the_provider(self):
        """The whole promise of the button.

        Removing the index must delete the memory and nothing at the
        provider. A `delete_file` call anywhere in this path would turn
        "forget this" into "destroy this", which is not recoverable.
        """
        import inspect

        import connector_api as api

        source = inspect.getsource(api.set_file_indexed)
        assert "delete_file" not in source
        assert "move_file" not in source
        # It deletes the memory document, and lets the existing triggers take
        # the chunks and the kept copy with it.
        assert "doc.reference.delete()" in source

    def test_indexing_the_same_file_twice_makes_one_memory(self):
        """The button is a state, not an action.

        A double tap, or a stale screen, must not leave two memories for one
        file — which would double the row in the library and index the bytes
        twice.
        """
        import inspect

        import connector_api as api

        source = inspect.getsource(api.set_file_indexed)
        assert '"created": False' in source

    def test_the_page_size_stays_inside_firestores_in_filter(self):
        """`_indexed_refs` batches by 30 because Firestore caps `in` there.

        A page larger than the chunk size still works — it just costs another
        query — but a chunk larger than 30 fails at runtime, on a screen, for
        the user.
        """
        import connector_api as api

        assert api.FILE_PAGE <= 30

    def test_the_phone_vault_has_no_provider_to_list(self):
        import connector_api as api
        import device_vault

        with pytest.raises(Exception):
            api._reject_device({"provider": device_vault.PROVIDER})


class TestVaultBreakdown:
    """Screen 1R's chips — what the vault holds, grouped as a person names it."""

    def test_the_groups_cover_every_indexable_type(self):
        """A type in no group is a file that vanishes from the breakdown.

        The chips are meant to add up to the headline count, so a type the
        pipeline can produce but the grouping forgets would make the vault
        look smaller than it is.
        """
        import account_api

        grouped = {t for kinds in account_api.MEMORY_GROUPS.values() for t in kinds}
        # Mirrors MemoryType in the app, minus the two the product dropped.
        produced = {
            "document",
            "pdf",
            "file",
            "link",
            "audio",
            "voiceNote",
            "video",
            "photo",
            "screenshot",
        }
        assert produced - grouped == set()

    def test_no_type_is_counted_twice(self):
        import account_api

        flat = [t for kinds in account_api.MEMORY_GROUPS.values() for t in kinds]
        assert len(flat) == len(set(flat))

    def test_the_removed_note_path_gets_no_chip(self):
        """v3 took write-a-note out of the product.

        Counting notes would advertise a capture route the app no longer
        offers; the memories themselves still answer questions.
        """
        import account_api

        flat = {t for kinds in account_api.MEMORY_GROUPS.values() for t in kinds}
        assert "note" not in flat
        assert "text" not in flat

    def test_each_group_fits_one_firestore_in_filter(self):
        import account_api

        for kinds in account_api.MEMORY_GROUPS.values():
            assert 0 < len(kinds) <= 30


class TestFileListing:
    """Screen 1L's list, and the two counts in its header."""

    def test_the_counts_are_account_wide_not_page_wide(self):
        """ "842 OF 10,412 INDEXED" cannot be derived from thirty rows.

        Both numbers come from outside the page — the total from the figure
        the folder selection already wrote to the account, the indexed count
        from an aggregation — so a client holding one page can still print
        the header truthfully.
        """
        import inspect

        import connector_api as api

        source = inspect.getsource(api.list_provider_files)
        assert '"totalCount": int(data.get("fileCount") or 0)' in source
        assert "_indexed_total(uid, account_id)" in source

    def test_paging_is_by_token_not_offset(self):
        """A file added mid-scroll shifts every offset below it.

        The user would see a row twice, or miss one — on the screen whose
        whole job is telling them which files are indexed.
        """
        import inspect

        import connector_api as api

        source = inspect.getsource(api.list_provider_files)
        assert 'req.data.get("pageToken")' in source
        # No cursor arithmetic anywhere: the provider's opaque token is
        # passed through untouched. (The word "offset" appears in the
        # docstring explaining why, so this looks for the call, not the word.)
        assert ".offset(" not in source
        assert 'req.data.get("offset")' not in source

    def test_the_breadcrumb_is_built_from_what_the_account_knows(self):
        import connector_api as api

        folders = [{"id": "f1", "name": "Contracts"}, {"id": "f2", "name": "Finance"}]
        assert api._breadcrumb("Google Drive", folders, "f1") == "Drive › Contracts"
        assert api._breadcrumb("Google Drive", folders, "f2") == "Drive › Finance"
        # A folder the selection does not name still gets a usable caption
        # rather than a dangling separator.
        assert api._breadcrumb("Google Drive", folders, "root") == "Drive"
        assert api._breadcrumb("Google Drive", [], "anything") == "Drive"
