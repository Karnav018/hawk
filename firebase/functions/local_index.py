"""The server's half of an index that lives on the phone.

Vectors are not stored in the cloud. Each signed-in device embeds the chunk
text it syncs (through [bounded_texts] → `gemini.embed_documents`), keeps the
vectors in its own store, and does the nearest-neighbour search itself. What
comes back up is the *choice*: the ids of the passages the device ranked
highest, which `ask` reads by id and answers from.

That split keeps the server authoritative about what a passage says and whose
it is — a device sends ids and distances, never text — while the searchable
representation of a person's files never leaves their phone.
"""

from __future__ import annotations

from retrieval import CONTEXT, Passage

#: One call embeds at most this many texts; `gemini.BATCH` is 50 and the
#: device sends what it has in batches of that size.
MAX_TEXTS = 50

#: A chunk is ~1,000 characters (`chunking.TARGET`). Four times that is room
#: for any real chunk and a hard stop for a client sending a novel.
#: Beyond this a text is cut, not refused. Refusing failed the *whole batch*
#: for one over-long chunk, and a batch that always fails is a device index
#: that never builds. The vector is of the head; the keyword stage on the
#: phone still reads every character.
MAX_TEXT_CHARS = 8_000

#: How many chosen passages `ask` will read — the same context budget the
#: server-side ranker used, so an answer is never built from more.
MAX_PASSAGES = CONTEXT + 4

#: Chunk documents touched per `purge_cloud_embeddings` call. Under
#: Firestore's 500-writes-per-batch, with room for the read that finds them.
PURGE_BATCH = 400


class BadRequest(ValueError):
    """The client sent something the endpoint will not act on."""


def bounded_texts(raw: object) -> list[str]:
    """The texts a device wants embedded, or [BadRequest] with the reason."""
    if not isinstance(raw, list) or not raw:
        raise BadRequest("Send a list of texts.")
    if len(raw) > MAX_TEXTS:
        raise BadRequest(f"At most {MAX_TEXTS} texts per call.")
    out: list[str] = []
    for item in raw:
        if not isinstance(item, str) or not item.strip():
            raise BadRequest("Every text must be a non-empty string.")
        out.append(item[:MAX_TEXT_CHARS])
    return out


def requested_passages(raw: object) -> list[tuple[str, float]]:
    """`[(chunk_id, distance), …]` from the request, in the device's order.

    Distances are the device's own cosine distances. They are trusted only
    for what they influence — the confidence label on the user's own answer
    — and clamped to the range a cosine distance can take.
    """
    if not isinstance(raw, list):
        raise BadRequest("`passages` must be a list.")
    if len(raw) > MAX_PASSAGES:
        raise BadRequest(f"At most {MAX_PASSAGES} passages per question.")
    out: list[tuple[str, float]] = []
    seen: set[str] = set()
    for item in raw:
        if not isinstance(item, dict):
            raise BadRequest("Each passage is an object with a chunkId.")
        chunk_id = item.get("chunkId")
        if not isinstance(chunk_id, str) or not chunk_id:
            raise BadRequest("Each passage needs a chunkId.")
        if chunk_id in seen:
            continue
        seen.add(chunk_id)
        distance = item.get("distance", 0.5)
        try:
            distance = float(distance)
        except (TypeError, ValueError) as error:
            raise BadRequest("A distance must be a number.") from error
        out.append((chunk_id, min(2.0, max(0.0, distance))))
    return out


def passages_from_docs(
    requested: list[tuple[str, float]], docs: dict[str, dict | None], uid: str
) -> list[Passage]:
    """Turn the device's chosen ids into [Passage]s, in the device's order.

    Silently drops anything that is not the caller's, no longer exists, or
    has gone dormant — a device with a stale index must not be able to have
    a dormant passage answer (§36), and a wrong id is not worth an error when
    the other seven are fine. Ranks follow the device's order: it did the
    ranking, and the server has nothing better to replace it with.
    """
    out: list[Passage] = []
    for rank, (chunk_id, distance) in enumerate(requested, start=1):
        data = docs.get(chunk_id)
        if not data:
            continue
        if data.get("userId") != uid:
            continue
        if data.get("recallState", "active") != "active":
            continue
        text = str(data.get("text") or "")
        if not text:
            continue
        out.append(
            Passage(
                chunk_id=chunk_id,
                memory_id=str(data.get("memoryId") or ""),
                text=text,
                chunk_index=int(data.get("chunkIndex") or 0),
                distance=distance,
                vector_rank=rank,
                lexical_rank=rank,
                score=1.0 / rank,
            )
        )
    return out
