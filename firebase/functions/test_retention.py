"""Retention: what ages out, what comes back, and that the chunks follow."""

from datetime import UTC, datetime, timedelta

from firebase_admin import firestore

import billing
import chunk_store
import retention

NOW = datetime(2026, 9, 27, 12, tzinfo=UTC)
FREE = billing.entitlements_for(billing.FREE)
PREMIUM = billing.entitlements_for(billing.PREMIUM)


def _memory(days_old: int, **extra) -> dict:
    return {"userId": "u1", "createdAt": NOW - timedelta(days=days_old), **extra}


class TestDecide:
    def test_free_memory_past_thirty_days_goes_dormant_with_its_chunks(self):
        d = retention.decide(_memory(31, chunkCount=3), FREE, NOW)
        assert d.action == "demote"
        assert d.update["recallState"] == "dormant"
        assert d.chunks_to == "dormant"

    def test_inside_the_window_nothing_happens(self):
        created = NOW - timedelta(days=5)
        data = _memory(5, recallExpiresAt=created + timedelta(days=30))
        assert retention.decide(data, FREE, NOW).action is None

    def test_an_upgrade_brings_it_back_without_reading_it_again(self):
        data = _memory(200, recallState="dormant", chunkRecall="dormant", chunkCount=4)
        d = retention.decide(data, PREMIUM, NOW)
        assert d.action == "promote"
        assert d.update["recallState"] == "active"
        assert d.chunks_to == "active"
        # Its chunks were kept — nothing to re-extract.
        assert "status" not in d.update

    def test_a_revived_memory_with_nothing_indexed_is_read_again(self):
        data = _memory(200, recallState="dormant", chunkRecall="dormant", chunkCount=0)
        assert retention.decide(data, PREMIUM, NOW).update["status"] == "extracted"

    def test_a_disconnected_source_is_never_revived_by_a_plan(self):
        # Reconnecting revives it, not upgrading — the old sweep got this wrong.
        data = _memory(2, recallState="dormant", chunkRecall="dormant", sourceAvailable=False)
        assert retention.decide(data, PREMIUM, NOW).action is None

    def test_chunks_that_disagree_with_their_memory_are_healed(self):
        # The bug: a memory marked dormant whose chunks stayed active.
        data = _memory(3, recallState="dormant", sourceAvailable=False)
        d = retention.decide(data, PREMIUM, NOW)
        assert d.action == "heal" and d.chunks_to == "dormant"

    def test_a_stale_stamp_is_corrected_not_obeyed(self):
        # A test account stamped with Free's window, now resolved as Premium.
        data = _memory(40, recallExpiresAt=NOW - timedelta(days=10))
        d = retention.decide(data, PREMIUM, NOW)
        assert d.action == "restamp"
        assert d.update == {"recallExpiresAt": None}

    def test_no_capture_date_is_left_alone(self):
        assert retention.decide({"userId": "u1"}, FREE, NOW).action is None


# ---------------------------------------------------------------- a fake Firestore


class _Ref:
    def __init__(self, doc):
        self.doc = doc


class _Doc:
    def __init__(self, id: str, data: dict):
        self.id = id
        self.data = dict(data)
        self.reference = _Ref(self)

    def to_dict(self):
        return dict(self.data)


class _Query:
    def __init__(self, docs, log):
        self._docs, self._log = list(docs), log
        self._limit, self._after, self._order = None, None, None

    def where(self, field, op, value):
        def keep(d):
            have = d.data.get(field)
            if op == "==":
                return have == value
            if op == "<":
                return have is not None and have < value
            if op == "in":
                return have in value
            raise AssertionError(op)

        self._log.append((field, op))
        q = _Query([d for d in self._docs if keep(d)], self._log)
        return q

    def select(self, fields):
        return self

    def order_by(self, field):
        self._order = field
        self._docs.sort(key=lambda d: d.data.get(field))
        return self

    def limit(self, n):
        self._limit = n
        return self

    def start_after(self, doc):
        self._after = doc
        return self

    def stream(self):
        docs = self._docs
        if self._after is not None:
            docs = docs[docs.index(self._after) + 1 :]
        return iter(docs[: self._limit] if self._limit else docs)


class _Batch:
    def __init__(self, db):
        self._db, self.ops = db, []

    def update(self, ref, fields):
        self.ops.append((ref.doc, fields))

    def commit(self):
        for doc, fields in self.ops:
            doc.data.update(fields)
            self._db.order.append(doc.id)


class _Db:
    def __init__(self, memories, chunks):
        self.tables = {"memories": memories, "chunks": chunks}
        self.order: list[str] = []
        self.queries: list = []

    def collection(self, name):
        return _Query(self.tables[name], self.queries)

    def batch(self):
        return _Batch(self)


def _chunks(memory_id, n, state="active", **extra):
    return [
        _Doc(f"{memory_id}-c{i}", {"memoryId": memory_id, "recallState": state, **extra})
        for i in range(n)
    ]


class TestSettle:
    def test_chunks_flip_before_their_memories_and_bump_updated_at(self):
        old = _Doc("old", _memory(40, chunkCount=2))
        fresh = _Doc("fresh", _memory(2, chunkCount=1, recallExpiresAt=NOW + timedelta(days=28)))
        db = _Db([old, fresh], _chunks("old", 2) + _chunks("fresh", 1))

        counts = retention.settle(db, [old, fresh], lambda _: FREE, NOW)

        assert counts["demote"] == 1
        assert old.data["recallState"] == "dormant"
        assert old.data["chunkRecall"] == "dormant"
        old_chunks = [c for c in db.tables["chunks"] if c.data["memoryId"] == "old"]
        assert all(c.data["recallState"] == "dormant" for c in old_chunks)
        assert all(c.data["updatedAt"] is firestore.SERVER_TIMESTAMP for c in old_chunks)
        # The fresh memory's chunk is untouched.
        assert db.tables["chunks"][-1].data["recallState"] == "active"
        # Chunks were written before the memory.
        assert db.order.index("old-c0") < db.order.index("old")


class TestSweep:
    def test_it_demotes_what_aged_out_under_the_plan_as_it_is_today(self, monkeypatch):
        free_old = _Doc(
            "a",
            _memory(
                40,
                userId="free",
                chunkCount=1,
                recallState="active",
                recallExpiresAt=NOW - timedelta(days=10),
            ),
        )
        # Stamped with Free's window, but the account is Premium now.
        now_premium = _Doc(
            "b",
            _memory(
                40,
                userId="prem",
                chunkCount=1,
                recallState="active",
                recallExpiresAt=NOW - timedelta(days=10),
            ),
        )
        not_due = _Doc(
            "c",
            _memory(
                5,
                userId="free",
                chunkCount=1,
                recallState="active",
                recallExpiresAt=NOW + timedelta(days=25),
            ),
        )
        db = _Db(
            [free_old, now_premium, not_due], _chunks("a", 1) + _chunks("b", 1) + _chunks("c", 1)
        )
        plans = {"free": FREE, "prem": PREMIUM}
        monkeypatch.setattr(retention, "entitlements_for", lambda _db, uid: plans[uid])

        counts = retention.sweep(db, NOW)

        assert counts["demote"] == 1 and counts["restamp"] == 1
        assert free_old.data["recallState"] == "dormant"
        assert now_premium.data["recallState"] == "active"
        assert now_premium.data["recallExpiresAt"] is None
        assert not_due.data["recallState"] == "active"
        assert db.tables["chunks"][0].data["recallState"] == "dormant"
        assert db.tables["chunks"][1].data["recallState"] == "active"


class TestChunkFlip:
    def test_only_those_memories_and_only_what_differs(self):
        db = _Db(
            [],
            _chunks("m1", 2)
            + _chunks("m2", 1, state="dormant")
            + _chunks("m3", 1, deleted=True)
            + _chunks("other", 1),
        )
        changed = chunk_store.set_recall_state(db, ["m1", "m2", "m3"], "dormant")
        assert changed == 2
        states = {c.id: c.data["recallState"] for c in db.tables["chunks"]}
        assert states == {
            "m1-c0": "dormant",
            "m1-c1": "dormant",
            "m2-c0": "dormant",
            "m3-c0": "active",
            "other-c0": "active",
        }

    def test_more_memories_than_one_in_filter_takes(self):
        ids = [f"m{i}" for i in range(chunk_store.IN_LIMIT + 5)]
        db = _Db([], [c for mid in ids for c in _chunks(mid, 1)])
        assert chunk_store.set_recall_state(db, ids, "dormant") == len(ids)
        assert sum(1 for f, op in db.queries if op == "in") == 2
