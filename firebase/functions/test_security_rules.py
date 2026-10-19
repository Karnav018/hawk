"""Assertions about `firestore.rules` as text.

Not a substitute for the emulator's rules test suite, which needs Java and a
running emulator. These catch the failure that actually happens in practice: a
new collection added to the model and never added to the rules, which then
falls through to the catch-all deny and is only noticed as a mysterious
`permission-denied` in the app.
"""

import pathlib
import re

RULES = pathlib.Path(__file__).resolve().parents[1] / "firestore.rules"
TEXT = RULES.read_text()


def block(header: str) -> str:
    """The body of one `match` block, brace-matched.

    Slicing to the first `}` looks equivalent and is not: it cuts inside the
    first nested block and silently returns a fragment that happens not to
    contain the line under test, so the assertion fails for the wrong reason.
    """
    start = TEXT.index(header)

    # Count from the brace that opens the *block*, which is the last one on the
    # header line. Starting at `start` counts the path wildcard's braces —
    # `match /chunks/{chunkId}` opens and closes one — so the scan terminates
    # on the path and returns nothing useful.
    line_end = TEXT.index("\n", start)
    opening = TEXT.rindex("{", start, line_end)

    depth = 0
    for i in range(opening, len(TEXT)):
        if TEXT[i] == "{":
            depth += 1
        elif TEXT[i] == "}":
            depth -= 1
            if depth == 0:
                return TEXT[start : i + 1]
    raise AssertionError(f"unbalanced braces after {header}")


def test_the_catch_all_denies() -> None:
    """New collections must be locked by default, not open by default."""
    assert "match /{document=**}" in TEXT
    tail = TEXT[TEXT.index("match /{document=**}") :]
    assert "allow read, write: if false" in tail


def test_every_collection_the_client_touches_has_a_rule() -> None:
    for collection in ("users", "memories", "chunks", "conversations"):
        assert f"match /{collection}/" in TEXT, collection


def test_vectors_are_never_client_writable() -> None:
    """A writable embedding is a poisoned index."""
    assert "allow write: if false" in block("match /chunks/")


def test_sign_in_challenges_are_entirely_server_side() -> None:
    """A readable challenge collection hands out every code in the system."""
    assert "allow read, write: if false" in block("match /emailChallenges/")


def test_storage_tokens_are_never_client_readable() -> None:
    assert "allow write: if false" in block("match /storageAccounts/")


def test_a_client_cannot_grant_itself_a_plan() -> None:
    """The subscription document is Admin-SDK only.

    A client that could write its own tier would grant itself Premium.
    """
    assert "allow write: if false" in block("match /subscription/")


def test_a_client_cannot_mark_a_memory_ready() -> None:
    """Status belongs to the pipeline.

    A memory written straight to `ready` would be answerable with no
    embeddings behind it — it would simply return nothing, confidently.
    """
    assert re.search(r"request\.resource\.data\.status == 'uploaded'", TEXT)
    assert re.search(r"request\.resource\.data\.recallState == 'active'", TEXT)


def test_ownership_is_checked_on_every_rule() -> None:
    # This is what replaces `WHERE user_id = :caller`. Its absence does not
    # leak here — it denies — but a rule without it is still a bug.
    allows = [
        line
        for line in TEXT.splitlines()
        if line.strip().startswith("allow") and "if false" not in line
    ]
    assert allows
    for line in allows:
        assert "isOwner" in line or "signedIn" in line, line


def test_oauth_grants_are_denied_to_the_owner_too() -> None:
    """The single most consequential rule in the file.

    A refresh token is a permanent key to the user's whole drive. It lives in
    a subcollection precisely because `allow read` on the parent cannot
    redact — a rule grants the entire document or none of it — so a token
    stored as a *field* on `storageAccounts` would be readable by any client
    holding the owner's ID token.
    """
    accounts = block("match /storageAccounts/{accountId}")
    assert "match /private/{document=**}" in accounts
    private = accounts[accounts.index("match /private/{document=**}") :]
    assert "allow read, write: if false" in private


def test_the_account_row_itself_is_not_client_writable() -> None:
    """Connecting goes through a callable, which is where the free tier's
    one-account limit is enforced. A writable row makes the limit cosmetic."""
    accounts = block("match /storageAccounts/{accountId}")
    header, _, rest = accounts.partition("match /private")
    assert "allow write: if false" in header
    assert not re.search(r"allow (create|update|write):\s*if\s+isOwner", header)


def test_pkce_verifiers_are_server_only() -> None:
    """The verifier is the half of the PKCE pair that makes an intercepted
    redirect useless. A readable challenge collection hands it back."""
    assert "allow read, write: if false" in block("match /oauthChallenges/{challengeId}")


def test_index_jobs_are_readable_so_3l_needs_no_polling() -> None:
    jobs = block("match /indexJobs/{jobId}")
    assert "allow read: if isOwner(resource.data.userId)" in jobs
    assert "allow write: if false" in jobs


def test_the_profile_is_an_allowlist_on_create_as_well_as_update() -> None:
    """Screen 3J writes with `set(merge: true)`.

    On a project without Identity Platform there is no blocking trigger to
    seed the document first, so that write lands as a *create* — and an
    unrestricted create is an unrestricted update with one extra step. The
    field that matters is `filedBytes`: the server-owned file-storage meter
    is read straight off this document, and a client that could seed it
    negative would grant itself unlimited storage.
    """
    users = block("match /users/{userId}")
    header, _, _ = users.partition("match /subscription")
    create = header[header.index("allow create") :]
    assert "hasOnly(['name', 'inputPreference', 'onboardedAt', 'updatedAt'])" in create
    assert "filedBytes" not in create


def test_the_input_preference_is_pinned_to_what_the_app_can_route_on() -> None:
    """It picks the home screen — orb or chat.

    A third value is a user with no home screen, so it is refused at the
    write rather than guessed at by every reader.
    """
    users = block("match /users/{userId}")
    header, _, _ = users.partition("match /subscription")
    assert header.count("request.resource.data.inputPreference in ['voice', 'typing']") == 2


def test_onboarding_cannot_be_ended_by_the_client() -> None:
    """`storageSetupAt` is what the router reads to leave the welcome run.

    Writable, it would let a client skip screens 3F–3L by writing a date.
    """
    users = block("match /users/{userId}")
    header, _, _ = users.partition("match /subscription")
    writable = [line for line in header.splitlines() if "hasOnly(" in line]
    assert writable
    for line in writable:
        assert "storageSetupAt" not in line, line
