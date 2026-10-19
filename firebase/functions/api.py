"""The callable surface the app talks to.

Most reads go straight to Firestore under security rules — that is the point of
having no server. Functions exist only where the client cannot be trusted or
cannot do the work:

* **Anything that spends money or quota.** A client-side counter is a
  suggestion.
* **Anything that writes server-owned state.** Entitlements, embeddings,
  processing status.
* **Anything needing a key.** Embedding and LLM calls.
"""

from __future__ import annotations

import asyncio
import time
from datetime import UTC, datetime, timedelta, timezone, tzinfo

from firebase_admin import firestore
from firebase_functions import https_fn, options

import billing
import gemini
import index_budget
import local_index
import meta_cache
import query_understanding
import rag
import retention
import retrieval
import usage
from connectors import source_url

#: Both retrieval paths embed the question and one of them generates prose.
RETRIEVAL_SECRETS = ["GEMINI_API_KEY"]

#: Instances kept warm for the call a person waits on.
#:
#: Measured from the logs: a call on a warm instance takes 450–650 ms; the
#: first one after a few minutes idle takes 3–10 s, because the instance had
#: scaled to zero and every session began with a cold start. One warm
#: instance for `ask` removes that where it is still felt: every typed
#: question is answered there. `search` runs cold on purpose — once a phone
#: holds its index the app searches locally, so a warm `search` would mostly
#: sit idle. **It costs money while idle**: Firebase quotes $7.11 a month per
#: warm 512 MB instance at deploy time. Set to 0 to go back to scale-to-zero.
WARM_INSTANCES = 1

#: The memory documents search and ask decorate their rows with, remembered
#: briefly — see `meta_cache`.
_META = meta_cache.MetaCache()


def _model_error(error: gemini.ModelError) -> https_fn.HttpsError:
    """Surface a model failure as something the app can act on.

    `retryable` is the distinction that matters to the user: a rate limit is
    "try again in a moment", a missing key is "this build is misconfigured",
    and the app shows a retry button for one and not the other.
    """
    return https_fn.HttpsError(
        https_fn.FunctionsErrorCode.UNAVAILABLE
        if error.retryable
        else https_fn.FunctionsErrorCode.FAILED_PRECONDITION,
        str(error),
    )


def _email_of(req: https_fn.CallableRequest) -> str | None:
    """The caller's email, from the verified ID token.

    Free: it is already in the token, so matching a test account by address
    costs no extra Firestore read on the hot path.
    """
    return (req.auth.token or {}).get("email") if req.auth else None


def _zone(raw: object) -> tzinfo:
    """The phone's UTC offset as a zone, so "yesterday" is the user's yesterday.

    Absent, unreadable or impossible (beyond ±14 h) means UTC — the old
    behaviour, never an error.
    """
    try:
        minutes = int(raw)  # type: ignore[arg-type]
    except (TypeError, ValueError):
        return UTC
    if abs(minutes) > 14 * 60:
        return UTC
    return timezone(timedelta(minutes=minutes))


def _now(req: https_fn.CallableRequest) -> datetime:
    return datetime.now(_zone(req.data.get("tzOffsetMinutes")))


def _require_uid(req: https_fn.CallableRequest) -> str:
    if req.auth is None or not req.auth.uid:
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.UNAUTHENTICATED, "Sign in first.")
    return req.auth.uid


def _entitlements(uid: str, *, email: str | None = None) -> billing.Entitlements:
    db = firestore.client()
    doc = db.collection("users").document(uid).collection("subscription").document("current").get()
    return billing.resolve_for_user(uid, doc.to_dict() if doc.exists else None, email=email)


@https_fn.on_call(region="us-central1", memory=options.MemoryOption.MB_256)
def get_subscription(req: https_fn.CallableRequest) -> dict:
    """What the paywall and the settings screen show."""
    uid = _require_uid(req)
    entitlements = _entitlements(uid, email=_email_of(req))
    allowance = usage.peek(uid, entitlements, zone=_zone((req.data or {}).get("tzOffsetMinutes")))

    db = firestore.client()
    dormant = (
        db.collection("memories")
        .where("userId", "==", uid)
        .where("recallState", "==", "dormant")
        .count()
        .get()
    )

    return {
        "tier": entitlements.tier,
        "limits": {
            "memoryDays": entitlements.memory_window_days,
            "backupDays": entitlements.backup_window_days,
            "indexBytes": entitlements.index_bytes,
            "connectedAccounts": entitlements.connected_accounts,
            "windowQueries": entitlements.window_queries,
            "windowHours": billing.ANSWER_WINDOW_HOURS,
            "weeklyQueries": entitlements.weekly_queries,
        },
        # Both allowances, with when the next answer comes back and when the
        # week resets — see `usage.Standing.report`.
        "answers": allowance,
        # The derived layer is the only thing this product hosts (§43), so
        # this is the number that actually bounds a user's footprint — and
        # until now it was a label on the pricing page with nothing behind it.
        "index": index_budget.allowance(uid, entitlements),
        # Lets the app say "1,204 memories are waiting" rather than showing a
        # generic upgrade prompt.
        "memoriesDormant": dormant[0][0].value if dormant else 0,
    }


@https_fn.on_call(
    region="us-central1",
    memory=options.MemoryOption.MB_512,
    timeout_sec=60,
    # Cold on purpose — see WARM_INSTANCES.
    min_instances=0,
    secrets=RETRIEVAL_SECRETS,
)
def search(req: https_fn.CallableRequest) -> dict:
    """Semantic search over the caller's own memories.

    Spends nothing. Only `ask` is metered, and only for a question that
    found something (`usage.counts_as_ask`). This docstring used to say
    search spent a query up front; the code had long since stopped, and the
    stale line was what made the counting look wrong from the outside.

    Returns passages, not answers. Screen 2C lists matches while the user is
    still speaking, and it must not wait on generation to do that.
    """
    uid = _require_uid(req)
    query = req.data.get("query")

    if not isinstance(query, str) or not query.strip():
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.INVALID_ARGUMENT, "Ask something.")

    query = query.strip()

    # Search does NOT spend a question. `ask` does.
    #
    # The daily allowance exists to bound generation, which is the expensive
    # half — a model call producing prose. Retrieval alone is one embedding
    # and about sixty document reads, and it is the product's core verb:
    # *finding* what you saved. Metering it would mean a free user exhausted
    # their day looking for a file without ever asking a question about it,
    # which is the opposite of what the limit is for.
    #
    # The generative path stays metered, and the fair-use ceilings still
    # bound it — so the expensive thing is still capped and the cheap thing
    # is usable.
    # No plan lookup. This used to read the subscription and today's usage
    # first — two Firestore round trips, 100–300 ms on every search — to
    # return an `allowance` the app never read. Search is unmetered
    # (`usage.counts_as_ask` charges answers, not searches), so there is
    # nothing here to check and nothing to report.
    started = time.perf_counter()
    db = firestore.client()
    marks: dict[str, float] = {}

    async def _run():
        # Understanding is local and synchronous in effect, so this is one
        # network call deep: embed the question, then the KNN read.
        #
        # It used to be two, and the comment here used to claim they ran
        # "concurrently — the wall clock is the slower of the two rather
        # than their sum". They did not: the code awaited the model call and
        # *then* passed its result into retrieval, which needs it. The
        # comment described the design; the code was strictly serial, and
        # searches were taking 19-20s end to end. See
        # query_understanding's docstring for the measurements that killed
        # the model call outright.
        at = time.perf_counter()
        parsed = await query_understanding.understand(query, now=_now(req))
        marks["understand"] = time.perf_counter() - at

        at = time.perf_counter()
        found = await retrieval.search(db, uid, query, parsed=parsed, marks=marks)
        marks["retrieve"] = time.perf_counter() - at
        return parsed, found

    try:
        parsed, passages = asyncio.run(_run())
    except gemini.ModelError as error:
        raise _model_error(error) from error

    at = time.perf_counter()
    meta = _memories(db, {p.memory_id for p in passages})
    marks["titles"] = time.perf_counter() - at
    marks["total"] = time.perf_counter() - started

    # Logged on every search, as one line.
    #
    # Without this the only latency signal was Cloud Run's total request
    # time, which says a search took 20 seconds and nothing about where they
    # went — and the answer turned out to be a leg that was not supposed to
    # be on the critical path at all. A stage breakdown is the difference
    # between noticing that and guessing at it.
    print(
        "[knowra] search "
        + " ".join(f"{name}={value * 1000:.0f}ms" for name, value in marks.items())
        + f" hits={len(passages)} filters={parsed.has_filters}"
    )

    return {
        "query": query,
        # What the question was read as. Surfaced so the UI can say "videos,
        # July" — a user who sees the filter can correct it, where one who
        # gets no results cannot tell whether the filter or the vault was
        # the problem.
        "signals": parsed.signals,
        "matches": [
            {
                "memoryId": p.memory_id,
                "chunkId": p.chunk_id,
                "title": meta.get(p.memory_id, {}).get("title", "Untitled"),
                "type": meta.get(p.memory_id, {}).get("type", "file"),
                "excerpt": _excerpt(p.text),
                "score": p.relevance,
                "locator": f"part {p.chunk_index + 1}",
                # Was missing, so every match on screen 2C was unopenable:
                # `Match.isOpenable` reads this field, the row's tap handler
                # reads that, and the whole chain was dead because the one
                # place that resolves a memory's original URL — `_memories`,
                # which has returned it all along for citations — was not
                # asked for it here.
                "url": meta.get(p.memory_id, {}).get("url"),
                "storagePath": meta.get(p.memory_id, {}).get("storagePath"),
            }
            for p in passages
        ],
    }


@https_fn.on_call(
    region="us-central1",
    memory=options.MemoryOption.MB_512,
    timeout_sec=120,
    min_instances=WARM_INSTANCES,
    secrets=RETRIEVAL_SECRETS,
)
def ask(req: https_fn.CallableRequest) -> dict:
    """RAG over the caller's memories.

    Every answer comes back with citations — an uncited answer is a bug, not a
    degraded result, because traceability is what separates this from a
    general chatbot. The contract is enforced in `rag.answer`, after the model
    has spoken, rather than requested in the prompt.
    """
    uid = _require_uid(req)
    question = req.data.get("question") or req.data.get("query")
    conversation_id = req.data.get("conversationId")

    if not isinstance(question, str) or not question.strip():
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.INVALID_ARGUMENT, "Ask something.")

    question = question.strip()
    # The device did the retrieval. Its index lives on the phone
    # (`local_index`), so it sends the ids of the passages it ranked highest
    # and the server reads them — by id, checking they are the caller's and
    # still recallable — and answers from those. Without `passages` this is
    # an older app, or a device whose index is still being built, and the
    # server searches for itself while the cloud still holds vectors.
    chosen = req.data.get("passages")
    try:
        requested = local_index.requested_passages(chosen) if chosen is not None else None
    except local_index.BadRequest as error:
        raise https_fn.HttpsError(
            https_fn.FunctionsErrorCode.INVALID_ARGUMENT, str(error)
        ) from error

    entitlements = _entitlements(uid, email=_email_of(req))
    zone = _zone(req.data.get("tzOffsetMinutes"))
    # Reserved before any model runs, in a transaction, so two questions sent
    # together cannot both take the last answer. Handed back below if the
    # answer cites nothing (`usage.counts_as_ask`) or anything fails.
    reservation = usage.reserve(uid, entitlements, zone=zone)
    allowance = reservation.report
    db = firestore.client()
    started = datetime.now(UTC)

    async def _run():
        parsed = query_understanding.understand_locally(question, now=_now(req))
        if requested is not None:
            passages = local_index.passages_from_docs(requested, _chunks(db, requested), uid)
            return parsed, passages, await rag.answer(question, passages)

        # A follow-up is retrieved with its context folded in, but ANSWERED as
        # asked. "What about Team?" has no subject of its own — the nouns are
        # in the previous turn — so the embedding text gets them and the model
        # does not. That ordering matters: a model handed a rewritten question
        # can answer one the user never asked.
        retrieval_text = query_understanding.contextualise(parsed.search, history)
        passages = await retrieval.search(db, uid, retrieval_text, parsed=parsed)
        return parsed, passages, await rag.answer(question, passages)

    try:
        conversation = _conversation(db, uid, conversation_id)
        history = _history(db, conversation) if conversation else []
        parsed, passages, answer = asyncio.run(_run())
    except gemini.ModelError as error:
        usage.release(uid, entitlements, reservation, zone=zone)
        raise _model_error(error) from error
    except BaseException:
        usage.release(uid, entitlements, reservation, zone=zone)
        raise

    if not usage.counts_as_ask(answered=answer.answered, cited=len(answer.citations)):
        allowance = usage.release(uid, entitlements, reservation, zone=zone) or allowance

    meta = _memories(db, {p.memory_id for p in answer.citations})
    latency_ms = int((datetime.now(UTC) - started).total_seconds() * 1000)

    if conversation:
        _record(db, conversation, question, answer, latency_ms)

    return {
        "id": f"{uid}-{int(started.timestamp() * 1000)}",
        "question": question,
        "answered": answer.answered,
        "confidence": answer.confidence,
        "blocks": [{"text": b.text, "citations": list(b.citations)} for b in answer.blocks],
        "citations": [
            {
                "index": i,
                "memoryId": p.memory_id,
                "title": meta.get(p.memory_id, {}).get("title", "Untitled"),
                "type": meta.get(p.memory_id, {}).get("type", "file"),
                "url": meta.get(p.memory_id, {}).get("url"),
                "storagePath": meta.get(p.memory_id, {}).get("storagePath"),
                "locator": f"part {p.chunk_index + 1}",
                "score": p.relevance,
            }
            for i, p in enumerate(answer.citations, start=1)
        ],
        "answeredAt": started.isoformat(),
        "latencyMs": latency_ms,
        "allowance": allowance,
        "conversationId": conversation,
        "signals": parsed.signals,
        # How many candidates retrieval actually had to work with. Not shown,
        # but the difference between "no answer because nothing is indexed"
        # and "no answer despite good matches" is the first thing anyone will
        # want to know when this disappoints someone.
        "retrieved": len(passages),
    }


def _conversation(db, uid: str, raw: object) -> str | None:
    """Resolve, or create, the thread this question belongs to.

    §49 keeps conversation context separate from personal memory: a chat turn
    is not knowledge, and must not become a searchable memory. So messages
    live in their own collection, are never embedded, and never appear in
    retrieval.

    A caller-supplied id is verified to be the caller's own — missing and
    someone else's return the same None, so this cannot be used to discover
    which conversations exist.
    """
    if raw:
        ref = db.collection("conversations").document(str(raw))
        snapshot = ref.get()
        data = snapshot.to_dict() if snapshot.exists else None
        if data and data.get("userId") == uid:
            return ref.id
        return None

    ref = db.collection("conversations").document()
    now = datetime.now(UTC)
    ref.set({"userId": uid, "createdAt": now, "updatedAt": now})
    return ref.id


def _history(db, conversation_id: str, *, turns: int = 6) -> list[dict]:
    """The recent turns, oldest first.

    Bounded hard. An unbounded history would grow the retrieval text until
    the original question was a rounding error in it, and every follow-up
    would drift further from what was asked.
    """
    docs = (
        db.collection("conversations")
        .document(conversation_id)
        .collection("messages")
        .order_by("createdAt", direction=firestore.Query.DESCENDING)
        .limit(turns)
        .stream()
    )
    rows = [
        {"role": (d.to_dict() or {}).get("role"), "text": (d.to_dict() or {}).get("text")}
        for d in docs
    ]
    rows.reverse()
    return rows


def _record(db, conversation_id: str, question: str, answer, latency_ms: int) -> None:
    """Append the turn.

    Server-written only — `firestore.rules` denies the client, because a
    client that could write a message could fabricate a cited answer.
    """
    messages = db.collection("conversations").document(conversation_id).collection("messages")
    now = datetime.now(UTC)

    batch = db.batch()
    batch.set(messages.document(), {"role": "user", "text": question, "createdAt": now})
    batch.set(
        messages.document(),
        {
            "role": "assistant",
            "text": "\n\n".join(b.text for b in answer.blocks),
            "answered": answer.answered,
            "confidence": answer.confidence,
            "citations": [
                {"memoryId": p.memory_id, "chunkId": p.chunk_id} for p in answer.citations
            ],
            "latencyMs": latency_ms,
            # A microsecond later, so ordering by createdAt cannot put the
            # answer before its own question.
            "createdAt": now.replace(microsecond=min(now.microsecond + 1, 999999)),
        },
    )
    batch.update(
        db.collection("conversations").document(conversation_id),
        {"updatedAt": now, "lastQuestion": question},
    )
    batch.commit()


def _source_url(data: dict) -> str | None:
    """A connector-indexed memory's link, for the ones that never stored it.

    Memories written by the sync carry `sourceUrl` now, so this is the
    fallback for everything indexed before that — the link follows from the
    file id, so it is derived here rather than backfilled into every
    document.
    """
    return source_url(str(data.get("provider") or ""), data.get("sourceRef"))


def _chunks(db, requested: list[tuple[str, float]]) -> dict[str, dict | None]:
    """The chunk documents behind the device's chosen ids, in one `get_all`."""
    refs = [db.collection("chunks").document(chunk_id) for chunk_id, _ in requested]
    if not refs:
        return {}
    return {doc.id: (doc.to_dict() if doc.exists else None) for doc in db.get_all(refs)}


@https_fn.on_call(
    region="us-central1",
    memory=options.MemoryOption.MB_256,
    timeout_sec=60,
    secrets=RETRIEVAL_SECRETS,
)
def embed_texts(req: https_fn.CallableRequest) -> dict:
    """Turn texts into vectors for a device's own index — and keep nothing.

    The one model call the device cannot make itself yet. The vectors go
    straight back down and are never written anywhere here: the point of
    the on-device index is that the searchable form of a person's files
    exists only on their phone. `task` is `document` for chunk text and
    `query` for a question; the two are embedded differently and mixing
    them measurably hurts recall (see `gemini`).
    """
    _require_uid(req)
    try:
        texts = local_index.bounded_texts(req.data.get("texts"))
    except local_index.BadRequest as error:
        raise https_fn.HttpsError(
            https_fn.FunctionsErrorCode.INVALID_ARGUMENT, str(error)
        ) from error
    task = req.data.get("task")
    if task not in ("document", "query"):
        raise https_fn.HttpsError(
            https_fn.FunctionsErrorCode.INVALID_ARGUMENT, "task must be document or query."
        )

    async def _run():
        if task == "query":
            return [await gemini.embed_query(t) for t in texts]
        return await gemini.embed_documents(texts)

    try:
        vectors = asyncio.run(_run())
    except gemini.ModelError as error:
        raise _model_error(error) from error

    return {"vectors": vectors, "dimensions": gemini.DIMENSIONS, "model": gemini.EMBED_MODEL}


@https_fn.on_call(region="us-central1", memory=options.MemoryOption.MB_256, timeout_sec=120)
def purge_cloud_embeddings(req: https_fn.CallableRequest) -> dict:
    """Remove the caller's vectors from the cloud, a page at a time.

    Called by a device once its own index holds a vector for every chunk —
    not before, so nothing is deleted that has not been rebuilt somewhere.
    Walks the caller's chunk documents in id order and deletes the
    `embedding` field; `after` is the cursor the device passes back until
    `done`. A chunk with no such field costs a no-op write, which is the
    price of not being able to query for the field's presence.
    """
    uid = _require_uid(req)
    after = req.data.get("after")
    if after is not None and not isinstance(after, str):
        raise https_fn.HttpsError(
            https_fn.FunctionsErrorCode.INVALID_ARGUMENT, "`after` must be an id."
        )

    db = firestore.client()
    query = (
        db.collection("chunks")
        .where("userId", "==", uid)
        .order_by("__name__")
        .select([])
        .limit(local_index.PURGE_BATCH)
    )
    if after:
        query = query.start_after({"__name__": db.collection("chunks").document(after)})

    ids = [doc.id for doc in query.stream()]
    if ids:
        batch = db.batch()
        for chunk_id in ids:
            batch.update(
                db.collection("chunks").document(chunk_id), {"embedding": firestore.DELETE_FIELD}
            )
        batch.commit()

    return {
        "processed": len(ids),
        "after": ids[-1] if ids else after,
        "done": len(ids) < local_index.PURGE_BATCH,
    }


def _memories(db, memory_ids: set[str]) -> dict[str, dict]:
    """Resolve the memory metadata citation rows display.

    One `get_all` rather than a read per citation: eight sequential document
    reads is eight round trips inside a request the design promises will feel
    instant.

    `type` is returned as well as the title — screen 3B draws a per-type mark
    beside each source, and without it every source is a generic document.
    """
    ids = [m for m in memory_ids if m]
    if not ids:
        return {}
    # The same few memories come back search after search, and `search` and
    # `ask` run together over the same question — so most of these are
    # answered from the last two minutes without a read.
    out, missing = _META.get_many(ids)
    if not missing:
        return out
    refs = [db.collection("memories").document(m) for m in missing]
    for doc in db.get_all(refs):
        if not doc.exists:
            continue
        data = doc.to_dict() or {}
        out[doc.id] = {
            "title": str(data.get("title") or _fallback_title(data)),
            "type": str(data.get("type") or "file"),
            # The original, where there is one. §28's promise is that an
            # answer is *traceable*, which means the citation has to be able
            # to take you to the thing it cites — a title and a page number
            # you cannot open is a reference, not a citation.
            "url": data.get("url") or data.get("sourceUrl") or _source_url(data),
            # Where the kept file lives, so the app can fetch it on a device
            # that never had it. A path, not a signed URL: the client reads it
            # through the Storage SDK under `storage.rules`, so nothing here
            # grants access the rules do not.
            "storagePath": data.get("storagePath"),
        }
        # Only once indexing has finished: `storagePath` is written in the
        # same update that marks a memory ready, and a row cached a moment
        # earlier would say the file is not kept for the whole TTL.
        _META.put(doc.id, out[doc.id], settled=data.get("status") == "ready")
    return out


def _fallback_title(data: dict) -> str:
    """Mirrors the client's own fallback, so a citation and its library row
    read the same. A link saved with no note has its url as the only label."""
    url = str(data.get("url") or "")
    if url:
        cleaned = url.split("://", 1)[-1].split("?", 1)[0].rstrip("/")
        return cleaned.removeprefix("www.") or "Untitled"
    return "Untitled"


def _excerpt(text: str, *, limit: int = 220) -> str:
    """A readable fragment for a match row, cut on a word boundary."""
    clean = " ".join(text.split())
    if len(clean) <= limit:
        return clean
    cut = clean[:limit].rsplit(" ", 1)[0]
    return f"{cut}…"


@https_fn.on_call(region="us-central1", memory=options.MemoryOption.MB_256)
def apply_retention(req: https_fn.CallableRequest) -> dict:
    """Re-derive every memory's expiry for the caller — `retention.apply`.

    Memories outside the window are **demoted, not deleted**: keeping the row
    and its chunks is what makes an upgrade restore something rather than
    promise it. A plan change already does this by itself
    (`retention.on_plan_changed`); this is the manual door.
    """
    uid = _require_uid(req)
    counts = retention.apply(
        firestore.client(), uid, _entitlements(uid, email=_email_of(req)), datetime.now(UTC)
    )
    return {"demoted": counts["demote"], "promoted": counts["promote"], "healed": counts["heal"]}
