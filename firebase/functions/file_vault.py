"""Keeping the user's own files, in Firebase Storage — architecture §7/§10.

This reverses an earlier decision, and the reversal is the interesting part.

The upload used to be **transport only**: bytes went to the bucket so a Cloud
Function could read them, and the object was deleted the moment extraction
succeeded. The reasoning was sound — the phone already had the file, so a
second copy was the product paying to store something the user already owned.

What that reasoning missed is that a *vault* is judged on whether it can hand
the thing back. The phone's copy is one device's copy: it does not survive a
reinstall, a lost phone, or a second device, and nothing captured on a laptop
could ever be opened on a tablet. So the file is kept, deliberately, and the
cost is bounded by `Entitlements.file_bytes` rather than by throwing the file
away.

Three rules hold this together:

* **A quota, enforced before the write is kept.** Over the ceiling the object
  is discarded and the memory says so. The capture is still indexed and still
  answers questions — only the copy is declined.
* **Accounting is server-owned.** `filedBytes` lives on the user document,
  which `firestore.rules` denies to clients, so the number cannot be edited by
  the thing it limits.
* **Deleting a memory deletes its file.** Enforced by a trigger rather than by
  every call site remembering, because the one that forgets is the one that
  leaves a user paying for bytes they cannot see.
"""

from __future__ import annotations

from firebase_admin import firestore, storage
from firebase_functions import options
from firebase_functions.firestore_fn import Event, on_document_deleted

import billing
import chunk_store
import device_vault


#: Where a kept file lives. Under the uid because `storage.rules` scopes every
#: read and write by that segment, and under the memory id because that is
#: what the app asks for and what the delete trigger can name without a
#: lookup.
def object_path(uid: str, memory_id: str, filename: str) -> str:
    return f"users/{uid}/originals/{memory_id}/{_safe(filename)}"


def _safe(name: str) -> str:
    """Strips what would change the meaning of an object path.

    A filename reaches here from a phone's file picker — user-supplied data.
    `..` and `/` in an object name do not traverse in GCS the way they do on
    a filesystem, but they do produce paths that no longer match the
    `users/{uid}/` prefix the rules are written against.
    """
    cleaned = "".join(c for c in name if c.isprintable() and c not in "/\\")
    cleaned = cleaned.replace("..", "_").strip()
    return cleaned or "original"


def used(uid: str) -> int:
    """Bytes of kept files already spent. Server-owned."""
    doc = firestore.client().collection("users").document(uid).get()
    data = doc.to_dict() if doc.exists else None
    return int((data or {}).get("filedBytes") or 0)


def allowance(uid: str, entitlements: billing.Entitlements) -> dict:
    """What the profile and the paywall show for kept files."""
    limit = entitlements.file_bytes
    spent = used(uid)
    return {
        "usedBytes": spent,
        "limitBytes": limit,
        "remainingBytes": None if limit is None else max(0, limit - spent),
    }


def fits(uid: str, entitlements: billing.Entitlements, size: int) -> bool:
    limit = entitlements.file_bytes
    if limit is None:
        return True
    if limit <= 0:
        return False
    return used(uid) + size <= limit


def record(uid: str, size: int) -> None:
    firestore.client().collection("users").document(uid).set(
        {"filedBytes": firestore.Increment(size)}, merge=True
    )


def release(uid: str, size: int) -> None:
    """Gives the bytes back. Never below zero.

    `Increment(-size)` alone would drift negative the first time a delete ran
    twice — a retried trigger, or a memory deleted while its ingestion was
    still in flight — and a negative balance silently grants free storage.
    """
    if size <= 0:
        return
    ref = firestore.client().collection("users").document(uid)

    @firestore.transactional
    def _apply(tx, ref):
        snapshot = ref.get(transaction=tx)
        current = int((snapshot.to_dict() or {}).get("filedBytes") or 0)
        tx.set(ref, {"filedBytes": max(0, current - size)}, merge=True)

    _apply(firestore.client().transaction(), ref)


def human_size(n: int) -> str:
    """1 GB, 100 GB, 512 MB — whole units, the way a plan is sold."""
    gib = 1024**3
    if n >= gib:
        return f"{n / gib:g} GB"
    return f"{max(1, round(n / 1024**2))} MB"


def keep(
    uid: str,
    memory_id: str,
    *,
    upload_path: str,
    filename: str,
    entitlements: billing.Entitlements,
) -> tuple[str | None, str | None]:
    """Move the uploaded object to its durable home.

    Returns `(storage_path, note)`. A note means the file was not kept and
    why — shown on the memory, because a vault that silently declines to keep
    something is worse than one that says it is full.

    Copy-then-delete rather than a rename: object stores have no rename, and
    doing it in this order means a failure leaves the bytes in `captures/`,
    where the next sweep can retry, rather than nowhere at all.
    """
    bucket = storage.bucket()
    source = bucket.blob(upload_path)

    try:
        source.reload()
    except Exception as error:
        print(f"[knowra] file_vault missing_upload path={upload_path} {error}")
        return None, None

    size = int(source.size or 0)
    if not fits(uid, entitlements, size):
        _delete(bucket, upload_path)
        return None, (
            "Indexed, but the file was not kept — your plan's "
            f"{human_size(entitlements.file_bytes or 0)} of file storage is full."
        )

    target = object_path(uid, memory_id, filename)
    try:
        bucket.copy_blob(source, bucket, target)
    except Exception as error:
        print(f"[knowra] file_vault copy_failed to={target} {error}")
        return None, None

    _delete(bucket, upload_path)
    record(uid, size)
    return target, None


def forget(uid: str, storage_path: str | None) -> int:
    """Delete a kept file and give back its bytes. Returns the bytes freed."""
    if not storage_path:
        return 0
    bucket = storage.bucket()
    blob = bucket.blob(storage_path)
    try:
        blob.reload()
        size = int(blob.size or 0)
    except Exception:
        return 0
    if _delete(bucket, storage_path):
        release(uid, size)
        return size
    return 0


def _delete(bucket, path: str) -> bool:
    try:
        bucket.blob(path).delete()
        return True
    except Exception as error:
        print(f"[knowra] file_vault delete_failed path={path} {error}")
        return False


@on_document_deleted(
    document="memories/{memoryId}",
    region="us-central1",
    memory=options.MemoryOption.MB_256,
)
def on_memory_deleted(event: Event) -> None:
    """Delete the kept file when its memory goes.

    A trigger rather than a line in `deleteMemory`, because there is more
    than one way a memory dies — the app's delete, a connector disconnect
    with `deleteMemories`, an account purge — and the path that forgets is
    the one that leaves a user paying for bytes they can no longer see.

    Also releases the quota. Without that, deleting everything and starting
    again would leave the account permanently full.
    """
    snapshot = event.data
    if snapshot is None:
        return
    data = snapshot.to_dict() or {}
    uid = data.get("userId")
    path = data.get("storagePath")
    if not uid:
        return

    # Mirrors the increment in `ingestion.on_memory_created`, and sits above
    # the `path` check on purpose: a capture whose file was declined for
    # quota has no `storagePath` by now but was still counted on the way in,
    # and decrementing only the ones that kept a file would ratchet the row
    # upwards over a few full-vault days.
    device_vault.forget_capture(uid, data)

    # The chunks go with the memory. They are what made it findable: left
    # behind, a deleted file keeps turning up as a source on every phone
    # (no `removed` change ever reaches the index listener) and keeps
    # answering through the server's passage lookup.
    chunks = chunk_store.delete_for_memory(firestore.client(), uid=uid, memory_id=snapshot.id)

    freed = forget(uid, path) if path else 0
    print(f"[knowra] memory_deleted uid={uid} memory={snapshot.id} chunks={chunks} freed={freed}")
