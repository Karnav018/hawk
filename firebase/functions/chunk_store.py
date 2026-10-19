"""The chunk documents of one memory, and how they leave.

Ingestion writes them; this is the one place that removes them. There is more
than one way a memory dies — the app's delete, a connector disconnect, a
re-index that replaces it — and the chunks are what make a memory *findable*:
left behind, a deleted file keeps answering questions from every phone's
index and from the server's passage lookup, and its bytes stay charged
against the plan.

**Soft, then hard.** A chunk is first marked `deleted`, its text emptied and
`updatedAt` bumped, so that a phone syncing only what changed since it last
looked (`IndexSync`'s delta sync) *sees* the deletion — a hard delete is an
absence, and an absence never appears in a "changed since" query. The marked
documents are removed for good by [sweep_deleted_chunks] once every phone has
had [TOMBSTONE_DAYS] to notice; a phone away longer than that does a full
reconcile instead.
"""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

from firebase_admin import firestore
from firebase_functions import options, scheduler_fn

import index_budget

#: Firestore's ceiling on writes per batch, with room to spare.
BATCH = 400

#: Firestore's ceiling on values in one `in` filter.
IN_LIMIT = 30

#: How long a deleted chunk stays visible to delta sync. The phone does a full
#: reconcile at least weekly (`IndexSync.reconcileEvery`), so this is four
#: times that.
TOMBSTONE_DAYS = 30


def delete_for_memory(db, *, uid: str, memory_id: str) -> int:
    """Mark every chunk of [memory_id] deleted and give its bytes back.

    Returns how many were marked. Chunks already marked are skipped — their
    bytes were given back the first time, and releasing them again would
    understate what the plan is using.
    """
    existing = (
        db.collection("chunks")
        .where("memoryId", "==", memory_id)
        .select(["text", "deleted"])
        .stream()
    )
    batch = db.batch()
    pending = 0
    reclaimed = 0
    removed = 0
    for doc in existing:
        data = doc.to_dict() or {}
        if data.get("deleted"):
            continue
        reclaimed += index_budget.chunk_cost(str(data.get("text") or ""))
        batch.update(
            doc.reference,
            {
                "deleted": True,
                "text": "",
                "embedding": firestore.DELETE_FIELD,
                "updatedAt": firestore.SERVER_TIMESTAMP,
            },
        )
        pending += 1
        removed += 1
        if pending >= BATCH:
            batch.commit()
            batch = db.batch()
            pending = 0
    if pending:
        batch.commit()
    if reclaimed:
        index_budget.release(uid, reclaimed)
    return removed


def set_recall_state(db, memory_ids: list[str], state: str) -> int:
    """Set the chunks of [memory_ids] to [state]. Returns how many changed.

    Retention and the connectors change a memory's `recallState`; the phone's
    index and the server's passage lookup read the *chunk's*. So the chunks
    follow, with `updatedAt` bumped for delta sync. Chunks already in [state]
    and chunks marked deleted are left alone.
    """
    ids = list(dict.fromkeys(memory_ids))
    batch = db.batch()
    pending = 0
    changed = 0
    for start in range(0, len(ids), IN_LIMIT):
        docs = (
            db.collection("chunks")
            .where("memoryId", "in", ids[start : start + IN_LIMIT])
            .select(["recallState", "deleted"])
            .stream()
        )
        for doc in docs:
            data = doc.to_dict() or {}
            if data.get("deleted") or data.get("recallState") == state:
                continue
            batch.update(
                doc.reference,
                {"recallState": state, "updatedAt": firestore.SERVER_TIMESTAMP},
            )
            pending += 1
            changed += 1
            if pending >= BATCH:
                batch.commit()
                batch = db.batch()
                pending = 0
    if pending:
        batch.commit()
    return changed


def sweep(db, *, now: datetime) -> int:
    """Hard-delete chunks marked deleted more than [TOMBSTONE_DAYS] ago."""
    cutoff = now - timedelta(days=TOMBSTONE_DAYS)
    swept = 0
    while True:
        docs = list(
            db.collection("chunks")
            .where("deleted", "==", True)
            .where("updatedAt", "<", cutoff)
            .select([])
            .limit(BATCH)
            .stream()
        )
        if not docs:
            return swept
        batch = db.batch()
        for doc in docs:
            batch.delete(doc.reference)
        batch.commit()
        swept += len(docs)
        if len(docs) < BATCH:
            return swept


@scheduler_fn.on_schedule(
    schedule="every day 03:30",
    region="us-central1",
    memory=options.MemoryOption.MB_256,
    timeout_sec=540,
)
def sweep_deleted_chunks(event: scheduler_fn.ScheduledEvent) -> None:
    """Remove chunk tombstones every phone has had time to see."""
    swept = sweep(firestore.client(), now=datetime.now(UTC))
    print(f"[knowra] sweep_deleted_chunks swept={swept}")
