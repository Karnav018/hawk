"""Getting text out of a memory — architecture §21.

Every memory type reduces to text before it can be chunked and embedded. What
that reduction costs varies enormously: a note is already text, a PDF is a
parse, a photo is a description plus OCR, an hour of audio is a transcription that costs real
money and minutes.

Everything is implemented now, by three routes:

* **Text already in the document** — a note, a title. Free, instant.
* **A file in Storage** — a PDF, a photo, a recording. One multimodal model
  call replaces an OCR engine, a PDF parser and a speech model.
* **A page on the web** — a saved link, fetched and stripped to its prose by
  `link_archive`. A link indexed by its url alone is a bookmark, and the
  product's claim is that you can ask for it in your own words.

A type with no route left returns [Extracted.unsupported], which the pipeline
records on the memory as a *reason* rather than a failure. A user seeing "that
file type is not indexed yet" is informed; one seeing a memory stuck at
`failed` with no explanation is not.
"""

from __future__ import annotations

import re
from dataclasses import dataclass


@dataclass(frozen=True, slots=True)
class Extracted:
    text: str
    #: Set when this type cannot be extracted yet. The memory is still
    #: visible in the library; it just cannot answer anything.
    unsupported: str | None = None
    #: Set when the capture itself should fail, in words the app can show —
    #: a link to a page that refuses readers. Not retryable.
    failure: str | None = None
    #: Which model read the file, when one did. The fallback model here marks
    #: a file worth reading again with the flagship when quota allows.
    read_with: str | None = None

    @property
    def ok(self) -> bool:
        return self.unsupported is None and self.failure is None and bool(self.text.strip())


#: Types whose content is already text in the document.
_TEXTUAL = {"note", "text", "link"}

#: Mime prefixes the model can read directly.
_READABLE = ("application/pdf", "image/", "audio/", "text/")

#: Video is excluded on cost, not capability. A minute of video is an order of
#: magnitude more tokens than a minute of audio for the same speech, and the
#: right answer is to strip the audio track first — which needs ffmpeg, which
#: is a separate piece of work.
_PENDING = {
    "video": "Video is not indexed yet — the audio track needs extracting first.",
}

_TAG = re.compile(r"<[^>]+>")


def storage_path(memory: dict) -> str | None:
    """Where the file lives, if this memory has one."""
    path = memory.get("storagePath") or memory.get("storage_path")
    return str(path) if path else None


def plan(memory: dict) -> Extracted | None:
    """Decide without doing any work.

    Returns an [Extracted] when the answer needs no file — text already in the
    document, or a type with no route — and None when the caller must fetch
    the file and call [extract_file].
    """
    kind = str(memory.get("type") or "file")

    if kind in _TEXTUAL:
        return Extracted(text=_textual(memory))

    if kind in _PENDING:
        return Extracted(text="", unsupported=_PENDING[kind])

    path = storage_path(memory)
    if not path:
        # A media type with nothing behind it. The most likely cause is a
        # connector-indexed memory whose original is still in the provider —
        # those are read through the connector, not from our Storage.
        return Extracted(
            text="",
            unsupported="Nothing uploaded for this capture yet.",
        )

    mime = str(memory.get("mimeType") or "")
    if not mime.startswith(_READABLE):
        return Extracted(
            text="",
            unsupported=f"{mime or 'That file type'} is not indexed yet.",
        )

    return None


def extract(memory: dict) -> Extracted:
    """Text-only extraction, for callers with no file access.

    Kept so the pure path stays synchronous and testable; anything needing a
    download goes through [plan] plus [extract_file].
    """
    planned = plan(memory)
    return (
        planned
        if planned is not None
        else Extracted(text="", unsupported="This capture needs its file read.")
    )


async def extract_link(memory: dict) -> Extracted:
    """Read the page a saved link points at, and index what it says.

    The fallback is the old behaviour — title, note and url — and it is the
    result for every link that cannot be read: a paywall, a login wall, a
    dead domain, a private address. A link the user chose to keep is a
    memory whether or not we could open it, so a failed fetch must not turn
    into an `unsupported` that drops it out of the index entirely.

    The page's own title is indexed alongside the body for the same reason
    `_textual` indexes the memory's: people search for what a page was
    called at least as often as for what it said.
    """
    import link_archive

    fallback = _textual(memory)
    url = str(memory.get("url") or "").strip()
    if not url:
        return Extracted(text=fallback)

    try:
        title, text = await link_archive.fetch(url)
    except link_archive.Blocked as error:
        # A login or a paywall: the url alone is not what the user meant to
        # keep, and the app offers the way that works — save it as a PDF.
        print(f"[knowra] link_archive blocked url={url} {error}")
        return Extracted(text=fallback, failure=str(error))
    except link_archive.Unreachable as error:
        print(f"[knowra] link_archive skipped url={url} {error}")
        return Extracted(text=fallback)
    except Exception as error:
        # A page can fail in ways httpx does not model — a bad certificate,
        # a connection reset mid-stream. Same verdict: keep the link.
        print(f"[knowra] link_archive failed url={url} {error}")
        return Extracted(text=fallback)

    parts = [p for p in (fallback, title, text) if p and p.strip()]
    return Extracted(text="\n\n".join(parts))


async def extract_file(memory: dict, data: bytes, *, economy: bool = False) -> Extracted:
    """Read an uploaded file as text, via the model — the cheaper one when
    [economy] (`billing.reads_economy`)."""
    import gemini

    mime = str(memory.get("mimeType") or "application/octet-stream")

    # Plain text needs no model at all. Sending a .txt to a vision model
    # would be a paid round trip to learn what `bytes.decode` already knows.
    if mime.startswith("text/"):
        try:
            return Extracted(text=data.decode("utf-8", errors="replace"))
        except Exception:
            return Extracted(text="", unsupported="That text file could not be read.")

    text, model = await gemini.extract_file(
        data, mime, filename=str(memory.get("title") or ""), economy=economy
    )
    if not text.strip():
        # The model read it and found nothing — a blank scan, silence, a
        # picture nothing can be made out in. Not a failure, and not worth retrying.
        return Extracted(text="", unsupported="Nothing readable in this file.")
    return Extracted(text=text, read_with=model)


def _textual(memory: dict) -> str:
    """Title, body and url, in the order a reader would meet them.

    The title is included in the indexed text rather than held separately: a
    note titled "Q3 pricing" whose body never repeats the phrase should still
    be found by asking about Q3 pricing, and a separate title vector would
    mean two embeddings and two chunks competing for the same answer.
    """
    parts: list[str] = []

    title = str(memory.get("title") or "").strip()
    if title:
        parts.append(title)

    body = str(memory.get("text") or "").strip()
    if body:
        # Notes can arrive from a share sheet carrying markup.
        parts.append(_TAG.sub(" ", body) if "<" in body else body)

    url = str(memory.get("url") or "").strip()
    if url:
        # The url is indexed too — people search for the domain they saved
        # something from far more often than you would expect.
        parts.append(url)

    return "\n\n".join(parts)
