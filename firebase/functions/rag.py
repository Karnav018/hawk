"""Turning retrieved passages into a cited answer — architecture §27, §28.

The product's claim is not "it answers questions", it is "every answer comes
back with the file and page it came from". So the citation contract is
enforced *here*, in code, after the model has spoken — not merely requested in
the prompt. A model asked politely to cite will mostly cite; mostly is not a
contract.

Three rules this module holds:

**A claim citing a source that does not exist is dropped.** Models invent
citation numbers, especially under pressure to look thorough. A block whose
every citation is invalid is removed rather than shown uncited.

**No passages means no answer.** With nothing retrieved the model is asked
nothing at all — a model handed an empty context will answer from its own
training and sound exactly as confident doing it, which is the single worst
failure this product can have.

**Confidence is derived, not reported.** The model's self-assessment is
advisory; what ships is capped by how good retrieval actually was. A model
cannot know that its best passage was a distant match.
"""

from __future__ import annotations

import json
from dataclasses import dataclass

import gemini
from retrieval import Passage

SYSTEM = """You answer questions strictly from the numbered SOURCES supplied.

Rules, in order of importance:
1. Use ONLY the sources. If they do not contain the answer, say so.
2. Every factual claim must cite the source it came from, by number.
3. Prefer quoting figures, names and dates exactly as the source gives them.
4. Be brief. Two or three short paragraphs at most.
5. Never mention "sources", "context" or "documents" in your prose — the
   reader sees the citations, so referring to them reads as hedging.

Return JSON only, in this exact shape:
{
  "blocks": [
    {"text": "A claim or two, as prose.", "citations": [1, 2]}
  ],
  "confidence": "high" | "medium" | "low",
  "answered": true | false
}

"answered" is false when the sources do not contain the answer. In that case
return one block explaining briefly what is missing, with an empty citations
array."""

#: Cosine distance beyond which a passage is a weak match. Used to cap
#: confidence, not to filter — a weak best match is still the best there is,
#: and the honest response is a hedged answer rather than none.
WEAK_DISTANCE = 0.62


@dataclass(frozen=True, slots=True)
class AnswerBlock:
    text: str
    citations: tuple[int, ...]


@dataclass(frozen=True, slots=True)
class Answer:
    blocks: tuple[AnswerBlock, ...]
    #: Only the sources actually cited, renumbered 1..n in citation order —
    #: a "SOURCES" list containing passages nothing referred to invites the
    #: reader to check something the answer never claimed.
    citations: tuple[Passage, ...]
    confidence: str
    answered: bool


def _prompt(question: str, passages: list[Passage]) -> str:
    blocks = [f"[{i}] {p.text}" for i, p in enumerate(passages, start=1)]
    return "SOURCES\n" + "\n\n".join(blocks) + f"\n\nQUESTION\n{question}"


def _confidence(reported: str, passages: list[Passage], cited: int) -> str:
    """Cap the model's self-report by what retrieval actually returned.

    The model sees the passages but not how far away they were, so it cannot
    tell a precise hit from the least-bad of sixty. This is where that gets
    accounted for.
    """
    level = reported if reported in {"high", "medium", "low"} else "low"
    best = min((p.distance for p in passages), default=2.0)

    if best > WEAK_DISTANCE:
        # Nothing retrieved was a close match. High is not available.
        return "low"
    if cited == 0:
        return "low"
    if cited == 1 and level == "high":
        # One source is not corroboration.
        return "medium"
    return level


async def answer(question: str, passages: list[Passage]) -> Answer:
    if not passages:
        return Answer(
            blocks=(
                AnswerBlock(
                    text=(
                        "Nothing in your vault matches that yet. Capture "
                        "something, or connect storage, and ask again."
                    ),
                    citations=(),
                ),
            ),
            citations=(),
            confidence="low",
            answered=False,
        )

    raw = await gemini.generate(SYSTEM, _prompt(question, passages))

    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError as error:
        # `responseMimeType: application/json` makes this rare, not
        # impossible — and a half-parsed answer must not become a shown one.
        raise gemini.ModelError("The answer came back malformed.") from error

    valid = range(1, len(passages) + 1)
    kept: list[AnswerBlock] = []
    used: list[int] = []

    for block in parsed.get("blocks") or []:
        text = str(block.get("text") or "").strip()
        if not text:
            continue

        raw_cites = [
            int(c)
            for c in (block.get("citations") or [])
            if isinstance(c, (int, float)) and int(c) in valid
        ]
        claimed = len(block.get("citations") or [])

        # A block that cited only sources which do not exist is dropped. It
        # is not an uncited claim to be shown with a caveat — it is a claim
        # whose stated evidence was invented.
        if claimed > 0 and not raw_cites:
            continue

        for c in raw_cites:
            if c not in used:
                used.append(c)
        kept.append(AnswerBlock(text=text, citations=tuple(raw_cites)))

    answered = bool(parsed.get("answered")) and bool(kept)

    if not kept:
        return Answer(
            blocks=(
                AnswerBlock(
                    text=(
                        "I found related material but could not answer that "
                        "from it. Try asking more specifically."
                    ),
                    citations=(),
                ),
            ),
            citations=(),
            confidence="low",
            answered=False,
        )

    # Renumber to 1..n over only the cited passages, so the superscripts the
    # reader sees match the SOURCES list beneath them.
    renumber = {old: new for new, old in enumerate(used, start=1)}
    blocks = tuple(
        AnswerBlock(
            text=b.text,
            citations=tuple(renumber[c] for c in b.citations),
        )
        for b in kept
    )

    return Answer(
        blocks=blocks,
        citations=tuple(passages[old - 1] for old in used),
        confidence=_confidence(str(parsed.get("confidence") or ""), passages, len(used)),
        answered=answered,
    )
