"""How much index a user is entitled to, and what happens at the ceiling.

The derived layer is the only thing this product hosts — architecture §43.
Originals stay in the user's own storage, so the bill is embeddings and chunk
text, and `Entitlements.index_bytes` is the number that bounds it. It existed
in the plan table from the start and was enforced nowhere, which made it a
label on a pricing page rather than a limit.

The cost model is deliberately simple and slightly pessimistic:

    per chunk  =  len(text)  +  DIMENSIONS × 8

1536 doubles at 8 bytes is 12.3 KB of vector per chunk, which dwarfs the text
for anything but a very long passage. Counting it this way means the number a
user sees moves with the thing that actually costs money.

Two ceilings, and they answer different questions:

* **Per memory** — one capture must not consume the whole allowance. A link to
  a 900-page manual is a legitimate thing to save, and indexing all of it
  would leave no room for the next four hundred notes.
* **Per account** — the plan's total. When it is reached, indexing degrades to
  *partial*: whatever fits is indexed and the memory says so. Refusing the
  whole capture would be worse, because the first page of a document is
  usually the part that answers questions about it.
"""

from __future__ import annotations

from firebase_admin import firestore

from billing import Entitlements
from gemini import DIMENSIONS

#: Bytes per stored vector. Firestore keeps each component as a double.
VECTOR_BYTES = DIMENSIONS * 8

#: The most one memory may claim, as a fraction of the plan's total.
#:
#: A twentieth: on the free tier that is ~100 MB, about 8,000 chunks, which is
#: a very long book. Generous for anything a person actually captures, and
#: still leaves nineteen twentieths for everything else.
PER_MEMORY_SHARE = 0.05


def chunk_cost(text: str) -> int:
    return len(text.encode("utf-8")) + VECTOR_BYTES


def cost_of(texts: list[str]) -> int:
    return sum(chunk_cost(t) for t in texts)


def used(uid: str) -> int:
    """Index bytes already spent. Server-owned; the client cannot write it."""
    doc = firestore.client().collection("users").document(uid).get()
    data = doc.to_dict() if doc.exists else None
    return int((data or {}).get("indexedBytes") or 0)


def allowance(uid: str, entitlements: Entitlements) -> dict:
    """What the paywall and the storage dashboard show."""
    limit = entitlements.index_bytes
    spent = used(uid)
    return {
        "limit": limit,
        "used": spent,
        "remaining": None if limit is None else max(0, limit - spent),
    }


def fit(uid: str, entitlements: Entitlements, texts: list[str]) -> tuple[list[str], str | None]:
    """Trim a chunk list to what the user can afford.

    Returns the chunks to index and, when anything was dropped, a sentence for
    the memory's `indexNote`. Truncation has to be *visible*: an answer that
    silently cannot see the second half of a document is indistinguishable
    from a document that never said it, and the user would have no way to tell
    which.
    """
    limit = entitlements.index_bytes
    if limit is None or not texts:
        return texts, None

    per_memory = int(limit * PER_MEMORY_SHARE)
    remaining = max(0, limit - used(uid))
    budget = min(per_memory, remaining)

    if budget <= 0:
        return [], ("Your plan's index is full. Free up space or upgrade, then re-index this.")

    kept: list[str] = []
    spent = 0
    for text in texts:
        cost = chunk_cost(text)
        if spent + cost > budget:
            break
        kept.append(text)
        spent += cost

    if len(kept) == len(texts):
        return texts, None

    if not kept:
        # Even the first chunk does not fit, which means the budget is
        # essentially gone rather than the chunk being enormous.
        return [], ("Your plan's index is full. Free up space or upgrade, then re-index this.")

    reason = "the index limit on your plan" if remaining < per_memory else "the per-item limit"
    return kept, (
        f"Indexed the first {len(kept)} of {len(texts)} parts — "
        f"{reason} stopped the rest. The whole file is still in the library."
    )


def record(uid: str, texts: list[str]) -> None:
    """Add what was just indexed to the running total.

    A transactional increment rather than read-add-write: two captures
    finishing together would otherwise both read the old total and both write
    their own, losing one of them — which is how a limit quietly stops being
    one.
    """
    amount = cost_of(texts)
    if amount <= 0:
        return

    db = firestore.client()
    ref = db.collection("users").document(uid)

    @firestore.transactional
    def _add(transaction) -> None:  # type: ignore[no-untyped-def]
        snapshot = ref.get(transaction=transaction)
        current = int((snapshot.to_dict() or {}).get("indexedBytes") or 0)
        transaction.set(ref, {"indexedBytes": current + amount}, merge=True)

    _add(db.transaction())


def release(uid: str, amount: int) -> None:
    """Give bytes back when chunks are deleted.

    Called on re-index, which replaces a memory's chunks, and on retention
    demotion, which drops them. Without this the total only ever rises and a
    user who deletes everything stays at their ceiling forever.
    """
    if amount <= 0:
        return

    db = firestore.client()
    ref = db.collection("users").document(uid)

    @firestore.transactional
    def _sub(transaction) -> None:  # type: ignore[no-untyped-def]
        snapshot = ref.get(transaction=transaction)
        current = int((snapshot.to_dict() or {}).get("indexedBytes") or 0)
        # Floored at zero: an accounting drift must not leave a negative
        # balance that hands out free allowance.
        transaction.set(ref, {"indexedBytes": max(0, current - amount)}, merge=True)

    _sub(db.transaction())
