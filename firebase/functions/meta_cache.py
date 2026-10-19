"""A short memory for the memory documents that search and ask decorate with.

Every search ends with one `get_all` over the memories its passages came
from, to put a title, a type and somewhere to open on each row. Measured at
30–170 ms a search — and the same handful of memories come back search after
search within one session, because a person asks about the same few files.
The app also fires `search` and `ask` together, so each question fetched the
same memory documents twice within a second.

Per instance and per process: nothing is shared between instances, and an
instance that dies takes its cache with it. That is fine — this is a
shortcut, not a store.
"""

from __future__ import annotations

import time
from collections.abc import Callable, Iterable

#: How long an entry is trusted.
#:
#: Short, because a title can be renamed and a kept file's `storagePath`
#: appears when indexing finishes. Two minutes bounds how stale a row can be
#: while still covering a session's worth of follow-ups.
TTL_SECONDS = 120.0


class MetaCache:
    """Memory metadata by id, forgotten after [TTL_SECONDS]."""

    def __init__(self, *, ttl: float = TTL_SECONDS, clock: Callable[[], float] = time.monotonic):
        self._ttl = ttl
        self._clock = clock
        self._entries: dict[str, tuple[float, dict]] = {}

    def get_many(self, ids: Iterable[str]) -> tuple[dict[str, dict], list[str]]:
        """Split [ids] into what is cached and fresh, and what must be read."""
        now = self._clock()
        found: dict[str, dict] = {}
        missing: list[str] = []
        for memory_id in ids:
            entry = self._entries.get(memory_id)
            if entry is not None and entry[0] > now:
                found[memory_id] = entry[1]
            else:
                self._entries.pop(memory_id, None)
                missing.append(memory_id)
        return found, missing

    def put(self, memory_id: str, meta: dict, *, settled: bool) -> None:
        """Remember [meta] — but only once the memory is settled.

        A memory that is still being indexed changes under us: its
        `storagePath` is written in the same update that marks it ready. An
        entry cached a second earlier would say the file is not kept, and
        keep saying so for the whole TTL. So an unsettled memory is looked up
        every time until it is.
        """
        if not settled:
            return
        self._entries[memory_id] = (self._clock() + self._ttl, meta)

    def forget(self, memory_id: str) -> None:
        self._entries.pop(memory_id, None)

    def __len__(self) -> int:
        return len(self._entries)
