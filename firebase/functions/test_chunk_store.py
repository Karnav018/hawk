"""A memory's chunks leave with it — visibly first, for good later."""

from datetime import UTC, datetime, timedelta

from firebase_admin import firestore

import chunk_store
import index_budget

NOW = datetime(2026, 9, 27, 12, tzinfo=UTC)


class _Ref:
    def __init__(self, doc):
        self.doc = doc


class _Doc:
    def __init__(self, id: str, data: dict):
        self.id = id
        self.data = dict(data)
        self.reference = _Ref(self)

    def to_dict(self) -> dict:
        return dict(self.data)


class _Query:
    def __init__(self, docs: list[_Doc]):
        self._docs = docs
        self._limit = None

    def where(self, field, op, value):
        def keep(d: _Doc) -> bool:
            have = d.data.get(field)
            if op == "==":
                return have == value
            if op == "<":
                return have is not None and have < value
            raise AssertionError(op)

        q = _Query([d for d in self._docs if keep(d)])
        return q

    def select(self, fields):
        return self

    def limit(self, n):
        self._limit = n
        return self

    def stream(self):
        return iter(self._docs[: self._limit] if self._limit else self._docs)


class _Batch:
    def __init__(self, db):
        self._db = db
        self.ops: list = []

    def update(self, ref, fields):
        self.ops.append(("update", ref.doc, fields))

    def delete(self, ref):
        self.ops.append(("delete", ref.doc, None))

    def commit(self):
        for op, doc, fields in self.ops:
            if op == "update":
                doc.data.update(fields)
            else:
                self._db.docs.remove(doc)
        self._db.commits.append(len(self.ops))


class _Db:
    def __init__(self, docs: list[_Doc]):
        self.docs = docs
        self.commits: list[int] = []

    def collection(self, name: str) -> _Query:
        assert name == "chunks"
        return _Query(list(self.docs))

    def batch(self) -> _Batch:
        return _Batch(self)


def _chunks(memory_id: str, n: int, text: str = "some text", **extra) -> list[_Doc]:
    return [
        _Doc(f"{memory_id}-{i}", {"memoryId": memory_id, "text": text, **extra}) for i in range(n)
    ]


class TestDelete:
    def test_the_chunks_are_marked_so_a_delta_sync_sees_them(self, monkeypatch):
        released: list = []
        monkeypatch.setattr(index_budget, "release", lambda uid, amount: released.append(amount))
        db = _Db(_chunks("m1", 3) + _chunks("m2", 2))

        assert chunk_store.delete_for_memory(db, uid="u1", memory_id="m1") == 3

        marked = [d for d in db.docs if d.data.get("deleted")]
        assert sorted(d.id for d in marked) == ["m1-0", "m1-1", "m1-2"]
        for d in marked:
            assert d.data["text"] == ""
            assert d.data["updatedAt"] is firestore.SERVER_TIMESTAMP
            assert d.data["embedding"] is firestore.DELETE_FIELD
        # Still there: a hard delete would be an absence a delta never shows.
        assert len(db.docs) == 5
        assert released == [3 * index_budget.chunk_cost("some text")]

    def test_a_second_delete_refunds_nothing(self, monkeypatch):
        # Re-index then delete: the first pass already gave the bytes back.
        released: list = []
        monkeypatch.setattr(index_budget, "release", lambda uid, amount: released.append(amount))
        db = _Db(_chunks("m1", 2, text="", deleted=True))

        assert chunk_store.delete_for_memory(db, uid="u1", memory_id="m1") == 0
        assert released == [] and db.commits == []

    def test_a_large_memory_is_marked_in_batches(self, monkeypatch):
        monkeypatch.setattr(index_budget, "release", lambda uid, amount: None)
        db = _Db(_chunks("big", chunk_store.BATCH + 1))

        assert chunk_store.delete_for_memory(db, uid="u1", memory_id="big") == chunk_store.BATCH + 1
        assert db.commits == [chunk_store.BATCH, 1]


class TestSweep:
    def test_only_old_tombstones_go(self):
        old = NOW - timedelta(days=chunk_store.TOMBSTONE_DAYS + 1)
        recent = NOW - timedelta(days=2)
        db = _Db(
            _chunks("gone", 2, text="", deleted=True, updatedAt=old)
            + _chunks("fresh", 1, text="", deleted=True, updatedAt=recent)
            + _chunks("live", 1, updatedAt=old)
        )

        assert chunk_store.sweep(db, now=NOW) == 2
        assert sorted(d.id for d in db.docs) == ["fresh-0", "live-0"]

    def test_nothing_to_sweep_writes_nothing(self):
        db = _Db(_chunks("live", 3, updatedAt=NOW))
        assert chunk_store.sweep(db, now=NOW) == 0
        assert db.commits == []
