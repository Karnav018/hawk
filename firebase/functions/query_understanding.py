"""Reading the question before searching it — architecture §24.

"Find that video about vector databases I watched around July" carries three
separate signals, and an embedding of the whole sentence uses only one of
them. The words "video" and "July" get averaged into the vector alongside
"vector databases", where they compete with the semantic content instead of
narrowing it. Extracted as *filters* they do the opposite: they shrink the
candidate set to the right shape before similarity is measured at all.

Two things constrain how the signals can be used, and they are not the same:

* **Type is a pre-filter.** Firestore's `find_nearest` accepts equality
  filters, so `memoryType == "video"` narrows the KNN search itself — the
  cheap, correct place for it.
* **Dates are a post-filter.** Firestore does *not* support a range filter
  alongside vector search. So the date window is applied to the over-fetched
  candidates instead, which works precisely because retrieval already fetches
  far more than it returns.

**Extraction does not call a model.** It used to, and that was the single
worst decision in the retrieval path — measured, not guessed:

    gemini-3.6-flash, maxOutputTokens=300, this exact prompt
      run 1   2.60s   thoughts=289  output=7 tokens
      run 2   1.55s   HTTP 503 "model is currently experiencing high demand"
      run 3   4.19s   thoughts=289  output=None      <- truncated
    gemini-embedding-001 (the call that actually matters)
              0.53s

Three things are wrong in that table. The extraction cost more than the
embedding it was supposed to overlap with. One call in three failed outright,
so a third of searches fell back to no filters anyway. And of the 300-token
budget, 289 went to *thinking* about a filter extraction — twice leaving no
room for the answer, which means the model was being paid to return nothing.

So the filters are parsed here, in Python, from a closed vocabulary. It cannot
resolve "the thing I saw the day after the offsite", which the model could
have. It also cannot fail, cannot be rate-limited, costs nothing, and returns
in microseconds — and since the alternative was a third of searches getting no
filters *and* waiting 3 seconds for that, this is strictly better.

`understand_with_model` is kept below for the cases the vocabulary cannot
reach, behind `QUERY_MODEL_UNDERSTANDING=1`. It is off by default.
"""

from __future__ import annotations

import calendar
import json
import os
import re
from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta, tzinfo

import gemini

#: The memory types a question can plausibly name, mapped to the wire values
#: stored on each chunk. Deliberately a closed set: a model free to invent a
#: type would produce a filter that matches nothing, which looks identical to
#: "you have no such files".
TYPE_WORDS: dict[str, tuple[str, ...]] = {
    "video": ("video",),
    "audio": ("audio", "voiceNote"),
    "image": ("photo", "screenshot"),
    "document": ("pdf", "document"),
    "note": ("note", "text"),
    "link": ("link",),
}

SYSTEM = """You extract retrieval filters from a question about someone's own
saved files. You do not answer it.

Return JSON only:
{
  "search": "the part of the question that describes the CONTENT to find",
  "type": one of ["video","audio","image","document","note","link"] or null,
  "after": "YYYY-MM-DD" or null,
  "before": "YYYY-MM-DD" or null
}

Rules:
- "search" must keep the meaning. Strip only words that became a filter — a
  file type, a date phrase, and openers like "find" or "show me".
- Set "type" ONLY when the question names a kind of file. "the recording of
  the board call" is audio; "what did we agree on pricing" is null.
- Resolve relative dates against TODAY, given below. "around July" means that
  whole month. "last week" means the seven days before today.
- Everything null is the normal case. Do not invent a filter to seem useful."""


@dataclass(frozen=True, slots=True)
class Query:
    """A question, split into what to match and what to narrow by."""

    #: The text actually embedded. Falls back to the raw question.
    search: str
    memory_types: tuple[str, ...] = ()
    after: datetime | None = None
    before: datetime | None = None
    #: What the model reported, for logging when retrieval disappoints.
    signals: dict = field(default_factory=dict)

    @property
    def has_filters(self) -> bool:
        return bool(self.memory_types or self.after or self.before)

    def within_dates(self, captured: datetime | None) -> bool:
        """Whether a candidate falls inside the window.

        A candidate with no capture date **passes**. The alternative — hiding
        anything we cannot date — would silently drop every memory ingested
        before the field existed, and a filter that removes the answer is
        worse than one that removes nothing.
        """
        if captured is None:
            return True
        if self.after and captured < self.after:
            return False
        if self.before and captured > self.before:
            return False
        return True


#: Words a person actually uses for a kind of file, mapped to the same closed
#: set of wire values as [TYPE_WORDS].
#:
#: Ordered longest-first when matched, so "voice note" is not read as "note".
#: The plural is not listed separately — matching is done on a word stem
#: boundary that accepts a trailing "s".
TYPE_VOCABULARY: tuple[tuple[str, str], ...] = (
    ("voice note", "audio"),
    ("voice memo", "audio"),
    ("screenshot", "image"),
    ("recording", "audio"),
    ("document", "document"),
    ("picture", "image"),
    ("article", "link"),
    ("podcast", "audio"),
    ("video", "video"),
    ("photo", "image"),
    ("image", "image"),
    ("audio", "audio"),
    ("clip", "video"),
    ("note", "note"),
    ("link", "link"),
    ("url", "link"),
    ("pdf", "document"),
    ("doc", "document"),
)

#: Openers that carry no content. Stripped from the front only — "find" in
#: the middle of a question is usually part of it ("where did I find that").
OPENERS: tuple[str, ...] = (
    "can you find",
    "do i have",
    "show me",
    "find me",
    "search for",
    "look for",
    "where is",
    "where are",
    "what was",
    "what did",
    "remind me",
    "get me",
    "find",
    "show",
)

#: Words that carry no retrievable content on their own.
#:
#: Used only to *measure* what is left after the filters are removed, and to
#: trim the edges — never to rewrite the middle of a query. Stopword removal
#: inside a phrase would damage the embedding, which reads whole sentences
#: better than bags of keywords.
FILLER = frozenset(
    {
        "a",
        "an",
        "and",
        "about",
        "all",
        "any",
        "anything",
        "around",
        "as",
        "at",
        "be",
        "by",
        "did",
        "do",
        "for",
        "from",
        "have",
        "i",
        "in",
        "is",
        "it",
        "its",
        "me",
        "my",
        "of",
        "on",
        "or",
        "our",
        "saw",
        "some",
        "that",
        "the",
        "their",
        "then",
        "there",
        "these",
        "they",
        "this",
        "those",
        "to",
        "was",
        "watched",
        "we",
        "were",
        "what",
        "when",
        "where",
        "which",
        "with",
        "you",
    }
)

_MONTHS = {name.lower(): number for number, name in enumerate(calendar.month_name) if name} | {
    name.lower(): number for number, name in enumerate(calendar.month_abbr) if name
}


def _month_window(year: int, month: int, tz: tzinfo = UTC) -> tuple[datetime, datetime]:
    start = datetime(year, month, 1, tzinfo=tz)
    last = calendar.monthrange(year, month)[1]
    return start, datetime(year, month, last, 23, 59, 59, tzinfo=tz)


#: Longest names first, so "september" is never read as "sep".
_MONTH_ALTERNATION = "|".join(sorted(_MONTHS, key=len, reverse=True))

#: An explicit day, four ways people write one. Each shape names which group
#: holds the day, the month and the (optional) year.
_DAY_SHAPES: tuple[tuple[re.Pattern[str], int, int, int], ...] = (
    # 2026-09-27
    (re.compile(r"\b(20\d{2})-(\d{1,2})-(\d{1,2})\b"), 3, 2, 1),
    # 27/09/2026, 27-09-2026, 27.09.2026 — day first, as this product's users write it
    (re.compile(r"\b(\d{1,2})[/.-](\d{1,2})[/.-](20\d{2})\b"), 1, 2, 3),
    # 27 sep, 27th of september 2026
    (
        re.compile(
            rf"\b(?:on |from )?(\d{{1,2}})(?:st|nd|rd|th)?\s+(?:of\s+)?"
            rf"({_MONTH_ALTERNATION})\b(?:,?\s+(20\d{{2}}))?"
        ),
        1,
        2,
        3,
    ),
    # sep 27, september 27th, 2026
    (
        re.compile(
            rf"\b(?:on |from )?({_MONTH_ALTERNATION})\s+(\d{{1,2}})(?:st|nd|rd|th)?\b"
            rf"(?:,?\s+(20\d{{2}}))?"
        ),
        2,
        1,
        3,
    ),
)


def _explicit_day(lowered: str, today: datetime) -> tuple[datetime, datetime, str] | None:
    """One named day — "27 Sep" — as that day's window, in `today`'s zone.

    Checked before the bare month names, or "27 sep" reads as all of
    September. Without a year the day is the most recent one that has
    already happened: "27 Sep" asked on 11 Sep is last year's, asked on 27
    Sep it is today. An impossible day (31 Sep) is left for the month rule.
    """
    for pattern, day_at, month_at, year_at in _DAY_SHAPES:
        match = pattern.search(lowered)
        if not match:
            continue
        raw_month = match.group(month_at)
        month = int(raw_month) if raw_month.isdigit() else _MONTHS.get(raw_month)
        if not month or not 1 <= month <= 12:
            continue
        day = int(match.group(day_at))
        given = match.group(year_at)
        year = int(given) if given else today.year
        if not 1 <= day <= calendar.monthrange(year, month)[1]:
            continue
        start = datetime(year, month, day, tzinfo=today.tzinfo)
        if not given and start > today:
            year -= 1
            if day > calendar.monthrange(year, month)[1]:
                continue
            start = start.replace(year=year)
        return start, start.replace(hour=23, minute=59, second=59), pattern.pattern
    return None


def understand_locally(question: str, *, now: datetime | None = None) -> Query:
    """Parse filters out of a question with no network call.

    Returns the same [Query] the model path returned, so retrieval cannot
    tell the difference. Order of work:

    1. Find a type word. First match wins, longest patterns first.
    2. Find a date phrase. First match wins, most specific first — "last
       week" is checked before the bare word "week" could be.
    3. Remove whatever matched from the question, then strip a leading
       opener, and keep the result only if enough of it survives.

    Step 3 is where the value is. Leaving "video" and "july" in the embedded
    text is the problem §24 exists to solve: they get averaged into the
    vector and compete with the content instead of narrowing it.
    """
    moment = now or datetime.now(UTC)
    text = question.strip()
    lowered = text.lower()

    kind: str | None = None
    matched: list[str] = []

    for word, canonical in TYPE_VOCABULARY:
        # `\b...s?\b` so "videos" matches and "videographer" does not.
        pattern = rf"\b{re.escape(word)}s?\b"
        if re.search(pattern, lowered):
            kind = canonical
            matched.append(pattern)
            break

    after, before, date_pattern = _parse_dates(lowered, moment)
    if date_pattern:
        matched.append(date_pattern)

    search = _remainder(text, matched)

    return Query(
        search=search,
        memory_types=TYPE_WORDS.get(kind, ()) if kind else (),
        after=after,
        before=before,
        signals={
            "type": kind,
            "after": after.date().isoformat() if after else None,
            "before": before.date().isoformat() if before else None,
            "rewritten": search != text,
        },
    )


def _remainder(text: str, patterns: list[str]) -> str:
    """What is left to embed once the filters have been lifted out.

    Falls back to the whole question when too little survives, and that
    fallback earns its keep: "show me my screenshots from last week" reduces
    to "my from", which is 6 characters — long enough to pass a length check
    and completely meaningless to embed. Counting *content* words instead of
    characters is what catches it.

    When it does fall back, nothing is lost: the type and date filters still
    apply, so the search is narrowed to screenshots from last week and ranked
    by a vector of the original sentence. Which is the right answer for a
    question that was nothing but filters.
    """
    stripped = text
    for pattern in patterns:
        stripped = re.sub(pattern, " ", stripped, flags=re.IGNORECASE)
    stripped = _strip_opener(stripped)
    stripped = re.sub(r"\s+", " ", stripped).strip(" ,.?!-")

    words = stripped.split()
    # Trim filler off both ends — "invoices from" and "that about vector
    # databases" both read as truncations, and a trailing preposition is a
    # small but real distortion of the embedded text.
    while words and words[0].lower().strip(",.?!") in FILLER:
        words.pop(0)
    while words and words[-1].lower().strip(",.?!") in FILLER:
        words.pop()

    content = [w for w in words if w.lower().strip(",.?!") not in FILLER]
    if len(content) < 1 or len(" ".join(words)) < 3:
        return text
    return " ".join(words)


def _strip_opener(text: str) -> str:
    stripped = text.strip()
    lowered = stripped.lower()
    for opener in OPENERS:
        if lowered.startswith(opener):
            return stripped[len(opener) :].lstrip(" ,")
    return stripped


def _parse_dates(  # noqa: PLR0911 — one return per date shape reads better
    lowered: str, now: datetime
) -> tuple[datetime | None, datetime | None, str | None]:
    """The date window, and the pattern to remove from the search text.

    Most specific first. "last month" has to be tested before a bare month
    name, and "last 7 days" before "last week", or the looser pattern eats
    the tighter one's words and the window comes out wrong.
    """
    today = now.replace(hour=0, minute=0, second=0, microsecond=0)
    # Every window is built in `now`'s zone. The phone passes its local
    # clock; the API passes the phone's offset. "Yesterday" is the user's
    # yesterday, not the one in Greenwich — for a user in India the two
    # disagree until 05:30 every morning.
    tz = today.tzinfo or UTC

    if match := re.search(r"\blast (\d{1,3}) days?\b", lowered):
        days = min(int(match.group(1)), 3650)
        return today - timedelta(days=days), None, r"\blast \d{1,3} days?\b"

    if re.search(r"\b(today)\b", lowered):
        return today, None, r"\b(today)\b"

    if re.search(r"\byesterday\b", lowered):
        yesterday = today - timedelta(days=1)
        return yesterday, yesterday.replace(hour=23, minute=59, second=59), r"\byesterday\b"

    if re.search(r"\b(this|last|past) week\b", lowered):
        return today - timedelta(days=7), None, r"\b(this|last|past) week\b"

    if re.search(r"\b(last|past) month\b", lowered):
        first = today.replace(day=1)
        previous = first - timedelta(days=1)
        start, end = _month_window(previous.year, previous.month, tz)
        return start, end, r"\b(last|past) month\b"

    if re.search(r"\bthis month\b", lowered):
        start, _ = _month_window(today.year, today.month, tz)
        return start, None, r"\bthis month\b"

    if re.search(r"\b(last|past) year\b", lowered):
        year = today.year - 1
        return (
            datetime(year, 1, 1, tzinfo=tz),
            datetime(year, 12, 31, 23, 59, 59, tzinfo=tz),
            r"\b(last|past) year\b",
        )

    if explicit := _explicit_day(lowered, today):
        return explicit

    # A named month, optionally with a year: "in July", "around July 2025".
    for name, number in _MONTHS.items():
        pattern = rf"\b(?:in |around |during |from )?{name}\b(?:\s+(\d{{4}}))?"
        match = re.search(pattern, lowered)
        if not match:
            continue
        year = int(match.group(1)) if match.group(1) else today.year
        # "July" said in March means last July, not a July that has not
        # happened — a question is always about something already saved.
        if not match.group(1) and number > today.month:
            year -= 1
        start, end = _month_window(year, number, tz)
        return start, end, pattern

    if match := re.search(r"\b(20\d{2})\b", lowered):
        year = int(match.group(1))
        return (
            datetime(year, 1, 1, tzinfo=tz),
            datetime(year, 12, 31, 23, 59, 59, tzinfo=tz),
            r"\b20\d{2}\b",
        )

    return None, None, None


def plain(question: str) -> Query:
    """The no-filters reading, for when extraction fails or is skipped."""
    return Query(search=question)


async def understand(question: str, *, now: datetime | None = None) -> Query:
    """Extract filters. Never raises, and by default never waits on anything.

    Still `async` even though the default path does no I/O, because both
    callers are already in a coroutine and making them branch on whether this
    one happens to need the network would push the decision into every call
    site. The cost of an await on an already-complete result is nil.
    """
    if os.environ.get("QUERY_MODEL_UNDERSTANDING") != "1":
        return understand_locally(question, now=now)
    return await understand_with_model(question, now=now)


async def understand_with_model(question: str, *, now: datetime | None = None) -> Query:
    """The model path. Off by default — see this module's docstring.

    Deliberately forgiving: this is an optimisation on top of semantic search,
    not a precondition for it. A question that cannot be parsed should still
    be answered, slightly less precisely, rather than failing.
    """
    today = (now or datetime.now(UTC)).date().isoformat()

    try:
        raw = await gemini.generate(
            SYSTEM,
            f"TODAY: {today}\n\nQUESTION: {question}",
            max_tokens=300,
        )
        parsed = json.loads(raw)
    except Exception:
        # Not `plain`: the local parser is still better than nothing, and a
        # 503 from the model is no reason to discard filters we can read
        # ourselves.
        return understand_locally(question, now=now)

    if not isinstance(parsed, dict):
        return understand_locally(question, now=now)

    search = str(parsed.get("search") or "").strip()
    # A model that strips too aggressively can leave a fragment that matches
    # nothing. Below a few characters, trust the original.
    if len(search) < 3:
        search = question

    kind = parsed.get("type")
    types = TYPE_WORDS.get(str(kind), ()) if kind else ()

    return Query(
        search=search,
        memory_types=types,
        after=_date(parsed.get("after"), end=False),
        before=_date(parsed.get("before"), end=True),
        signals={
            "type": kind,
            "after": parsed.get("after"),
            "before": parsed.get("before"),
            "rewritten": search != question,
        },
    )


def _date(raw: object, *, end: bool) -> datetime | None:
    if not raw:
        return None
    try:
        parsed = datetime.fromisoformat(str(raw))
    except ValueError:
        return None
    stamped = parsed if parsed.tzinfo else parsed.replace(tzinfo=UTC)
    # "before 2026-07-31" has to include the whole of the 31st, or a date
    # range of one day matches nothing.
    return stamped.replace(hour=23, minute=59, second=59) if end else stamped


def contextualise(question: str, history: list[dict], *, limit: int = 4) -> str:
    """Fold a follow-up into a question that can stand on its own.

    "What about Team?" retrieves nothing on its own — the subject is in the
    previous turn. Rather than spend a model call resolving the pronoun, the
    recent turns are prepended to the *embedding text* only: the model still
    receives the question as asked, so it never answers a question the user
    did not ask, but retrieval gets the missing nouns.

    Cheap, and it fails in the harmless direction: a follow-up about something
    genuinely new is only slightly diluted by the context, whereas a resolved
    rewrite that guessed wrong would search for the wrong thing entirely.
    """
    if not history:
        return question

    recent = [
        str(turn.get("text") or "").strip()
        for turn in history[-limit:]
        if turn.get("role") == "user"
    ]
    recent = [t for t in recent if t]
    if not recent:
        return question

    return " ".join([*recent, question])
