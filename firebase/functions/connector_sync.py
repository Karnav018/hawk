"""The first index, and keeping it current afterwards.

Screen 3L is a window onto one `indexJobs` document: the worker writes
progress, the client streams the document. No polling endpoint, no websocket —
the same trick the rest of the app uses.

Two workers:

* **`on_index_job_created`** — the first pass over the folders the user chose
  on 3K. Enumerates, dedupes, and writes one `memories` document per file,
  which the existing `on_memory_created` trigger then processes. This function
  never downloads anything; it decides *what* to ingest and lets the pipeline
  do the ingesting.
* **`sync_connected_accounts`** — §39, on a schedule. Asks each provider what
  changed since the stored cursor and reconciles.
"""

from __future__ import annotations

import asyncio
from datetime import UTC, datetime

from firebase_admin import firestore
from firebase_functions import options, scheduler_fn
from firebase_functions.firestore_fn import Event, on_document_created

import connector_oauth as oauth
import device_vault
from connector_api import PROVIDER_SECRETS
from connectors import ConnectorError, ConnectorState, connector_for, source_url

#: Firestore caps a batch at 500 writes; 400 leaves room for the job update
#: that rides along with each flush.
BATCH = 400

#: Progress is written every this many files rather than every file. At one
#: write per file a 10,000-file Drive is 10,000 writes purely to animate a
#: progress bar — the dominant cost of the whole first index.
PROGRESS_EVERY = 25

#: Coarse kinds, matching the rows screen 3L shows. Deliberately not the full
#: `MemoryType` enum: 3L groups by the kind of *work* — reading, transcribing,
#: looking at — because that is what explains why one row is slower.
KINDS = {
    "document": (
        "application/pdf",
        "application/msword",
        "text/",
        "application/vnd.openxmlformats",
    ),
    "image": ("image/",),
    "recording": ("audio/", "video/"),
}

STAGE = {
    "document": "READING DOCUMENTS",
    "image": "LOOKING AT IMAGES",
    "recording": "TRANSCRIBING AUDIO",
}

#: The kind names above group 3L's progress rows by the kind of *work*. They
#: are NOT memory types — the app's `MemoryType` enum has no "image" or
#: "recording", and writing one lands as the catch-all `file`, so a Drive
#: photo would show in the library with a generic file icon.
MEMORY_TYPE = {
    "document": "document",
    "image": "photo",
    "recording": "audio",
}


def _kind(mime: str, name: str) -> str:
    for kind, prefixes in KINDS.items():
        if any(mime.startswith(p) for p in prefixes):
            return kind
    # No usable mime type, so the extension is the only signal left — Drive
    # returns `application/octet-stream` for plenty of real files. Guessing
    # "document" is the cheap failure: a misfiled image still gets indexed,
    # it just lands in the wrong progress row.
    suffix = name.rsplit(".", 1)[-1].lower() if "." in name else ""
    if suffix in {"jpg", "jpeg", "png", "heic", "gif", "webp"}:
        return "image"
    if suffix in {"mp3", "m4a", "wav", "aac", "mp4", "mov", "m4v"}:
        return "recording"
    return "document"


@on_document_created(
    document="indexJobs/{jobId}",
    region="us-central1",
    memory=options.MemoryOption.MB_512,
    timeout_sec=540,
    max_instances=10,
    secrets=PROVIDER_SECRETS,
)
def on_index_job_created(event: Event) -> None:
    snapshot = event.data
    if snapshot is None:
        return

    job = snapshot.reference
    data = snapshot.to_dict() or {}
    uid = data.get("userId")
    account_id = data.get("accountId")
    if not uid or not account_id:
        return

    db = firestore.client()
    account = db.collection("storageAccounts").document(account_id)
    now = datetime.now(UTC)
    job.update({"state": "enumerating", "startedAt": now, "updatedAt": now})

    try:
        counts = asyncio.run(_enumerate(db, job, account, data))
    except ConnectorError as error:
        job.update(
            {
                "state": "failed",
                "error": str(error),
                "updatedAt": datetime.now(UTC),
            }
        )
        account.update(
            {
                "state": ConnectorState.REVOKED if error.revoked else ConnectorState.ERROR,
                "error": {"code": "sync", "message": str(error)},
                "updatedAt": datetime.now(UTC),
            }
        )
        return

    finished = datetime.now(UTC)
    job.update(
        {
            # "complete" means every file has a memory document. Those
            # documents are still being processed by the ingestion pipeline —
            # which is exactly what 3L's "You can start asking as soon as the
            # first ones land" promises.
            "state": "complete",
            "progress": {"discovered": counts["total"], "processed": counts["total"], "failed": 0},
            "byKind": counts["by_kind"],
            "stage": None,
            "finishedAt": finished,
            "updatedAt": finished,
        }
    )
    account.update(
        {
            "state": ConnectorState.CONNECTED,
            "lastSyncedAt": finished,
            "fileCount": counts["total"],
            "updatedAt": finished,
        }
    )


async def _enumerate(db, job, account, data: dict) -> dict:
    """Walk the chosen folders, writing one memory per new file."""
    provider = data["provider"]
    uid = data["userId"]
    account_id = data["accountId"]
    connector = connector_for(provider)
    token = await oauth.access_token(account, account_id=account_id, provider=provider)

    # §16 — dedupe before spending anything. One read of the account's known
    # provider file ids, held in memory, beats a Firestore lookup per file.
    seen = {
        doc.to_dict().get("sourceRef")
        for doc in db.collection("memories")
        .where("userId", "==", uid)
        .where("storageAccountId", "==", account_id)
        .select(["sourceRef"])
        .stream()
    }

    by_kind: dict[str, int] = {}
    total = 0
    batch = db.batch()
    pending = 0

    for folder in data.get("folders", []):
        cursor: str | None = None
        while True:
            page = await connector.list_files(token, folder_id=folder["id"], page_token=cursor)
            for f in page.files:
                if f.deleted or f.id in seen:
                    continue
                seen.add(f.id)

                kind = _kind(f.mime_type, f.name)
                by_kind[kind] = by_kind.get(kind, 0) + 1
                total += 1

                batch.set(
                    db.collection("memories").document(),
                    {
                        "userId": uid,
                        "title": f.name,
                        "type": MEMORY_TYPE[kind],
                        # Kept alongside `type` because 3L groups by the kind
                        # of work, which is a coarser question than what the
                        # library renders an icon for.
                        "workKind": kind,
                        # The pipeline's own starting state, same as a manual
                        # capture — one state machine, two entry points.
                        "status": "uploaded",
                        "recallState": "active",
                        "storageAccountId": account_id,
                        "provider": provider,
                        # §10 — a pointer, never a copy. The original stays
                        # where the user already keeps it.
                        "sourceRef": f.id,
                        # Stored, not derived at read time: the library reads
                        # memory documents straight from Firestore, so a file
                        # whose link only exists inside a callable is a file
                        # the library cannot open.
                        "sourceUrl": source_url(provider, f.id),
                        "sourceFolderId": folder["id"],
                        "sourceAvailable": True,
                        "mimeType": f.mime_type,
                        "bytes": f.bytes,
                        "contentHash": f.content_hash,
                        "capturedAt": f.modified_at or datetime.now(UTC),
                        "createdAt": datetime.now(UTC),
                        "updatedAt": datetime.now(UTC),
                    },
                )
                pending += 1

                if pending >= BATCH:
                    batch.commit()
                    batch = db.batch()
                    pending = 0
                    _report(job, total, by_kind, kind)
                elif total % PROGRESS_EVERY == 0:
                    _report(job, total, by_kind, kind)

            if not page.has_more:
                break
            cursor = page.cursor

    if pending:
        batch.commit()

    # Take a change cursor now, not at the start: anything modified during the
    # walk was already picked up by the walk itself, and a cursor from before
    # it would replay all of it on the next sync.
    changes = await connector.get_changes(token, cursor=None)
    account.update({"syncCursor": changes.cursor, "updatedAt": datetime.now(UTC)})

    return {"total": total, "by_kind": by_kind}


def _report(job, total: int, by_kind: dict[str, int], kind: str) -> None:
    job.update(
        {
            "state": "processing",
            "progress.discovered": total,
            "progress.processed": total,
            "byKind": by_kind,
            "stage": STAGE.get(kind),
            "updatedAt": datetime.now(UTC),
        }
    )


@scheduler_fn.on_schedule(
    schedule="every 6 hours",
    region="us-central1",
    memory=options.MemoryOption.MB_512,
    timeout_sec=540,
    secrets=PROVIDER_SECRETS,
)
def sync_connected_accounts(event: scheduler_fn.ScheduledEvent) -> None:
    """§39 — reconcile every live connection against its provider.

    Polling rather than provider webhooks: Drive's push channels expire every
    few days and need a public endpoint to renew, which is a lot of moving
    parts for a product where "your file appears within a few hours" is fine.
    Worth revisiting when it stops being fine.
    """
    db = firestore.client()
    accounts = (
        db.collection("storageAccounts")
        .where("state", "in", [ConnectorState.CONNECTED, ConnectorState.SYNCING])
        .stream()
    )

    for doc in accounts:
        data = doc.to_dict() or {}
        # The phone vault is a source, not a connection: nothing to poll, no
        # token to refresh, and `connector_for("internal")` does not exist.
        # Skipped here rather than excluded from the query because the query
        # selects on state, and the phone vault is legitimately CONNECTED.
        if device_vault.is_device(data.get("provider")):
            continue
        try:
            asyncio.run(_sync_one(db, doc.reference, doc.id, data))
        except ConnectorError as error:
            doc.reference.update(
                {
                    "state": ConnectorState.REVOKED if error.revoked else ConnectorState.ERROR,
                    "error": {"code": "sync", "message": str(error)},
                    "updatedAt": datetime.now(UTC),
                }
            )
        except Exception as error:
            # One bad account must not stop the others from syncing — but a
            # silently skipped account is a connection that quietly stops
            # updating, so the reason is recorded on the account itself, where
            # both the UI and a later investigation can find it.
            doc.reference.update(
                {
                    "state": ConnectorState.ERROR,
                    "error": {"code": "sync", "message": str(error)[:500]},
                    "updatedAt": datetime.now(UTC),
                }
            )
            continue


async def _sync_one(db, ref, account_id: str, data: dict) -> None:
    provider = data["provider"]
    uid = data["userId"]
    folders = {f["id"] for f in data.get("indexedFolders", [])}
    if not folders:
        return

    connector = connector_for(provider)
    token = await oauth.access_token(ref, account_id=account_id, provider=provider)
    changes = await connector.get_changes(token, cursor=data.get("syncCursor"))

    batch = db.batch()
    pending = 0
    #: Files this sync added by itself. The app announces them — the one
    #: thing Hawk does without being asked (`Snack.assistant`).
    added = 0

    for f in changes.files:
        existing = [
            doc
            for doc in db.collection("memories")
            .where("userId", "==", uid)
            .where("storageAccountId", "==", account_id)
            .where("sourceRef", "==", f.id)
            .limit(1)
            .stream()
        ]

        if f.deleted:
            # §39 — the memory survives the file. What we learned from it is
            # often the only remaining record that it existed.
            for doc in existing:
                batch.update(
                    doc.reference,
                    {"sourceAvailable": False, "updatedAt": datetime.now(UTC)},
                )
                pending += 1
        elif existing:
            doc = existing[0]
            if (doc.to_dict() or {}).get("contentHash") != f.content_hash:
                # Content changed: the old extraction describes a file that no
                # longer exists, so it goes back through the pipeline.
                batch.update(
                    doc.reference,
                    {
                        "status": "uploaded",
                        "contentHash": f.content_hash,
                        "bytes": f.bytes,
                        "updatedAt": datetime.now(UTC),
                    },
                )
                pending += 1
        elif f.parent_id in folders:
            # New, and inside a folder the user actually chose. Files added
            # outside the indexed scope are ignored, not quietly opted in.
            batch.set(
                db.collection("memories").document(),
                {
                    "userId": uid,
                    "title": f.name,
                    "type": MEMORY_TYPE[_kind(f.mime_type, f.name)],
                    "status": "uploaded",
                    "recallState": "active",
                    "storageAccountId": account_id,
                    "provider": provider,
                    "sourceRef": f.id,
                    "sourceUrl": source_url(provider, f.id),
                    "sourceFolderId": f.parent_id,
                    "sourceAvailable": True,
                    "mimeType": f.mime_type,
                    "bytes": f.bytes,
                    "contentHash": f.content_hash,
                    "capturedAt": f.modified_at or datetime.now(UTC),
                    "createdAt": datetime.now(UTC),
                    "updatedAt": datetime.now(UTC),
                },
            )
            pending += 1
            added += 1

        if pending >= BATCH:
            batch.commit()
            batch = db.batch()
            pending = 0

    if pending:
        batch.commit()

    finished = datetime.now(UTC)
    update = {
        "syncCursor": changes.cursor,
        "lastSyncedAt": finished,
        "updatedAt": finished,
    }
    if added:
        # Only when something arrived, so the timestamp itself is the news:
        # the app compares it with the last one it announced, and a quiet
        # sync every six hours never re-raises an old "found 3 new files".
        update["lastSyncAdded"] = added
        update["lastSyncAddedAt"] = finished
    ref.update(update)
