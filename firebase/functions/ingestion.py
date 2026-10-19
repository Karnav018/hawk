"""The ingestion pipeline, triggered by the capture itself.

A Firestore trigger rather than a queue: the client writes a memory document
and the pipeline starts, so there is no enqueue step to fail independently of
the write. The document *is* the job record, and its `status` is the state
machine from architecture §22.

    uploaded -> processing -> extracted -> embedding
             -> indexed -> ready        (failed reachable from any of them)

Three outcomes, deliberately distinguished — because "this memory cannot
answer questions" has three very different causes and the user deserves to
know which:

* **ready** — extracted, chunked, embedded, searchable.
* **extracted** with `indexNote` — the content is held but this *type* cannot
  be read yet (video needs its audio track stripped). Not a failure; a capability gap.
* **failed** with `error` — something broke. Retryable.

Collapsing the middle case into `failed` was the previous behaviour and it was
wrong: a user who captures a photo would see an error for working software.
"""

from __future__ import annotations

import asyncio
from datetime import UTC, datetime

from firebase_admin import firestore, storage
from firebase_functions import options
from firebase_functions.firestore_fn import Event, on_document_created

import billing
import chunk_store
import chunking
import device_vault
import extraction
import file_vault
import gemini
import index_budget

#: Firestore caps a batch at 500 writes. A very long document can exceed that
#: in chunks alone, so the writes are flushed in windows.
BATCH = 400

#: Absolute ceiling per memory, independent of plan.
#:
#: Not a cost control — `index_budget` does that, and its per-plan share is
#: larger than this. This is a retrieval and latency ceiling: past a few
#: hundred passages from one document, KNN candidates get dominated by a
#: single source and one capture can crowd out everything else the user owns.
MAX_CHUNKS = 400


@on_document_created(
    document="memories/{memoryId}",
    region="us-central1",
    memory=options.MemoryOption.GB_1,
    # Media work is slow; the default 60s would kill a large PDF mid-parse.
    timeout_sec=540,
    # A cap, so a bulk import cannot fan out into unbounded spend.
    max_instances=20,
    secrets=["GEMINI_API_KEY"],
)
def on_memory_created(event: Event) -> None:
    """Take a freshly captured memory through to searchable."""
    snapshot = event.data
    if snapshot is None:
        return

    data = snapshot.to_dict() or {}
    uid = data.get("userId")
    if not uid:
        return

    db = firestore.client()
    ref = snapshot.reference

    # Stamp the expiry at capture, from the plan in force now. The retention
    # sweep then reads one indexed field instead of joining every memory
    # against a subscription.
    subscription = (
        db.collection("users").document(uid).collection("subscription").document("current").get()
    )
    entitlements = billing.resolve_for_user(
        uid, subscription.to_dict() if subscription.exists else None
    )
    created = billing._as_datetime(data.get("createdAt") or datetime.now(UTC))
    expires = billing.recall_expiry(created, entitlements)

    # Count it against the phone vault row, if this user has one. Before the
    # work rather than after it, and keyed on the capture rather than on the
    # eventual outcome: a PDF nothing could be extracted from is still a file
    # the user put in their vault from this device, and a row that counted
    # only the successes would quietly disagree with the library.
    device_vault.note_capture(uid, data)

    ref.update(
        {
            "status": "processing",
            "recallExpiresAt": expires,
            "updatedAt": datetime.now(UTC),
        }
    )

    try:
        extracted = _read(data, economy=billing.reads_economy(entitlements.tier))

        if _settled_unread(ref, data, extracted):
            return

        if not extracted.ok:
            ref.update(
                {
                    "status": "extracted",
                    "indexNote": "Nothing readable in this capture.",
                    "chunkCount": 0,
                    "updatedAt": datetime.now(UTC),
                }
            )
            return

        all_chunks = chunking.split(extracted.text)
        chunks = all_chunks[:MAX_CHUNKS]
        capped_by_ceiling = len(chunks) < len(all_chunks)
        if not chunks:
            ref.update(
                {
                    "status": "extracted",
                    "indexNote": "Too short to index.",
                    "chunkCount": 0,
                    "updatedAt": datetime.now(UTC),
                }
            )
            return

        # Trim to what the plan can afford BEFORE embedding — the embedding
        # call is the cost, so checking afterwards would mean paying for
        # vectors we then refuse to store.
        texts, note = index_budget.fit(uid, entitlements, [c.text for c in chunks])
        # From here `note` is only ever the *quota's* note: the per-file
        # ceiling below writes its own `ceiling_note`. That keeps "the plan's
        # allowance cut this short" answerable as `note is not None`, which
        # is stored as `overQuota` for screen 1X's library-row lock — so the
        # app never has to infer it from the wording of a sentence. The
        # ceiling is a different thing: no upgrade raises it.

        if not texts:
            _discard_upload(data)
            ref.update(
                {
                    "status": "extracted",
                    "indexNote": note or "Nothing left to index.",
                    "overQuota": note is not None,
                    "chunkCount": 0,
                    "storagePath": None,
                    "sourceFilename": data.get("title"),
                    "updatedAt": datetime.now(UTC),
                }
            )
            return

        chunks = chunks[: len(texts)]
        ceiling_note = (
            f"Indexed the first {len(chunks)} of {len(all_chunks)} parts. "
            "The whole file is still in the library."
            if note is None and capped_by_ceiling
            else None
        )

        # No embedding here any more. The vectors live on the user's phone
        # (`local_index`): the server stores the chunk *text*, each signed-in
        # device embeds it through `embed_texts` and keeps the vectors in
        # its own index. Nothing about a chunk's content leaves this
        # collection as a vector.
        ref.update({"status": "embedding", "updatedAt": datetime.now(UTC)})

        _write_chunks(
            db,
            uid=uid,
            memory_id=ref.id,
            memory=data,
            chunks=chunks,
            recall_state=data.get("recallState", "active"),
        )
        index_budget.record(uid, texts)

        # The file is kept, inside the plan's allowance.
        #
        # This used to delete the upload here, on the grounds that the phone
        # already had the file. True, and not enough: a phone's copy does not
        # survive a reinstall, a lost device, or a second device, so a vault
        # that deleted its copy could not hand anything back. `file_vault`
        # moves the object out of `captures/` into a durable path and counts
        # it against `Entitlements.file_bytes`.
        #
        # Over the ceiling the object is dropped and `kept_note` says so. The
        # memory is indexed either way — the index is what answers questions,
        # and declining to answer because a bucket is full would punish the
        # user twice.
        upload_path = extraction.storage_path(data)
        kept_path: str | None = None
        kept_note: str | None = None
        if upload_path:
            kept_path, kept_note = file_vault.keep(
                uid,
                ref.id,
                upload_path=upload_path,
                filename=str(data.get("sourceFilename") or data.get("title") or "file"),
                entitlements=entitlements,
            )

        ref.update(
            {
                "status": "ready",
                "readWith": extracted.read_with,
                "chunkCount": len(chunks),
                # Carries the truncation reason when there was one, so a
                # partially indexed memory says so rather than looking whole.
                # A file that could not be kept is reported the same way.
                "indexNote": note or ceiling_note or kept_note,
                "overQuota": note is not None,
                "error": None,
                # Where the kept object lives, or None when there is none to
                # read. The filename survives either way, because the library
                # row and any citation still have to name what this came from.
                "storagePath": kept_path,
                "sourceFilename": data.get("title"),
                "originalLocation": "vault" if kept_path else "device",
                "indexedAt": datetime.now(UTC),
                "updatedAt": datetime.now(UTC),
            }
        )

    except gemini.ModelError as error:
        # Separated from a generic failure because the remedy differs: a
        # missing key or a rate limit is configuration or patience, not a bad
        # capture. `retryable` is recorded so a future sweep can tell which
        # memories are worth another attempt.
        ref.update(
            {
                "status": "failed",
                "error": str(error)[:500],
                "errorRetryable": error.retryable,
                "updatedAt": datetime.now(UTC),
            }
        )
        raise
    except Exception as exc:
        # The failure is recorded on the document itself: a stuck ingestion has
        # to be diagnosable after the fact, not only while it is happening.
        ref.update(
            {
                "status": "failed",
                "error": str(exc)[:500],
                "errorRetryable": False,
                "updatedAt": datetime.now(UTC),
            }
        )
        raise


def _settled_unread(ref, data: dict, extracted: extraction.Extracted) -> bool:
    """Close a capture that will never be read, and say whether it was one.

    Two verdicts, both final, neither a crash:

    * **failed** — a failure the user can act on, like a link to a page that
      refuses readers. Recorded for the app to show and returned from cleanly
      rather than raised: raising would log an outage for a page that simply
      said no. Not retryable — it will say no again.
    * **held** — this *type* cannot be read yet. The row stays in the library
      and says why it cannot answer. The upload goes, because "unsupported"
      is a permanent verdict about the type — there is nothing to retry, and
      the bytes would sit in the bucket forever.
    """
    if extracted.failure is not None:
        ref.update(
            {
                "status": "failed",
                "error": extracted.failure,
                "errorRetryable": False,
                "updatedAt": datetime.now(UTC),
            }
        )
        return True

    if extracted.unsupported is not None:
        _discard_upload(data)
        ref.update(
            {
                "status": "extracted",
                "indexNote": extracted.unsupported,
                "chunkCount": 0,
                "storagePath": None,
                "sourceFilename": data.get("title"),
                "updatedAt": datetime.now(UTC),
            }
        )
        return True

    return False


def _discard_upload(memory: dict) -> bool:
    """Delete the transported file. Returns whether there was one to delete.

    Best effort: the text is already chunked and embedded by this point, so a
    bucket that refuses the delete is a stray object to clean up later, not a
    reason to fail an ingestion that otherwise worked.
    """
    path = extraction.storage_path(memory)
    if not path:
        return False
    try:
        storage.bucket().blob(path).delete()
        return True
    except Exception as error:
        print(f"[knowra] upload_discard_failed path={path} error={error}")
        return False


def _read(memory: dict, *, economy: bool = False) -> extraction.Extracted:
    """Extract text, downloading the uploaded file only when one is needed.

    The download is deliberate and bounded: `plan` answers from the document
    alone wherever it can, so a note or a link never touches Storage, and a
    type with no route is refused before any bytes move.
    """
    # Links go out to the web rather than to Storage, and they are the one
    # type whose text is neither in the document nor in our bucket.
    if str(memory.get("type") or "") == "link":
        return asyncio.run(extraction.extract_link(memory))

    planned = extraction.plan(memory)
    if planned is not None:
        return planned

    path = extraction.storage_path(memory)
    if not path:
        return extraction.Extracted(text="", unsupported="Nothing uploaded for this capture yet.")

    blob = storage.bucket().blob(path)
    if not blob.exists():
        # The upload was started and never finished, or was deleted. Recorded
        # as a reason rather than a failure — there is nothing to retry.
        return extraction.Extracted(text="", unsupported="That upload is no longer available.")

    return asyncio.run(extraction.extract_file(memory, blob.download_as_bytes(), economy=economy))


def _write_chunks(
    db,
    *,
    uid: str,
    memory_id: str,
    memory: dict,
    chunks: list[chunking.Chunk],
    recall_state: str,
) -> None:
    """Persist chunk text — and only text.

    Replaces any previous chunks for this memory first. Re-ingestion happens —
    a Drive file changes, a plan upgrade revives a dormant memory — and
    leaving the old chunks behind means the same passage answers twice, from
    two versions of the truth.

    **No `embedding` field.** Vectors are computed and kept on each device
    (see `local_index`); a chunk document is the text plus what retrieval
    needs to filter it. Devices notice new chunks through a listener on this
    collection and embed them themselves.
    """
    chunk_store.delete_for_memory(db, uid=uid, memory_id=memory_id)
    batch = db.batch()
    pending = 0

    now = datetime.now(UTC)
    title = memory.get("title")

    for chunk in chunks:
        batch.set(
            db.collection("chunks").document(),
            {
                "userId": uid,
                "memoryId": memory_id,
                # Denormalised onto the chunk on purpose. Retrieval reads
                # hundreds of these and must not fan out a memory lookup per
                # candidate just to know whether it is still recallable.
                "recallState": recall_state,
                "memoryTitle": title,
                "memoryType": memory.get("type"),
                # For §24's date window. Denormalised for the same reason as
                # recallState: retrieval reads hundreds of these and must not
                # fan out a memory lookup per candidate.
                "capturedAt": memory.get("capturedAt") or memory.get("createdAt"),
                "text": chunk.text,
                "chunkIndex": chunk.index,
                "charStart": chunk.start,
                "createdAt": now,
                # What a phone's delta sync asks for: chunks changed since it
                # last looked. The commit time, not this instance's clock, so
                # every writer's order is the server's order.
                "updatedAt": firestore.SERVER_TIMESTAMP,
            },
        )
        pending += 1
        if pending >= BATCH:
            batch.commit()
            batch = db.batch()
            pending = 0

    if pending:
        batch.commit()
