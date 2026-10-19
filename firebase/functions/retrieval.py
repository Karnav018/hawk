"""Finding the passages that answer a question — architecture §25, §26.

The spec asks for hybrid retrieval: vector, keyword and metadata together,
then a reranking stage. Firestore gives us exactly one of those — KNN — and no
reranker. This module is the answer to that gap, and the shape of it is the
main design decision in the retrieval path:

    over-fetch by vector  ──►  rescore lexically  ──►  fuse the two rankings

Rather than run a second search engine, the vector stage fetches far more
candidates than the answer needs, and the keyword stage re-ranks *within* that
candidate set. This recovers most of what hybrid search is for — exact names,
figures, quoted phrases, the things an embedding smooths away — without a
Typesense or Vertex AI Search deployment to run, pay for and keep in sync.

What it cannot recover is a document the vector stage never returned at all.
That is the honest limit: if the only mention of "Pricing schedule v4" sits in
a passage that is semantically unlike the question, over-fetching will not
find it. The fix is a real lexical index, and the fusion step below is exactly
where it plugs in — `_lexical` becomes a second retriever instead of a
rescorer, and `_fuse` is unchanged.

Fusion is Reciprocal Rank Fusion, not a weighted score sum. RRF combines
*ranks*, so it needs no calibration between a cosine distance and a term
overlap count — two quantities on unrelated scales, where any fixed weighting
is a guess that quietly favours one retriever.
"""

from __future__ import annotations

import math
import re
import time
from dataclasses import dataclass

from google.cloud.firestore_v1.base_vector_query import DistanceMeasure
from google.cloud.firestore_v1.vector import Vector

import gemini
from query_understanding import Query

#: How many chunks the vector stage pulls before rescoring. Generous on
#: purpose — this is the only stage that can bring a passage into play at all,
#: so its recall bounds everything downstream.
CANDIDATES = 60

#: How many survive into the model's context. Bounded by attention, not by
#: cost: past roughly this many passages an answer starts citing the weakest
#: ones to look thorough.
CONTEXT = 8

#: RRF's damping constant. 60 is the value from the original paper and is not
#: worth tuning before there is a relevance set to tune against.
RRF_K = 60

#: Words carrying no retrieval signal. Short and deliberate — an aggressive
#: stop list removes the words that make a phrase query specific.
_STOP = frozenset(
    "a an and are as at be by did do does for from had has have how i if in is it "
    "its me my of on or our so than that the their them then there these they this "
    "to was we were what when where which who why will with you your".split()
)

_WORD = re.compile(r"[a-z0-9][a-z0-9'./-]*")


@dataclass(frozen=True, slots=True)
class Passage:
    chunk_id: str
    memory_id: str
    text: str
    #: Position within its source document, for the citation locator.
    chunk_index: int
    #: Cosine distance from the query. 0 is identical, 2 is opposite.
    distance: float
    vector_rank: int
    lexical_rank: int
    score: float

    @property
    def relevance(self) -> int:
        """0-100, for the number screen 3B prints beside a source.

        Derived from cosine distance rather than the fused score: the fused
        score is a rank artefact with no meaning outside this result set, and
        showing it would imply a precision it does not have.
        """
        similarity = 1.0 - (self.distance / 2.0)
        return max(0, min(100, round(similarity * 100)))


def _captured(data: dict):
    """A chunk's capture date, for the date window.

    Denormalised onto the chunk at ingestion, because filtering would
    otherwise mean a memory lookup per candidate — sixty round trips inside a
    request that is meant to feel instant.
    """
    return data.get("capturedAt") or data.get("createdAt")


def _terms(text: str) -> list[str]:
    return [w for w in _WORD.findall(text.lower()) if w not in _STOP and len(w) > 1]


def _lexical(query: str, passages: list[dict]) -> dict[str, float]:
    """Score candidates by term overlap, weighted by term rarity.

    BM25's idea without BM25's bookkeeping: a term appearing in few candidates
    says more about which one is relevant than a term appearing in all of
    them. Computed over the candidate set rather than the whole corpus, which
    is an approximation — but the candidate set is what we are ranking, and it
    needs no corpus-wide statistics to maintain.
    """
    query_terms = set(_terms(query))
    if not query_terms:
        return {}

    docs = {p["id"]: _terms(p["text"]) for p in passages}
    n = len(docs) or 1

    # Document frequency across candidates, for the rarity weight.
    df: dict[str, int] = {}
    for terms in docs.values():
        for term in set(terms):
            if term in query_terms:
                df[term] = df.get(term, 0) + 1

    scores: dict[str, float] = {}
    for doc_id, terms in docs.items():
        if not terms:
            continue
        counts: dict[str, int] = {}
        for term in terms:
            if term in query_terms:
                counts[term] = counts.get(term, 0) + 1

        score = 0.0
        for term, count in counts.items():
            idf = math.log(1 + n / (1 + df.get(term, 0)))
            # Saturating term frequency: the fifth occurrence of a word says
            # much less than the second, and without this a long chunk that
            # merely repeats a query word outranks a short one that answers.
            tf = count / (count + 1.5)
            score += idf * tf
        # Length normalisation, so a long chunk does not win on volume alone.
        scores[doc_id] = score / math.sqrt(len(terms))

    return scores


def _fuse(vector_order: list[str], lexical_order: list[str], *, k: int = RRF_K) -> dict[str, float]:
    """Reciprocal Rank Fusion over two rankings.

    Each retriever contributes 1/(k + rank). A passage both rank highly wins;
    one that only the keyword stage likes still places, which is the whole
    point — that is the passage the embedding smoothed away.
    """
    scores: dict[str, float] = {}
    for order in (vector_order, lexical_order):
        for rank, doc_id in enumerate(order, start=1):
            scores[doc_id] = scores.get(doc_id, 0.0) + 1.0 / (k + rank)
    return scores


def _nearest(scoped, vector: list[float]) -> list:
    """The nearest candidates, as whole documents.

    Not projected. Firestore returns no `_distance` when `select()` is
    combined with `find_nearest` (seen live as `retrieval_projection_off
    reason=no_distance`), and relevance and confidence both read it. So each
    candidate arrives with its 12 KB vector — a cost that ends with the cloud
    vectors themselves, once every device has purged them.
    """
    return list(
        scoped.find_nearest(
            vector_field="embedding",
            query_vector=Vector(vector),
            limit=CANDIDATES,
            distance_measure=DistanceMeasure.COSINE,
            distance_result_field="_distance",
        ).get()
    )


async def search(
    db,
    uid: str,
    query: str,
    *,
    limit: int = CONTEXT,
    parsed: Query | None = None,
    marks: dict[str, float] | None = None,
) -> list[Passage]:
    """Hybrid retrieval over one user's active chunks.

    [parsed] carries §24's extracted signals. Its type filter narrows the KNN
    query itself; its date window is applied to the candidates afterwards,
    because Firestore does not support a range filter alongside vector search.

    [marks], when given, receives the stage timings — `embed`, `knn`, `rank`
    — so the caller's one log line can say where a slow search went.
    """
    timings = marks if marks is not None else {}
    text = parsed.search if parsed else query

    at = time.perf_counter()
    vector = await gemini.embed_query(text)
    timings["embed"] = time.perf_counter() - at

    # `recallState` is filtered in the query, not afterwards: an expired
    # memory must not be able to answer a question (§36), and post-filtering
    # would let dormant chunks consume candidate slots. Both the filter field
    # and the vector are in the composite index for exactly this reason.
    scoped = db.collection("chunks").where("userId", "==", uid).where("recallState", "==", "active")

    # A type filter is an equality, which `find_nearest` supports as a
    # pre-filter — so it shrinks the search rather than the results. Only
    # applied for a single type: Firestore's `in` is not permitted alongside
    # vector search, and "audio or voice note" is better served by fetching
    # both and letting the date/lexical stages sort it out than by refusing.
    types = parsed.memory_types if parsed else ()
    if len(types) == 1:
        scoped = scoped.where("memoryType", "==", types[0])

    at = time.perf_counter()
    docs = _nearest(scoped, vector)
    timings["knn"] = time.perf_counter() - at

    at = time.perf_counter()
    candidates: list[dict] = []
    dropped = 0
    for doc in docs:
        data = doc.to_dict() or {}
        body = data.get("text") or ""
        if not body:
            continue

        # Post-filters. Both are applied here rather than in the query: the
        # date window because Firestore cannot range-filter a vector search,
        # and a multi-value type because it cannot `in`-filter one either.
        if parsed is not None:
            if types and len(types) > 1 and data.get("memoryType") not in types:
                dropped += 1
                continue
            if not parsed.within_dates(_captured(data)):
                dropped += 1
                continue

        candidates.append(
            {
                "id": doc.id,
                "memory_id": data.get("memoryId") or "",
                "text": body,
                "chunk_index": int(data.get("chunkIndex") or 0),
                "distance": float(data.get("_distance") or 0.0),
            }
        )

    if dropped:
        # Worth logging: a filter that removed most of the candidate set is
        # the likeliest reason a question with an obvious answer returns
        # nothing, and it is invisible from the response alone.
        print(
            f"[knowra] retrieval_filtered dropped={dropped} "
            f"kept={len(candidates)} signals={parsed.signals if parsed else {}}"
        )

    if not candidates:
        timings["rank"] = time.perf_counter() - at
        return []

    vector_order = [c["id"] for c in candidates]
    lexical_scores = _lexical(query, candidates)
    lexical_order = [
        doc_id
        for doc_id, _ in sorted(lexical_scores.items(), key=lambda kv: kv[1], reverse=True)
        if lexical_scores[doc_id] > 0
    ]

    fused = _fuse(vector_order, lexical_order)
    by_id = {c["id"]: c for c in candidates}
    vector_rank = {doc_id: i for i, doc_id in enumerate(vector_order, start=1)}
    lexical_rank = {doc_id: i for i, doc_id in enumerate(lexical_order, start=1)}

    ranked = sorted(fused.items(), key=lambda kv: kv[1], reverse=True)[:limit]
    timings["rank"] = time.perf_counter() - at

    return [
        Passage(
            chunk_id=doc_id,
            memory_id=by_id[doc_id]["memory_id"],
            text=by_id[doc_id]["text"],
            chunk_index=by_id[doc_id]["chunk_index"],
            distance=by_id[doc_id]["distance"],
            vector_rank=vector_rank.get(doc_id, 0),
            # 0 means the keyword stage did not rank it at all.
            lexical_rank=lexical_rank.get(doc_id, 0),
            score=score,
        )
        for doc_id, score in ranked
    ]
