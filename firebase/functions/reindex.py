"""Bringing already-captured memories into the index.

The ingestion trigger fires on document *create*, so every memory captured
before the embedding pipeline existed stopped at `extracted` and is invisible
to search — permanently, with no event left to wake it. Which means the
earliest things a user saved are the ones that cannot be found, and they have
no way to know why.

Two entry points, same worker:

* **`reindex_memory`** — a callable, for one memory the user is looking at.
* **`reindex_backlog`** — scheduled, for the ones nobody is looking at.

Deliberately *not* a Firestore trigger on update. Re-embedding writes to the
memory document, which would re-fire the trigger, and a self-triggering
embedding loop is an unbounded bill.
"""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

from firebase_admin import firestore
from firebase_functions import https_fn, options, scheduler_fn

import billing
import chunking
import extraction
import gemini
import index_budget
from ingestion import MAX_CHUNKS, _write_chunks

#: Statuses worth another attempt.
#:
#: `extracted` is the backlog: read but never embedded. `failed` is retried
#: only when the failure said it was retryable — a rate limit deserves another
#: go, a malformed capture does not, and retrying it forever is how a bad
#: document becomes a recurring cost.
STALE = ("extracted", "failed")

#: How many per scheduled run. Small on purpose: each is an embedding call on
#: a free-tier quota, and a sweep that exhausts the quota starves the live
#: capture path that users are actually waiting on.
PER_RUN = 25

#: Don't re-attempt something that just failed — give the cause time to clear.
COOLDOWN = timedelta(hours=6)

SECRETS = ["GEMINI_API_KEY"]


def _entitlements(db, uid: str) -> billing.Entitlements:
    snapshot = (
        db.collection("users").document(uid).collection("subscription").document("current").get()
    )
    return billing.resolve_for_user(uid, snapshot.to_dict() if snapshot.exists else None)


def _reindex(db, doc) -> str:
    """Take one memory from `extracted`/`failed` to `ready`. Returns outcome."""
    data = doc.to_dict() or {}
    uid = data.get("userId")
    if not uid:
        return "skipped"

    from ingestion import _discard_upload, _read

    entitlements = _entitlements(db, uid)
    extracted = _read(data, economy=billing.reads_economy(entitlements.tier))
    if extracted.unsupported is not None or not extracted.ok:
        # A permanent verdict, so the transported bytes go with it.
        _discard_upload(data)
        # Still not indexable. Recorded so the sweep stops picking it up
        # every six hours forever.
        doc.reference.update(
            {
                "status": "extracted",
                "indexNote": extracted.unsupported or "Nothing readable in this capture.",
                "storagePath": None,
                "sourceFilename": data.get("title"),
                "reindexedAt": datetime.now(UTC),
                "updatedAt": datetime.now(UTC),
            }
        )
        return "unsupported"

    chunks = chunking.split(extracted.text)[:MAX_CHUNKS]
    if not chunks:
        doc.reference.update(
            {
                "status": "extracted",
                "indexNote": "Too short to index.",
                "reindexedAt": datetime.now(UTC),
                "updatedAt": datetime.now(UTC),
            }
        )
        return "unsupported"

    texts, note = index_budget.fit(uid, entitlements, [c.text for c in chunks])
    if not texts:
        doc.reference.update(
            {
                "status": "extracted",
                "indexNote": note or "Nothing left to index.",
                "reindexedAt": datetime.now(UTC),
                "updatedAt": datetime.now(UTC),
            }
        )
        return "unsupported"

    chunks = chunks[: len(texts)]

    # Text only; each device embeds it — see `ingestion._write_chunks`.
    _write_chunks(
        db,
        uid=uid,
        memory_id=doc.id,
        memory=data,
        chunks=chunks,
        recall_state=data.get("recallState", "active"),
    )
    index_budget.record(uid, texts)

    # Same rule as first ingestion: the upload was transport. §7 — originals
    # stay where they already live.
    discarded = _discard_upload(data)

    doc.reference.update(
        {
            "status": "ready",
            "readWith": extracted.read_with,
            "chunkCount": len(chunks),
            "indexNote": note,
            "error": None,
            "errorRetryable": None,
            "storagePath": None if discarded else extraction.storage_path(data),
            "sourceFilename": data.get("title"),
            "originalLocation": "device" if discarded else None,
            "indexedAt": datetime.now(UTC),
            "reindexedAt": datetime.now(UTC),
            "updatedAt": datetime.now(UTC),
        }
    )
    return "indexed"


@https_fn.on_call(
    region="us-central1",
    memory=options.MemoryOption.GB_1,
    timeout_sec=300,
    secrets=SECRETS,
)
def reindex_memory(req: https_fn.CallableRequest) -> dict:
    """Re-index one of the caller's own memories.

    For the case where a user is looking at a row that says it cannot be
    searched and wants to do something about it.
    """
    if req.auth is None or not req.auth.uid:
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.UNAUTHENTICATED, "Sign in first.")
    uid = req.auth.uid
    memory_id = str(req.data.get("memoryId") or "")
    if not memory_id:
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.INVALID_ARGUMENT, "Which memory?")

    db = firestore.client()
    doc = db.collection("memories").document(memory_id).get()
    data = doc.to_dict() if doc.exists else None

    # Missing and someone else's are the same error, so this cannot be used
    # to discover whether a memory id exists.
    if not data or data.get("userId") != uid:
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.NOT_FOUND, "No such memory.")

    try:
        outcome = _reindex(db, doc)
    except gemini.ModelError as error:
        raise https_fn.HttpsError(
            https_fn.FunctionsErrorCode.UNAVAILABLE
            if error.retryable
            else https_fn.FunctionsErrorCode.FAILED_PRECONDITION,
            str(error),
        ) from error

    return {"outcome": outcome}


@scheduler_fn.on_schedule(
    schedule="every 6 hours",
    region="us-central1",
    memory=options.MemoryOption.GB_1,
    timeout_sec=540,
    secrets=SECRETS,
)
def reindex_backlog(event: scheduler_fn.ScheduledEvent) -> None:
    """Work through memories the pipeline never reached.

    Ordered oldest-first so the backlog drains rather than churning the same
    recent documents, and capped per run so a sweep cannot spend the quota
    the live capture path needs.
    """
    db = firestore.client()
    now = datetime.now(UTC)
    counts = {"indexed": 0, "unsupported": 0, "skipped": 0, "failed": 0}

    for status in STALE:
        remaining = PER_RUN - sum(counts.values())
        if remaining <= 0:
            break

        docs = (
            db.collection("memories")
            .where("status", "==", status)
            .order_by("createdAt")
            .limit(remaining * 3)
            .stream()
        )

        for doc in docs:
            if sum(counts.values()) >= PER_RUN:
                break

            data = doc.to_dict() or {}

            # Already judged unindexable — don't spend a call re-learning it.
            if data.get("indexNote"):
                continue
            if status == "failed" and not data.get("errorRetryable"):
                continue

            if _too_soon(data.get("reindexedAt"), now):
                continue

            try:
                counts[_reindex(db, doc)] += 1
            except gemini.ModelError as error:
                # A rate limit means stop, not skip: continuing would burn
                # the rest of the run against a quota that is already gone.
                doc.reference.update(
                    {
                        "reindexedAt": now,
                        "error": str(error)[:500],
                        "errorRetryable": error.retryable,
                        "updatedAt": now,
                    }
                )
                counts["failed"] += 1
                if error.retryable:
                    print(f"[knowra] reindex_backlog stopping early: {error}")
                    print(f"[knowra] reindex_backlog {counts}")
                    return
            except Exception as error:
                doc.reference.update(
                    {
                        "status": "failed",
                        "error": str(error)[:500],
                        "errorRetryable": False,
                        "reindexedAt": now,
                        "updatedAt": now,
                    }
                )
                counts["failed"] += 1

    print(f"[knowra] reindex_backlog {counts}")


def _too_soon(last: object, now: datetime) -> bool:
    """True if this memory was attempted inside the cooldown.

    An unreadable timestamp returns False — attempting one memory again
    slightly early is a wasted call, whereas treating a bad value as "too
    soon" would exclude it from the sweep forever.
    """
    if last is None:
        return False
    try:
        return now - billing._as_datetime(last) < COOLDOWN
    except (TypeError, ValueError, OSError):
        return False
