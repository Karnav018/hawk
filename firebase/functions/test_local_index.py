"""The server's half of the on-device index: what it will embed, and which
of a device's chosen passages it will answer from."""

from __future__ import annotations

import pytest

import local_index


class TestBoundedTexts:
    def test_a_normal_batch_passes_through(self) -> None:
        assert local_index.bounded_texts(["a chunk", "another"]) == ["a chunk", "another"]

    def test_the_batch_is_capped_at_what_one_embed_call_takes(self) -> None:
        with pytest.raises(local_index.BadRequest):
            local_index.bounded_texts(["x"] * (local_index.MAX_TEXTS + 1))

    def test_a_novel_is_cut_to_the_bound_not_refused(self) -> None:
        # One over-long chunk used to fail the batch it travelled in — every
        # time — so the phone could never finish its index.
        [cut] = local_index.bounded_texts(["y" * (local_index.MAX_TEXT_CHARS + 1)])
        assert len(cut) == local_index.MAX_TEXT_CHARS

    def test_nothing_and_blanks_are_refused(self) -> None:
        for bad in ([], None, "text", ["ok", "   "], [42]):
            with pytest.raises(local_index.BadRequest):
                local_index.bounded_texts(bad)


class TestRequestedPassages:
    def test_keeps_the_device_order_and_clamps_distances(self) -> None:
        got = local_index.requested_passages(
            [
                {"chunkId": "c2", "distance": 0.31},
                {"chunkId": "c1", "distance": -1},
                {"chunkId": "c3", "distance": 9},
                {"chunkId": "c4"},
            ]
        )
        assert got == [("c2", 0.31), ("c1", 0.0), ("c3", 2.0), ("c4", 0.5)]

    def test_a_repeated_id_counts_once(self) -> None:
        got = local_index.requested_passages([{"chunkId": "c1"}, {"chunkId": "c1"}])
        assert [c for c, _ in got] == ["c1"]

    def test_too_many_is_refused(self) -> None:
        too_many = [{"chunkId": f"c{i}"} for i in range(local_index.MAX_PASSAGES + 1)]
        with pytest.raises(local_index.BadRequest):
            local_index.requested_passages(too_many)

    def test_shapes_that_are_not_passages_are_refused(self) -> None:
        for bad in (
            "c1",
            [{"distance": 0.1}],
            [{"chunkId": ""}],
            [{"chunkId": "c1", "distance": "x"}],
        ):
            with pytest.raises(local_index.BadRequest):
                local_index.requested_passages(bad)


class TestPassagesFromDocs:
    """The server reads the chosen chunks itself — the device sends ids,
    never text — and answers only from what is the caller's and still
    recallable."""

    def _docs(self) -> dict:
        return {
            "mine": {"userId": "u1", "memoryId": "m1", "text": "Team is $29", "chunkIndex": 3},
            "dormant": {
                "userId": "u1",
                "memoryId": "m2",
                "text": "old",
                "chunkIndex": 0,
                "recallState": "dormant",
            },
            "theirs": {"userId": "u2", "memoryId": "m9", "text": "not yours", "chunkIndex": 0},
            "gone": None,
            "empty": {"userId": "u1", "memoryId": "m3", "text": "", "chunkIndex": 0},
        }

    def test_only_the_callers_active_passages_survive(self) -> None:
        requested = [(c, 0.2) for c in ("mine", "dormant", "theirs", "gone", "empty")]
        out = local_index.passages_from_docs(requested, self._docs(), "u1")
        assert [p.chunk_id for p in out] == ["mine"]
        assert out[0].memory_id == "m1"
        assert out[0].text == "Team is $29"
        assert out[0].chunk_index == 3
        assert out[0].distance == 0.2

    def test_the_devices_order_is_the_rank(self) -> None:
        docs = {
            f"c{i}": {"userId": "u1", "memoryId": "m", "text": f"t{i}", "chunkIndex": i}
            for i in range(3)
        }
        out = local_index.passages_from_docs([("c2", 0.1), ("c0", 0.3), ("c1", 0.2)], docs, "u1")
        assert [p.chunk_id for p in out] == ["c2", "c0", "c1"]
        assert [p.vector_rank for p in out] == [1, 2, 3]
        assert out[0].relevance > out[2].relevance

    def test_nothing_chosen_means_nothing_answered_from(self) -> None:
        assert local_index.passages_from_docs([], {}, "u1") == []
