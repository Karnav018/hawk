"""Splitting text into the units that get embedded — architecture §18.

The chunk is the atom of retrieval, so its size is a product decision, not a
tuning knob:

* Too large and the embedding averages several topics into one vector that is
  close to nothing in particular, and the citation points at three pages.
* Too small and a passage loses the context that made it meaningful, and the
  answer cites a fragment that reads as out of context.

Sentence-aware, with overlap. Splitting mid-sentence puts the subject in one
chunk and its predicate in another, and neither retrieves; the overlap means a
fact sitting on a boundary appears whole in at least one chunk.
"""

from __future__ import annotations

import re
from dataclasses import dataclass

#: Characters, not tokens. Tokenising properly means shipping a tokeniser to
#: get a number used only to decide where to cut, and the ratio is stable
#: enough (~4 chars/token) that this lands around 250 tokens.
TARGET = 1000
OVERLAP = 150

#: Below this a chunk is not worth a vector — a heading, a page number, a
#: stray line. They still exist in the source; they just cannot be answers.
MIN_CHUNK = 60

#: A sentence end followed by whitespace. Deliberately conservative: it keeps
#: "Inc." and "v4.2" intact by requiring the next character to be uppercase
#: or a digit, which is what actually starts a new sentence.
_SENTENCE = re.compile(r"(?<=[.!?])\s+(?=[A-Z0-9\"'(\[])")

#: Blank-line-separated blocks. Split on these first, because a paragraph
#: boundary is a stronger topic boundary than any sentence end inside one.
_PARAGRAPH = re.compile(r"\n\s*\n+")


@dataclass(frozen=True, slots=True)
class Chunk:
    text: str
    #: Position in the source, 0-based. Becomes part of the citation locator,
    #: so it has to survive re-chunking of the same document identically.
    index: int
    #: Character offset into the cleaned source. Lets a future viewer scroll
    #: to the passage rather than just naming it.
    start: int


def normalise(raw: str) -> str:
    """Collapse the whitespace that PDF and HTML extraction leaves behind.

    Done before chunking, not after: offsets are recorded against the
    normalised text, so cleaning afterwards would invalidate every one.
    """
    text = raw.replace("\r\n", "\n").replace("\r", "\n")
    # Soft hyphens and zero-width joiners survive PDF extraction and split
    # words in the middle, which destroys both matching and readability.
    text = text.replace("­", "").replace("\u200b", "")
    # A single newline inside a paragraph is a line wrap, not a break.
    text = re.sub(r"(?<!\n)\n(?!\n)", " ", text)
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def split(raw: str, *, target: int = TARGET, overlap: int = OVERLAP) -> list[Chunk]:
    """Chunk `raw` into overlapping, sentence-aligned pieces."""
    text = normalise(raw)
    if not text:
        return []
    if len(text) <= target:
        return [Chunk(text=text, index=0, start=0)]

    # Paragraph boundaries first, then sentences within an over-long
    # paragraph. Keeping the offsets means walking the source rather than
    # using re.split, which throws away where each piece came from.
    units: list[tuple[int, str]] = []
    for para in _walk(text, _PARAGRAPH):
        offset, body = para
        if len(body) <= target:
            units.append(para)
            continue
        for sentence in _walk(body, _SENTENCE, base=offset):
            units.extend(_slice(sentence, overlap))

    chunks: list[Chunk] = []
    buffer: list[tuple[int, str]] = []
    length = 0

    def flush() -> None:
        nonlocal buffer, length
        if not buffer:
            return
        body = " ".join(part for _, part in buffer).strip()
        if len(body) >= MIN_CHUNK or not chunks:
            chunks.append(Chunk(text=body, index=len(chunks), start=buffer[0][0]))
        # Carry the tail forward so a fact on the boundary appears whole in
        # the next chunk too. Measured from the end, by whole units.
        carried: list[tuple[int, str]] = []
        carried_len = 0
        for part in reversed(buffer):
            if carried_len >= overlap:
                break
            carried.insert(0, part)
            carried_len += len(part[1]) + 1
        buffer = carried
        length = carried_len

    for unit in units:
        if length + len(unit[1]) > target and length > 0:
            flush()
        buffer.append(unit)
        length += len(unit[1]) + 1

    # The final flush must not re-emit only the carried overlap, which would
    # duplicate the tail of the previous chunk as a chunk of its own.
    if buffer:
        body = " ".join(part for _, part in buffer).strip()
        if not chunks or (len(body) >= MIN_CHUNK and body != chunks[-1].text):
            chunks.append(Chunk(text=body, index=len(chunks), start=buffer[0][0]))

    return chunks


def _slice(unit: tuple[int, str], size: int) -> list[tuple[int, str]]:
    """Cut one over-long unit at word boundaries into atoms of at most `size`.

    A single "sentence" longer than the target is rare in English and routine
    elsewhere: `_SENTENCE` wants a capital letter after a full stop, and Hindi
    has neither the letter nor the stop, so a whole paragraph arrives as one
    unit. Without this it became one chunk of any length — 4,193 characters
    in one vault — which the embedder then refused, batch and all.

    `size` is the overlap, not the target: the assembler below re-joins atoms
    up to the target itself and carries *at least one whole atom* forward as
    the overlap, so an atom near the target would double the next chunk.
    """
    offset, body = unit
    if len(body) <= size:
        return [unit]
    out: list[tuple[int, str]] = []
    cursor = 0
    while cursor < len(body):
        end = min(cursor + size, len(body))
        if end < len(body):
            space = body.rfind(" ", cursor, end)
            if space > cursor:
                end = space
        piece = body[cursor:end].strip()
        if piece:
            out.append((offset + cursor, piece))
        cursor = end
        while cursor < len(body) and body[cursor] == " ":
            cursor += 1
    return out


def _walk(text: str, pattern: re.Pattern[str], *, base: int = 0) -> list[tuple[int, str]]:
    """Split on `pattern`, keeping each piece's offset."""
    out: list[tuple[int, str]] = []
    cursor = 0
    for match in pattern.finditer(text):
        piece = text[cursor : match.start()]
        if piece.strip():
            out.append((base + cursor, piece.strip()))
        cursor = match.end()
    tail = text[cursor:]
    if tail.strip():
        out.append((base + cursor, tail.strip()))
    return out
