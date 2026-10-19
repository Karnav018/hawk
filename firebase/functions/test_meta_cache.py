"""The memory-metadata cache behind `_memories` — what it keeps, for how long,
and what it refuses to keep."""

from __future__ import annotations

from meta_cache import MetaCache


class _Clock:
    def __init__(self) -> None:
        self.now = 1000.0

    def __call__(self) -> float:
        return self.now


def test_a_settled_memory_is_answered_without_a_read() -> None:
    clock = _Clock()
    cache = MetaCache(ttl=120, clock=clock)
    cache.put("m1", {"title": "lease.pdf"}, settled=True)

    found, missing = cache.get_many(["m1", "m2"])
    assert found == {"m1": {"title": "lease.pdf"}}
    assert missing == ["m2"]


def test_entries_expire_after_the_ttl() -> None:
    clock = _Clock()
    cache = MetaCache(ttl=120, clock=clock)
    cache.put("m1", {"title": "lease.pdf"}, settled=True)

    clock.now += 119
    assert cache.get_many(["m1"])[0], "still fresh a second before the TTL"
    clock.now += 2
    found, missing = cache.get_many(["m1"])
    assert found == {} and missing == ["m1"]
    assert len(cache) == 0, "an expired entry is dropped, not kept around"


def test_a_memory_still_indexing_is_never_cached() -> None:
    # Its `storagePath` lands in the same update that marks it ready; a row
    # cached a second earlier would say the file is not kept for two minutes.
    cache = MetaCache(ttl=120, clock=_Clock())
    cache.put("m1", {"title": "scan.pdf", "storagePath": None}, settled=False)
    assert cache.get_many(["m1"]) == ({}, ["m1"])


def test_forget_drops_one_entry() -> None:
    cache = MetaCache(ttl=120, clock=_Clock())
    cache.put("m1", {"title": "a"}, settled=True)
    cache.put("m2", {"title": "b"}, settled=True)
    cache.forget("m1")
    assert cache.get_many(["m1", "m2"]) == ({"m2": {"title": "b"}}, ["m1"])
