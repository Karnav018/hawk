"""The phone itself as a storage source — the second option on screen 3F.

Onboarding offers two ways to fill a vault, and only one of them is a
connector. Google Drive is an OAuth grant we hold a refresh token for; the
phone vault is the device the app is already running on. They are peers in
the product and nothing alike in the plumbing, which is exactly why this
lives outside `connectors/`: there is no authorize URL, no token to seal, no
cursor to sweep, and `connector_for("internal")` must never be reached with
it.

What it *is* is a row in `storageAccounts`, and that is deliberate:

* Screen 3F renders sources from the catalogue. Without a row, picking the
  phone vault would look — on the next visit, or from any other screen —
  exactly like never having picked it.
* `Continue` on 3F unlocks on "has any connection". Device-only is a
  supported product, not a deferral: the skip copy says so in as many words.
  Someone who chose their phone should reach the end of onboarding having
  *chosen* something rather than having skipped.
* Disconnecting then means something specific — stop offering this phone as
  a source — and is the same gesture as disconnecting Drive.

Three rules keep it from being mistaken for a connector:

1. **It never occupies a plan slot.** `connectedAccounts` prices cloud
   connections. Charging someone a slot for the phone in their hand would
   spend the free tier's only one the instant they picked a file, and then
   the upsell would be for permission to use their own device.
2. **The sync sweep skips it.** Nothing to poll: files arrive because the
   user picked them, not because we went looking.
3. **Its provider id is `internal`** — the same id a captured-here memory
   already resolves to in the app — so the library's source chip and this
   row cannot disagree about where a file came from.
"""

from __future__ import annotations

from datetime import UTC, datetime

from firebase_admin import firestore
from google.api_core import exceptions as gcloud

from connectors import ConnectorState, ScopeLevel

ACCOUNTS = "storageAccounts"

#: The wire id, shared with `StorageProvider.internal` in the app.
#:
#: Not a new string. A capture written by the phone carries no `provider` at
#: all and the client parses that absence to `internal`, so reusing the id
#: means the account row and every memory it stands for already agree —
#: where a fresh id like `device` would have needed a migration to say the
#: same thing.
PROVIDER = "internal"

LABEL = "Phone vault"

#: What 3F prints under the name before anything is known about it.
TAGLINE = "Files on this device"

#: Which of the catalogue's two kinds of row this is.
#:
#: The app needs the distinction because the two do genuinely different
#: things on tap — one opens a browser for consent, the other opens the
#: system file picker — and branching on the provider id would put
#: `if provider == 'internal'` back into the UI, which is the thing the
#: catalogue exists to avoid.
KIND = "device"
OAUTH_KIND = "oauth"

#: A device name is user-visible text from an untrusted client. Capped so a
#: 40 KB "name" cannot be parked in a document every screen reads.
MAX_NAME = 60

_DEFAULT_NAME = "This device"


def account_id(uid: str) -> str:
    """One phone vault per account, at a predictable address.

    Deterministic rather than auto-generated so connecting is idempotent
    without a query, and so a double tap on 3F cannot leave two rows for one
    device. Predictability costs nothing here: `firestore.rules` denies every
    client write to `storageAccounts` and scopes reads to the owner, so
    guessing the id of somebody else's row buys no access to it.
    """
    return f"device_{uid}"


def is_device(provider: object) -> bool:
    return str(provider or "") == PROVIDER


def counts_against_plan(account: dict) -> bool:
    """Whether this account occupies one of the plan's connection slots."""
    return not is_device(account.get("provider"))


def owns_memory(data: dict) -> bool:
    """True when this memory came from the device rather than a connector.

    The marker is an absence: `storageAccountId` is written by the connector
    sync and by nothing else, so a memory without one was captured here. That
    is a weaker signal than a positive flag would be, and it is the one that
    is true of every capture already in the database rather than only of the
    ones written after this shipped.
    """
    return not str(data.get("storageAccountId") or "")


def descriptor() -> dict:
    """The catalogue entry for screen 3F.

    `configured: true`, always. An OAuth provider can be missing credentials
    and so report itself unavailable with a reason; a phone cannot be
    misconfigured out of existence.
    """
    return {
        "id": PROVIDER,
        "label": LABEL,
        "tagline": TAGLINE,
        "kind": KIND,
        "configured": True,
    }


def connect(uid: str, *, device_name: object = None) -> tuple[str, dict]:
    """Make this phone a source. Idempotent. Returns `(id, data)`.

    Reconnecting after a disconnect is the same call: the row comes back to
    CONNECTED and keeps the counts it had, because the files it stands for
    never went anywhere — they are in the user's own vault, not behind a
    grant somebody revoked.
    """
    now = datetime.now(UTC)
    ref = firestore.client().collection(ACCOUNTS).document(account_id(uid))
    snapshot = ref.get()
    existing = snapshot.to_dict() or {}

    payload: dict = {
        "userId": uid,
        "provider": PROVIDER,
        "kind": KIND,
        "displayName": _clean_name(device_name) or existing.get("displayName") or _DEFAULT_NAME,
        "state": ConnectorState.CONNECTED,
        # READ and nothing else. The manage level is about moving and
        # deleting files at a provider, and the phone's own files are reached
        # through the OS picker, which grants what it grants per file.
        "scopeLevel": ScopeLevel.READ,
        # There is no cursor and no polling. Left false so the sweep's own
        # guard is belt and braces rather than the only thing standing
        # between this row and `connector_for("internal")`.
        "syncEnabled": False,
        "error": None,
        "updatedAt": now,
    }
    if not snapshot.exists:
        payload |= {"connectedAt": now, "fileCount": 0, "bytes": 0}

    ref.set(payload, merge=True)
    return ref.id, {**existing, **payload}


def pause(ref) -> None:
    """Unlist this phone as a source, without lying about why.

    The shared disconnect path ends in `_mark_revoked`, which stamps
    "Access was revoked at the provider." — true of a Drive whose grant the
    user pulled, and nonsense on a row that never had a provider or a grant.
    PAUSED is the state that actually happened: the user stopped offering
    this device, and turning it back on is theirs to do.
    """
    ref.set(
        {
            "state": ConnectorState.PAUSED,
            "syncEnabled": False,
            "error": None,
            "updatedAt": datetime.now(UTC),
        },
        merge=True,
    )


def note_capture(uid: str, memory: dict) -> None:
    """Count one device capture against the phone vault row.

    Takes the memory document rather than a size so that both triggers ask
    the same question in the same place — the create side and the delete side
    disagreeing about what counts is how a row ends up claiming 4 files for 3.

    `update`, not `set(merge=True)`: a capture made before the phone vault
    was ever connected must not conjure the row. Someone who skipped 3F has
    said they do not want this source listed, and a photo they dropped in
    afterwards is not them changing their mind.
    """
    size = _countable(memory)
    if size is None:
        return

    ref = firestore.client().collection(ACCOUNTS).document(account_id(uid))
    try:
        ref.update(
            {
                "fileCount": firestore.Increment(1),
                "bytes": firestore.Increment(size),
                "updatedAt": datetime.now(UTC),
            }
        )
    except gcloud.NotFound:
        # The ordinary case: no phone vault connected, so there is nothing to
        # count. Silent, because otherwise every capture by every user who
        # skipped 3F writes a log line saying nothing happened.
        return
    except Exception as error:
        # Anything else is a counter on a settings row, which is not worth
        # failing an ingestion that has already done the expensive work.
        print(f"[knowra] device_vault note_failed uid={uid} {error}")


def forget_capture(uid: str, memory: dict) -> None:
    """Give back what `note_capture` took. Never below zero.

    Decrementing blind would drift negative the first time a delete ran twice
    — a retried trigger, or a memory deleted while its ingestion was still in
    flight — and a row claiming −3 files is a bug a user can see.
    """
    freed = _countable(memory)
    if freed is None:
        return

    ref = firestore.client().collection(ACCOUNTS).document(account_id(uid))

    @firestore.transactional
    def _apply(tx, ref) -> None:
        snapshot = ref.get(transaction=tx)
        if not snapshot.exists:
            return
        data = snapshot.to_dict() or {}
        tx.set(
            ref,
            {
                "fileCount": max(0, int(data.get("fileCount") or 0) - 1),
                "bytes": max(0, int(data.get("bytes") or 0) - freed),
                "updatedAt": datetime.now(UTC),
            },
            merge=True,
        )

    try:
        _apply(firestore.client().transaction(), ref)
    except Exception as error:
        # The row is gone, or the transaction lost its retries. Either way a
        # stale count must not fail a delete the user has already seen
        # succeed — the memory is what they asked to remove.
        print(f"[knowra] device_vault forget_failed uid={uid} {error}")


def _countable(memory: dict) -> int | None:
    """The size to count for this memory, or None if it is not the phone's.

    A link or a typed note captured on the device is a memory but not a
    *file*, and the row says "Files on this device" — so only a capture that
    brought bytes with it moves these numbers.
    """
    if not owns_memory(memory):
        return None
    size = int(memory.get("bytes") or 0)
    return size if size > 0 else None


def _clean_name(raw: object) -> str | None:
    """A device name as the client sent it, made safe to display."""
    if raw is None:
        return None
    name = " ".join(str(raw).split())
    name = "".join(c for c in name if c.isprintable())
    return name[:MAX_NAME] or None
