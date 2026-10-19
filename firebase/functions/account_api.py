"""The account itself: what it holds, how to pause it, how to end it.

Three callables, and the distance between the second and the third is the
whole design:

* `account_summary` — one read for the profile screen, so it does not need
  four round trips to say "Standard, 214 memories, 2 accounts".
* `deactivate_account` — reversible. Disconnects every storage account and
  stops all indexing, keeps every memory. Signing in again undoes it.
* `delete_account` — final. Purges the derived layer, the profile, and the
  auth record.

The spec's rule is *never silently delete*, and the fork above is how that is
honoured: the destructive path is a different function with a different name
that the client has to ask for by typing a word, and the reversible path is
the one offered first. Anything that ends a user's access defaults to the
option they can walk back.

Originals are never touched. They live in the user's own storage (§7/§10) —
this backend holds embeddings, extracted text and pointers, so deleting an
account deletes what *we* made, and the user's files stay exactly where they
already were. That is worth stating plainly to the user too: "your files are
not deleted" is the truthful and reassuring thing to say, and it is only
truthful because of that architecture.
"""

from __future__ import annotations

import asyncio
from datetime import UTC, datetime

from firebase_admin import auth, firestore, storage
from firebase_functions import https_fn, options

import billing
import connector_api
import device_vault
import file_vault
import index_budget
import usage
from api import _email_of, _entitlements, _require_uid
from connectors.base import ConnectorState

#: Deleting connector tokens means revoking them at the provider, which needs
#: that provider's client secret.
PROVIDER_SECRETS = connector_api.PROVIDER_SECRETS

#: Typed, not tapped.
#:
#: A confirmation dialog is one tap from the button that opened it, and the
#: button that opened it is one tap from a scroll. Requiring the word makes
#: deletion something a person *decides* rather than something a thumb does.
DELETE_PHRASE = "DELETE"

#: The breakdown screen 1R shows, mapped from the pipeline's own types.
#:
#: `text` and `note` are deliberately absent: v3 removed the write-a-note
#: path from the product, so counting them would advertise a capture route
#: the app no longer offers. Anything captured before that still answers
#: questions — it just does not get a chip of its own.
MEMORY_GROUPS = {
    "documents": ["document", "pdf", "file", "link"],
    "recordings": ["audio", "voiceNote", "video"],
    "images": ["photo", "screenshot"],
}

#: How many documents go in one batch. Firestore's hard limit is 500 writes;
#: 450 leaves room for the account document and its token subdocument.
BATCH = 450


def _profile(uid: str):
    return firestore.client().collection("users").document(uid)


# ---------------------------------------------------------------- summary


@https_fn.on_call(region="us-central1", memory=options.MemoryOption.MB_256)
def account_summary(req: https_fn.CallableRequest) -> dict:
    """Everything the profile screen shows, in one call.

    Counts come from Firestore aggregation queries, which are billed per
    *batch of index entries read* rather than per document — so counting
    thousands of memories costs about what reading one costs. Streaming them
    to length them would have been the obvious client-side version and would
    have cost a read per memory, every time the screen opened.
    """
    uid = _require_uid(req)
    email = _email_of(req)
    entitlements = _entitlements(uid, email=email)
    db = firestore.client()

    def count(query) -> int:
        try:
            result = query.count().get()
            return int(result[0][0].value)
        except Exception:
            # A count that fails is a missing number on a settings screen,
            # not a reason to fail the screen. Shown as "—".
            return -1

    memories = db.collection("memories").where("userId", "==", uid)
    accounts = db.collection("storageAccounts").where("userId", "==", uid)

    profile = _profile(uid).get()
    data = profile.to_dict() or {}

    # The phone vault is a storage account row but not a *connection*, and
    # the profile prints this number against the plan's limit — so it is
    # subtracted here rather than filtered in the query, which would need a
    # composite index and would drop rows written before `provider` existed.
    # A single get by a deterministic id is cheaper than either.
    has_device = (
        db.collection("storageAccounts").document(device_vault.account_id(uid)).get().exists
    )
    connected = count(accounts)
    if has_device and connected > 0:
        connected -= 1

    # Screen 1R prints the vault as a breakdown — "248 documents · 64
    # recordings · 1,204 images". Three aggregation queries rather than one
    # scan: Firestore bills a count by index entries read, so asking three
    # times costs about what asking once does, where streaming every memory
    # to tally them client-side is a read per memory every time the screen
    # opens.
    #
    # The groups are the ones a person would name, not the pipeline's eleven
    # types. Somebody looking at their vault thinks in documents, recordings
    # and images; `pdf` and `screenshot` are implementation detail.
    by_kind = {
        group: count(memories.where("type", "in", kinds)) for group, kinds in MEMORY_GROUPS.items()
    }

    return {
        "email": email,
        "name": data.get("name"),
        "createdAt": _iso(data.get("createdAt")),
        "status": data.get("status", "active"),
        # Defaulted, not passed through. The app routes its home screen on
        # this — orb or chat — and a null would send someone who chose
        # typing to the voice screen on a device that had not synced yet.
        "inputPreference": data.get("inputPreference") or "voice",
        "deviceVault": has_device,
        "tier": entitlements.tier,
        "isTestAccount": billing.is_test_account(uid, email=email),
        # On unless the user turned it off (`marketing.subscribed`).
        "marketingOptIn": data.get("marketingOptIn") is not False,
        "counts": {
            "memories": count(memories),
            "indexed": count(memories.where("recallState", "==", "active")),
            "dormant": count(memories.where("recallState", "==", "dormant")),
            "accounts": connected,
            "byKind": by_kind,
        },
        "index": index_budget.allowance(uid, entitlements),
        "files": file_vault.allowance(uid, entitlements),
        "queries": usage.peek(uid, entitlements),
    }


def _iso(value) -> str | None:
    if value is None:
        return None
    if isinstance(value, str):
        return value
    try:
        return value.isoformat()
    except AttributeError:
        return None


# ------------------------------------------------------------ deactivate


@https_fn.on_call(
    region="us-central1",
    memory=options.MemoryOption.MB_512,
    timeout_sec=300,
    secrets=PROVIDER_SECRETS,
)
def deactivate_account(req: https_fn.CallableRequest) -> dict:
    """Pause the account. Reversible, and nothing is lost.

    What it actually does, in order:

    1. Marks the profile deactivated, *first* — so if step 2 times out
       halfway through, the account is already closed rather than half
       closed. The expensive work is retryable; the state change is not.
    2. Disconnects every storage account, without deleting memories. That is
       `disconnect_account`'s non-destructive branch: tokens revoked at the
       provider, memories marked dormant and unavailable.
    3. Leaves memories, chunks and conversations exactly as they are.

    Reactivation is a sign-in: the app calls `reactivate_account`, and the
    user reconnects storage the same way they did the first time. There is no
    stored token to bring back, by design — a paused account holding live
    OAuth refresh tokens is a paused account that can still read your Drive.
    """
    uid = _require_uid(req)
    now = datetime.now(UTC)

    _profile(uid).set(
        {
            "status": "deactivated",
            "deactivatedAt": now,
            "updatedAt": now,
        },
        merge=True,
    )

    db = firestore.client()
    disconnected = 0
    failures = 0
    for doc in db.collection("storageAccounts").where("userId", "==", uid).stream():
        data = doc.to_dict() or {}
        try:
            asyncio.run(
                connector_api._revoke_quietly(data.get("provider", ""), doc.reference, doc.id)
            )
            doc.reference.collection("private").document("oauth").delete()
            doc.reference.set(
                {
                    # `state`, not `status`.
                    #
                    # The rest of the connector layer reads `state` — see
                    # `ConnectorState` and the composite index on
                    # (state, updatedAt) — and writing `status` here left the
                    # account reading as CONNECTED after its token had been
                    # revoked and deleted. The sync sweep would keep
                    # selecting it and the app would keep showing it as live.
                    "state": ConnectorState.REVOKED,
                    "syncEnabled": False,
                    "updatedAt": now,
                },
                merge=True,
            )
            disconnected += 1
        except Exception:
            # A provider that will not accept a revocation does not block the
            # deactivation — the local token is gone either way, so nothing
            # in this system can use it. Counted so the app can say so.
            failures += 1

    # Cancel queued indexing. A job that runs after deactivation would write
    # embeddings for an account that has asked us to stop.
    cancelled = 0
    batch = db.batch()
    pending = 0
    # `state` again, and these are the values the job actually moves through:
    # queued -> enumerating -> ... -> complete / failed. "running" was never
    # one of them, so this query matched nothing and no job was ever
    # cancelled — a deactivated account's indexing would have carried on.
    jobs = (
        db.collection("indexJobs")
        .where("userId", "==", uid)
        .where("state", "in", ["queued", "enumerating", "indexing"])
    )
    for job in jobs.stream():
        batch.update(job.reference, {"state": "cancelled", "updatedAt": now})
        cancelled += 1
        pending += 1
        if pending == BATCH:
            batch.commit()
            batch = db.batch()
            pending = 0
    if pending:
        batch.commit()

    return {
        "status": "deactivated",
        "disconnected": disconnected,
        "revokeFailures": failures,
        "cancelledJobs": cancelled,
    }


@https_fn.on_call(region="us-central1", memory=options.MemoryOption.MB_256)
def reactivate_account(req: https_fn.CallableRequest) -> dict:
    """Undo a deactivation.

    Deliberately trivial: the only thing deactivation changed that survives
    is the flag. Storage has to be reconnected by hand, which the app says on
    the way in rather than discovering later that nothing is syncing.
    """
    uid = _require_uid(req)
    now = datetime.now(UTC)
    _profile(uid).set(
        {"status": "active", "deactivatedAt": None, "updatedAt": now},
        merge=True,
    )
    return {"status": "active", "needsStorage": True}


# ---------------------------------------------------------------- delete


@https_fn.on_call(
    region="us-central1",
    memory=options.MemoryOption.MB_512,
    timeout_sec=540,
    secrets=PROVIDER_SECRETS,
)
def delete_account(req: https_fn.CallableRequest) -> dict:
    """Erase the account. Not reversible, and it says so.

    Order matters here too, and it is the opposite of deactivation's:

    * The **auth record goes last**. While it exists the caller can retry a
      partial delete; once it is gone, anything left behind is orphaned with
      no session that could ever clean it up. So data first, identity last.
    * Tokens are revoked **before** the documents holding them are deleted,
      because a deleted refresh token is not a revoked one — it just stops
      being ours. A provider grant nobody can see is worse than one they can.

    Subcollections are not deleted by deleting a parent in Firestore; every
    level is walked explicitly. The one that bites is `users/{uid}` — its
    `subscription` and `usage` children survive their parent silently, and a
    re-registered uid would inherit them.
    """
    uid = _require_uid(req)
    phrase = str(req.data.get("confirm") or "").strip()
    if phrase != DELETE_PHRASE:
        raise https_fn.HttpsError(
            https_fn.FunctionsErrorCode.FAILED_PRECONDITION,
            f'Type "{DELETE_PHRASE}" to confirm.',
        )

    db = firestore.client()
    deleted = {
        "memories": 0,
        "chunks": 0,
        "conversations": 0,
        "accounts": 0,
        "files": 0,
    }

    # 1. Revoke at the providers first, while we still hold the tokens.
    for doc in db.collection("storageAccounts").where("userId", "==", uid).stream():
        data = doc.to_dict() or {}
        try:
            asyncio.run(
                connector_api._revoke_quietly(data.get("provider", ""), doc.reference, doc.id)
            )
        except Exception as error:
            # Logged, not raised. A provider that will not take the
            # revocation must not stop the deletion — but it does mean a
            # grant may still be live on their side, which is the one thing
            # here worth being able to find again in the logs.
            print(f"[knowra] delete_account revoke_failed account={doc.id} {error}")
        doc.reference.collection("private").document("oauth").delete()
        doc.reference.delete()
        deleted["accounts"] += 1

    # 2. The derived layer. Chunks are the bulk of it — one memory can be 400.
    deleted["chunks"] = _purge(db.collection("chunks").where("userId", "==", uid))
    deleted["memories"] = _purge(db.collection("memories").where("userId", "==", uid))

    # 3. Conversations, each with a `messages` subcollection of its own.
    for doc in db.collection("conversations").where("userId", "==", uid).stream():
        _purge(doc.reference.collection("messages"))
        doc.reference.delete()
        deleted["conversations"] += 1

    _purge(db.collection("indexJobs").where("userId", "==", uid))
    _purge(db.collection("storeSubscriptions").where("userId", "==", uid))

    # 4. Every file kept for this user.
    #
    # By prefix, not by walking memories: the memories are already gone by
    # now, and an object whose memory was lost some other way would otherwise
    # never be reachable again — billed forever, visible to nobody.
    deleted["files"] = _purge_storage(uid)

    # 5. The profile and its subcollections.
    profile = _profile(uid)
    for name in ("subscription", "usage"):
        _purge(profile.collection(name))
    profile.delete()

    # 6. The identity, last.
    try:
        auth.delete_user(uid)
    except auth.UserNotFoundError:
        # Already gone — a retried delete. Everything above is idempotent, so
        # this is a success, not a failure.
        pass

    return {"status": "deleted", "deleted": deleted}


def _purge_storage(uid: str) -> int:
    """Delete every object under this user's prefix. Returns the count.

    `storage.rules` scopes all access by the `users/{uid}/` segment, so that
    prefix is exactly this user's data and nothing else's.
    """
    try:
        bucket = storage.bucket()
        blobs = list(bucket.list_blobs(prefix=f"users/{uid}/"))
    except Exception as error:
        print(f"[knowra] delete_account storage_list_failed uid={uid} {error}")
        return 0

    removed = 0
    for blob in blobs:
        try:
            blob.delete()
            removed += 1
        except Exception as error:
            print(f"[knowra] delete_account storage_delete_failed {blob.name} {error}")
    return removed


def _purge(query) -> int:
    """Delete everything a query returns, in batches. Returns the count.

    Streams rather than fetching: a vault with 100k chunks would not fit in
    memory, and the stream is resumable where a list is not.
    """
    db = firestore.client()
    total = 0
    batch = db.batch()
    pending = 0
    for doc in query.stream():
        batch.delete(doc.reference)
        total += 1
        pending += 1
        if pending == BATCH:
            batch.commit()
            batch = db.batch()
            pending = 0
    if pending:
        batch.commit()
    return total
