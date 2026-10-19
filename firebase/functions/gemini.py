"""The one place that talks to a model.

Gemini, on the free tier, for both jobs the product needs: turning text into
vectors, and turning retrieved context into a cited answer. Kept behind this
module so the retrieval and RAG layers never hold an API shape — swapping
providers later is this file plus the dimension constant.

Two asymmetries in here are easy to miss and expensive to get wrong.

**Documents and queries are embedded differently.** `RETRIEVAL_DOCUMENT` and
`RETRIEVAL_QUERY` are distinct task types, and using one for both measurably
degrades recall: a question and the passage that answers it are not the same
kind of text, and the model is told which it is looking at.

**A truncated embedding must be re-normalised.** `gemini-embedding-001`
natively emits 3072 dimensions and supports Matryoshka truncation to shorter
lengths — but only the full-length vector is unit-normalised. Truncating
without re-normalising leaves vectors of varying magnitude, which quietly
corrupts cosine distance: Firestore ranks by the metric we ask for, and it
cannot tell us the inputs were malformed.
"""

from __future__ import annotations

import asyncio
import math
import os
import threading

import httpx

API = "https://generativelanguage.googleapis.com/v1beta"

#: Must match the `dimension` in firestore.indexes.json. Changing it means
#: re-embedding every chunk *and* redeploying the indexes — Firestore rejects
#: a KNN query whose vector length disagrees with the index.
DIMENSIONS = 1536

EMBED_MODEL = os.environ.get("GEMINI_EMBED_MODEL", "gemini-embedding-001")
#: Pinned ids, not `gemini-flash-latest`: a floating alias can change the model
#: under a citation contract without a deploy. Overridable by env so a swap
#: needs no code change — and if an id is refused for this project, the
#: ladder below steps down to one that is not.
#:
#: **Which ids this key can call — measured, not read off a quota page.**
#: On 2026-09-27 `scripts/probe_models.py` got 404 "no longer available (to
#: new users)" for every 2.0 and 2.5 id, and 200 for `gemini-3.5-flash-lite`,
#: `gemini-3.6-flash` and the `-latest` aliases. The quota page still shows
#: generous rows for the 2.x family; they are limits on models this project
#: cannot use. So a Lite answers and a Flash reads files (once per file,
#: invisible afterwards, so it gets the fuller model).
#:
#: **3.1 Flash-Lite answers, chosen on price and checked on the real prompt
#: (2026-09-27).** $0.25 in / $1.50 out per million against 3.5 Flash-Lite's
#: $0.30 / $2.50 — about a quarter cheaper per answer — and on the app's own
#: `rag.answer` it gave the same cited answers, the same refusal on a
#: question the passages could not answer, and 1.3–1.6 s against 1.2–1.5 s.
#: Forty calls in six seconds drew no 429. Re-run `scripts/probe_models.py`
#: and `scripts/probe_burst.py` before changing either — and the ladder
#: below survives a wrong id anyway.
CHAT_MODEL = os.environ.get("GEMINI_CHAT_MODEL", "gemini-3.1-flash-lite")
EXTRACT_MODEL = os.environ.get("GEMINI_EXTRACT_MODEL", "gemini-3.6-flash")

#: Free-tier requests are slow under load and a hung call holds a function
#: instance; ingestion has its own 540s budget to spend, answering does not.
EMBED_TIMEOUT = httpx.Timeout(60.0, connect=10.0)
CHAT_TIMEOUT = httpx.Timeout(90.0, connect=10.0)

#: Transcription is the slowest call in the system — an hour of audio or a
#: hundred-page PDF is minutes, not seconds. Sits inside ingestion's 540s.
EXTRACT_TIMEOUT = httpx.Timeout(300.0, connect=10.0)

#: `batchEmbedContents` caps at 100 requests, and a large batch is also a
#: large retry: a single 429 loses the whole call.
BATCH = 50

#: Waits between attempts at a rate-limited or unavailable call. Extraction
#: can afford patience — it has ingestion's 540 s and nobody is watching a
#: spinner — so a burst of captures is spread out rather than failed on the
#: first 429. An answer cannot wait, so it gets one short retry.
EXTRACT_RETRIES = (2.0, 5.0, 12.0, 25.0)
ANSWER_RETRIES = (1.5,)

#: Where extraction turns when [EXTRACT_MODEL] is still out of quota after
#: its schedule. A file read a little less well beats a file not read at all,
#: and `readWith` on the memory says which model it was.
EXTRACT_FALLBACK_MODEL = os.environ.get("GEMINI_EXTRACT_FALLBACK_MODEL", "gemini-3.5-flash-lite")

#: The rungs every ladder ends on: models this project is known to have.
#: A 2-series id was once "no longer available to new users" on this key —
#: and on 2026-09-27 both 2.0 ids were refused again, live — so a wrong head
#: must never mean no model at all. Reading prefers the fuller model, an
#: answer the faster one; `scripts/probe_models.py` says which ids the key
#: will actually take.
_READ_SAFETY_NET = ("gemini-3.6-flash", "gemini-3.5-flash-lite")
_ANSWER_SAFETY_NET = ("gemini-3.5-flash-lite", "gemini-3.6-flash")


def _ladder(*heads: str, net: tuple[str, ...]) -> tuple[str, ...]:
    """[heads] then [net], each model once, order kept."""
    out: list[str] = []
    for model in (*heads, *net):
        if model and model not in out:
            out.append(model)
    return tuple(out)


EXTRACT_LADDER = _ladder(EXTRACT_MODEL, EXTRACT_FALLBACK_MODEL, net=_READ_SAFETY_NET)

#: Reading for the free tier (`billing.reads_economy`): 3.1 Flash-Lite at
#: $0.25 in / $1.50 out against 3.6 Flash's $0.75 / $3.75. Falls back up the
#: price list rather than failing — a file read by a dearer model beats a
#: file not read.
EXTRACT_ECONOMY_MODEL = os.environ.get("GEMINI_EXTRACT_ECONOMY_MODEL", "gemini-3.1-flash-lite")
EXTRACT_ECONOMY_LADDER = _ladder(EXTRACT_ECONOMY_MODEL, net=_ANSWER_SAFETY_NET)
CHAT_LADDER = _ladder(CHAT_MODEL, net=_ANSWER_SAFETY_NET)

#: Models this project cannot use, learned from a 404 and kept for the life
#: of the instance — the refusal is paid once, not on every request. Quota
#: (429) is deliberately not remembered: it is a bad minute, not a dead id.
_refused: set[str] = set()


class ModelError(RuntimeError):
    """A model call failed. [retryable] separates a bad minute from a bad request."""

    def __init__(self, message: str, *, retryable: bool = False):
        super().__init__(message)
        self.retryable = retryable


def _key() -> str:
    key = os.environ.get("GEMINI_API_KEY", "")
    if not key:
        # Loud, not silent: an unembedded chunk is invisible to search, so a
        # missing key would look like retrieval that simply never finds
        # anything rather than a pipeline that never ran.
        raise ModelError("GEMINI_API_KEY is not set.")
    return key


class _Pool:
    """Holds the one client, created on first use."""

    lock = threading.Lock()
    client: httpx.Client | None = None


def _client() -> httpx.Client:
    """One HTTP client for the instance's lifetime, so connections are reused.

    Every call used to open its own `AsyncClient`, which meant a new TCP and
    TLS handshake to Google per embedding and per answer — paid on the hot
    path of every search. A pooled client keeps the connection open between
    requests, so the second search on an instance skips the handshake.

    A *sync* client driven from a worker thread rather than an `AsyncClient`:
    each request runs its own `asyncio.run`, and an async pool is bound to
    the event loop it first used, so it could not be shared across requests.
    The sync client's pool is thread-safe and loop-agnostic.
    """
    if _Pool.client is None:
        with _Pool.lock:
            if _Pool.client is None:
                _Pool.client = httpx.Client(
                    limits=httpx.Limits(
                        max_connections=16,
                        max_keepalive_connections=8,
                        keepalive_expiry=60.0,
                    ),
                )
    return _Pool.client


def _retryable(response: httpx.Response) -> bool:
    return response.status_code == 429 or response.status_code >= 500


def _retry_after(response: httpx.Response, default: float) -> float:
    """The server's own wait when it names one, capped at a minute."""
    raw = response.headers.get("retry-after")
    if not raw:
        return default
    try:
        return min(max(float(raw), 0.0), 60.0)
    except ValueError:
        return default


async def _generate(
    ladder: tuple[str, ...],
    *,
    body: dict,
    timeout: httpx.Timeout,
    retries: tuple[float, ...],
    what: str,
) -> tuple[dict, str]:
    """`generateContent` down [ladder]. Returns the response body and the model.

    The first rung gets the full [retries] schedule; later rungs get one
    retry, because by then the schedule has already been spent once. A 404
    marks the model refused for this instance and moves on; a 429 or 5xx
    after the schedule moves on without marking. Anything else raises as it
    always did.
    """
    exhausted: httpx.Response | None = None
    for rung, model in enumerate(ladder):
        if model in _refused:
            continue
        response = await _post(
            f"{API}/models/{model}:generateContent",
            timeout=timeout,
            json=body,
            retries=retries if rung == 0 else retries[:1],
        )
        if response.status_code == 404:
            _refused.add(model)
            print(f"[knowra] model_refused model={model} what={what!r}")
            continue
        if _retryable(response):
            exhausted = response
            print(f"[knowra] model_exhausted model={model} status={response.status_code}")
            continue
        _raise_for(response, what)
        return response.json(), model
    if exhausted is not None:
        _raise_for(exhausted, what)
    raise ModelError(f"{what} failed: no model on the ladder is available to this project.")


async def _post(
    url: str,
    *,
    json: dict,
    timeout: httpx.Timeout,
    retries: tuple[float, ...] = (),
) -> httpx.Response:
    """One request, retried on the [retries] schedule while it is 429 or 5xx.

    Returns the last response either way; the caller's `_raise_for` turns a
    final failure into the [ModelError] it always did.
    """
    attempt = 0
    while True:
        response = await asyncio.to_thread(
            _client().post, url, params={"key": _key()}, json=json, timeout=timeout
        )
        if not _retryable(response) or attempt >= len(retries):
            return response
        wait = _retry_after(response, retries[attempt])
        print(
            f"[knowra] gemini_retry status={response.status_code} "
            f"wait={wait:g}s attempt={attempt + 1}/{len(retries)}"
        )
        await asyncio.sleep(wait)
        attempt += 1


def _raise_for(response: httpx.Response, what: str) -> None:
    if response.is_success:
        return
    status = response.status_code
    if status == 429 or status >= 500:
        raise ModelError(f"{what} is rate limited or unavailable.", retryable=True)
    if status in (401, 403):
        raise ModelError(f"{what} was refused — check GEMINI_API_KEY.")
    # The body carries Gemini's own reason, which is usually the actionable
    # part (a blocked prompt, a bad dimension).
    raise ModelError(f"{what} failed ({status}): {response.text[:300]}")


def _unit(values: list[float]) -> list[float]:
    """Re-normalise a truncated embedding to unit length.

    See the module docstring: only the full 3072-dimension vector arrives
    normalised. A zero vector is returned untouched rather than dividing by
    zero — it cannot match anything, which is the correct outcome for text
    that carried no signal.
    """
    norm = math.sqrt(sum(v * v for v in values))
    if norm == 0:
        return values
    return [v / norm for v in values]


async def embed_documents(texts: list[str]) -> list[list[float]]:
    """Embed chunk text for storage."""
    return await _embed(texts, task="RETRIEVAL_DOCUMENT")


async def embed_query(text: str) -> list[float]:
    """Embed a question for search."""
    vectors = await _embed([text], task="RETRIEVAL_QUERY")
    return vectors[0]


async def _embed(texts: list[str], *, task: str) -> list[list[float]]:
    if not texts:
        return []

    out: list[list[float]] = []

    for start in range(0, len(texts), BATCH):
        window = texts[start : start + BATCH]
        response = await _post(
            f"{API}/models/{EMBED_MODEL}:batchEmbedContents",
            json={
                "requests": [
                    {
                        "model": f"models/{EMBED_MODEL}",
                        "content": {"parts": [{"text": text}]},
                        "taskType": task,
                        "outputDimensionality": DIMENSIONS,
                    }
                    for text in window
                ]
            },
            timeout=EMBED_TIMEOUT,
            retries=ANSWER_RETRIES,
        )
        _raise_for(response, "Embedding")

        embeddings = response.json().get("embeddings", [])
        if len(embeddings) != len(window):
            # A short response would silently misalign every chunk with
            # somebody else's vector, which is worse than failing.
            raise ModelError(
                f"Embedding returned {len(embeddings)} vectors for {len(window)} inputs."
            )
        for item in embeddings:
            values = item.get("values") or []
            if len(values) != DIMENSIONS:
                raise ModelError(
                    f"Embedding returned {len(values)} dimensions, expected {DIMENSIONS}."
                )
            out.append(_unit(values))

    return out


#: Inline attachments are capped by the request size, not by a documented
#: file limit. 15 MB of base64 is ~20 MB on the wire, which is the practical
#: ceiling; anything larger needs the resumable Files API, and until that
#: exists a big file is recorded as un-indexed rather than failed.
MAX_INLINE_BYTES = 15 * 1024 * 1024

#: What extraction asks for of a document. Verbatim, not a summary — this
#: text is what gets chunked, embedded and later quoted back as a citation,
#: so a paraphrase here would make every citation subtly untrue.
_EXTRACT_SYSTEM = """You transcribe documents for a search index.

Return the readable content of the attached file as plain text, verbatim.

- Preserve wording, figures, names and dates exactly.
- Keep the reading order. Use blank lines between paragraphs or sections.
- For a table, keep it as lines of text with the columns separated by " | ".
- For speech, transcribe what is said. Label speakers as "Speaker 1:" only if
  more than one is clearly present.
- Do NOT summarise, comment, introduce or conclude. No preamble.
- If there is no readable content at all, return exactly: NO_CONTENT"""

#: Pictures are the exception to "verbatim". A photo of a garden has no words
#: to transcribe, and an index holding only the words *in* a picture cannot
#: find the picture — "garden image" matched nothing while photos were OCR'd
#: and nothing more. So a picture is described, plainly and in the terms
#: someone would search by, and any text in it is then transcribed verbatim
#: under its own heading, so a citation can never pass the description off as
#: something the picture said.
_DESCRIBE_SYSTEM = """You describe pictures for a search index.

Return plain text in exactly this shape:

What the picture shows: <one sentence — the subject, the setting, what is happening>
<two to four short lines with the details someone might search by: the kind of
place or object, notable things in it, colours and materials, and any dates,
brands, signs or labels that are visible>
Text in the picture:
<every readable word, verbatim and in reading order — or the single word: none>

- Describe only what is visible. Do not guess who a person is, and do not name
  anyone unless the name is written in the picture.
- Preserve wording, figures, names and dates in the text exactly.
- No preamble and no commentary outside this shape.
- If the picture is unreadable — blank, black or corrupted — return exactly: NO_CONTENT"""


def extraction_brief(mime_type: str, filename: str = "") -> tuple[str, str]:
    """The system prompt and the request for one file, by what the file is.

    A picture is described, with its words transcribed under a heading;
    everything else is transcribed verbatim. Pure, so the routing is testable
    without a model.
    """
    picture = mime_type.startswith("image/")
    system = _DESCRIBE_SYSTEM if picture else _EXTRACT_SYSTEM
    ask = "Describe this picture." if picture else "Transcribe this file."
    prompt = f"File name: {filename}\n\n{ask}" if filename else ask
    return system, prompt


async def extract_file(
    data: bytes, mime_type: str, *, filename: str = "", economy: bool = False
) -> tuple[str, str]:
    """Read a PDF, image or audio file as text — a picture as a description of
    it plus the words in it. Returns the text and the model that read it.

    One multimodal call in place of an OCR engine, a PDF parser and a speech
    model. That is a real simplification — three dependencies, three failure
    modes and three sets of tuning become one — and the trade is that the
    fidelity is the model's rather than a specialist's, and that it costs a
    request per file instead of local CPU.

    Patient by design. This is the one call with a long budget and no one
    waiting on it, so a rate-limited model is retried on [EXTRACT_RETRIES]
    and then the next rung of [EXTRACT_LADDER] is tried rather than failing:
    a handful of captures in a row was once enough to lose one.

    Raises [ModelError] with `retryable` set where the caller can usefully
    try again.
    """
    if len(data) > MAX_INLINE_BYTES:
        raise ModelError(
            f"That file is {len(data) // (1024 * 1024)} MB; "
            f"{MAX_INLINE_BYTES // (1024 * 1024)} MB is the current limit."
        )

    import base64

    system, prompt = extraction_brief(mime_type, filename)
    body = {
        "systemInstruction": {"parts": [{"text": system}]},
        "contents": [
            {
                "role": "user",
                "parts": [
                    {
                        "inlineData": {
                            "mimeType": mime_type,
                            "data": base64.b64encode(data).decode(),
                        }
                    },
                    {"text": prompt},
                ],
            }
        ],
        "generationConfig": {
            # Zero here, unlike answering: this is transcription, and any
            # sampling at all invents words that were never in the file —
            # which would then be embedded and cited.
            "temperature": 0,
            "maxOutputTokens": 8192,
        },
    }

    answer, model = await _generate(
        EXTRACT_ECONOMY_LADDER if economy else EXTRACT_LADDER,
        body=body,
        timeout=EXTRACT_TIMEOUT,
        retries=EXTRACT_RETRIES,
        what="Reading the file",
    )

    text = _text_of(answer, what="Reading the file")
    return ("" if text.strip() == "NO_CONTENT" else text), model


async def generate(system: str, prompt: str, *, max_tokens: int = 1200) -> str:
    """One-shot JSON generation. Returns the model's text, or raises."""
    answer, _ = await _generate(
        CHAT_LADDER,
        body={
            "systemInstruction": {"parts": [{"text": system}]},
            "contents": [{"role": "user", "parts": [{"text": prompt}]}],
            "generationConfig": {
                # Low, not zero: this is extraction from supplied context,
                # not composition, and creativity here shows up as claims
                # the sources do not support.
                "temperature": 0.2,
                "maxOutputTokens": max_tokens,
                "responseMimeType": "application/json",
            },
        },
        timeout=CHAT_TIMEOUT,
        retries=ANSWER_RETRIES,
        what="Answering",
    )
    return _text_of(answer, what="Answering")


def _text_of(body: dict, *, what: str) -> str:
    candidates = body.get("candidates") or []
    if not candidates:
        # A blocked prompt returns no candidate but does carry a reason.
        reason = (body.get("promptFeedback") or {}).get("blockReason")
        raise ModelError(f"{what} returned nothing{f' ({reason})' if reason else ''}.")

    # Parts can carry a `thoughtSignature` alongside — or instead of — text,
    # so this concatenates the text it finds rather than indexing parts[0].
    parts = (candidates[0].get("content") or {}).get("parts") or []
    text = "".join(part.get("text", "") for part in parts).strip()
    if not text:
        finish = candidates[0].get("finishReason")
        # MAX_TOKENS on a long file is worth retrying with a smaller slice
        # rather than recording as a permanent failure.
        raise ModelError(
            f"{what} returned no text (finish: {finish}).",
            retryable=finish == "MAX_TOKENS",
        )
    return text
