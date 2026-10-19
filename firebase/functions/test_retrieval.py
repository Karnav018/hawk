"""Tests for the retrieval and RAG layers.

Everything here is the pure part: fusion, lexical scoring, chunking, the
citation contract. The Firestore KNN call and the model calls are not mocked —
mocking them would test the mock. What *is* tested is the logic that decides
what reaches the user, which is where the interesting mistakes live.
"""

from __future__ import annotations

import asyncio
import os
from datetime import UTC, datetime

import pytest

os.environ.setdefault("GEMINI_API_KEY", "test-key")

import chunking
import rag
import retrieval
from query_understanding import Query
from retrieval import Passage


def passage(n: int, *, distance: float = 0.2, text: str = "text", memory: str = "m1") -> Passage:
    return Passage(
        chunk_id=f"c{n}",
        memory_id=memory,
        text=text,
        chunk_index=n,
        distance=distance,
        vector_rank=n,
        lexical_rank=n,
        score=1.0 / n,
    )


class TestFusion:
    def test_a_keyword_only_hit_survives(self):
        """The whole reason hybrid retrieval exists.

        A passage the embedding ranked last but the keyword stage ranked first
        must outrank one the embedding liked and the keyword stage never saw —
        that is the exact-name, exact-figure case an embedding smooths away.
        """
        fused = retrieval._fuse(["a", "b", "c"], ["c"])
        assert fused["c"] > fused["b"]

    def test_agreement_wins(self):
        fused = retrieval._fuse(["a", "b"], ["a", "b"])
        assert fused["a"] > fused["b"]

    def test_ranks_not_scores(self):
        """RRF must not care about the magnitude of either input.

        This is why it was chosen: a cosine distance and a term-overlap count
        live on unrelated scales, and any fixed weighting between them is a
        guess that silently favours one retriever.
        """
        a = retrieval._fuse(["x", "y"], ["y", "x"])
        b = retrieval._fuse(["x", "y"], ["y", "x"])
        assert a == b


class TestLexical:
    def test_rare_terms_count_for_more(self):
        cands = [
            {"id": "a", "text": "pricing pricing pricing generic filler words"},
            {"id": "b", "text": "the Scale tier is quoted individually"},
        ]
        scores = retrieval._lexical("what is the Scale tier", cands)
        assert scores["b"] > scores["a"]

    def test_repetition_saturates(self):
        """A chunk that merely repeats a query word must not beat one that
        answers. Without saturating term frequency, volume wins."""
        cands = [
            {"id": "a", "text": " ".join(["pricing"] * 40)},
            {"id": "b", "text": "pricing is three tiers billed annually"},
        ]
        scores = retrieval._lexical("pricing tiers", cands)
        assert scores["b"] > scores["a"]

    def test_stopwords_carry_no_signal(self):
        cands = [{"id": "a", "text": "the and of to was"}]
        assert retrieval._lexical("what was the", cands).get("a", 0) == 0

    def test_a_query_of_only_stopwords_scores_nothing(self):
        cands = [{"id": "a", "text": "pricing tiers"}]
        assert retrieval._lexical("what is the", cands) == {}


class TestRelevance:
    def test_distance_maps_to_a_percentage(self):
        assert passage(1, distance=0.0).relevance == 100
        assert passage(1, distance=2.0).relevance == 0
        assert 40 < passage(1, distance=1.0).relevance < 60

    def test_never_leaves_the_range(self):
        # Firestore can report a distance marginally outside [0, 2] on
        # near-identical vectors; the number on screen must still be sane.
        assert passage(1, distance=-0.01).relevance == 100
        assert passage(1, distance=2.5).relevance == 0


class TestCitationContract:
    """§28 — an uncited answer is a bug, not a degraded result."""

    def _answer(self, payload: dict, passages: list[Passage]):
        import asyncio
        import json

        async def fake_generate(system, prompt, **kw):
            return json.dumps(payload)

        original = rag.gemini.generate
        rag.gemini.generate = fake_generate
        try:
            return asyncio.run(rag.answer("q", passages))
        finally:
            rag.gemini.generate = original

    def test_no_passages_means_no_model_call(self):
        import asyncio

        def explode(*a, **k):
            raise AssertionError("the model must not be asked with no context")

        original = rag.gemini.generate
        rag.gemini.generate = explode
        try:
            result = asyncio.run(rag.answer("q", []))
        finally:
            rag.gemini.generate = original

        assert result.answered is False
        assert result.citations == ()
        assert "Nothing in your vault" in result.blocks[0].text

    def test_a_block_citing_a_nonexistent_source_is_dropped(self):
        """Models invent citation numbers under pressure to look thorough.

        A claim whose stated evidence does not exist is not an uncited claim
        to show with a caveat — it is a fabricated one, and it goes.
        """
        result = self._answer(
            {
                "blocks": [
                    {"text": "Real claim.", "citations": [1]},
                    {"text": "Invented claim.", "citations": [7]},
                ],
                "confidence": "high",
                "answered": True,
            },
            [passage(1)],
        )
        texts = [b.text for b in result.blocks]
        assert "Real claim." in texts
        assert "Invented claim." not in texts

    def test_citations_are_renumbered_to_match_the_sources_list(self):
        """The superscript the reader sees must index the list beneath it."""
        result = self._answer(
            {
                "blocks": [{"text": "Claim.", "citations": [3]}],
                "confidence": "medium",
                "answered": True,
            },
            [passage(1), passage(2), passage(3, memory="m3")],
        )
        assert result.blocks[0].citations == (1,)
        assert len(result.citations) == 1
        assert result.citations[0].memory_id == "m3"

    def test_uncited_sources_are_not_listed(self):
        # A SOURCES list containing passages nothing referred to invites the
        # reader to check something the answer never claimed.
        result = self._answer(
            {
                "blocks": [{"text": "Claim.", "citations": [1]}],
                "confidence": "high",
                "answered": True,
            },
            [passage(1), passage(2), passage(3)],
        )
        assert len(result.citations) == 1

    def test_an_answer_with_nothing_left_says_so(self):
        result = self._answer(
            {"blocks": [{"text": "", "citations": []}], "confidence": "high", "answered": True},
            [passage(1)],
        )
        assert result.answered is False
        assert "could not answer" in result.blocks[0].text

    def test_a_block_that_claims_nothing_may_be_uncited(self):
        # The "I cannot answer that" block legitimately has no citations.
        result = self._answer(
            {
                "blocks": [{"text": "The sources do not cover that.", "citations": []}],
                "confidence": "low",
                "answered": False,
            },
            [passage(1)],
        )
        assert result.answered is False
        assert result.blocks[0].citations == ()


class TestConfidence:
    def test_a_distant_best_match_caps_confidence(self):
        """The model sees the passages but not how far away they were, so it
        cannot tell a precise hit from the least-bad of sixty."""
        assert rag._confidence("high", [passage(1, distance=1.4)], 3) == "low"

    def test_one_source_is_not_corroboration(self):
        assert rag._confidence("high", [passage(1, distance=0.1)], 1) == "medium"

    def test_close_and_corroborated_keeps_high(self):
        assert rag._confidence("high", [passage(1, distance=0.1)], 3) == "high"

    def test_an_unrecognised_self_report_is_low(self):
        assert rag._confidence("extremely-high", [passage(1, distance=0.1)], 3) == "low"


class TestChunking:
    def test_a_short_document_is_one_chunk(self):
        assert len(chunking.split("One short note.")) == 1

    def test_empty_input_yields_nothing(self):
        assert chunking.split("   \n\n  ") == []

    def test_indices_are_contiguous(self):
        text = "Sentence number one is here. " * 200
        chunks = chunking.split(text)
        assert [c.index for c in chunks] == list(range(len(chunks)))

    def test_chunks_overlap_so_a_boundary_fact_survives(self):
        text = " ".join(f"Fact {i} is recorded plainly." for i in range(200))
        chunks = chunking.split(text)
        assert len(chunks) > 1
        # Consecutive chunks must share some text, or a fact sitting exactly
        # on a boundary appears in neither whole.
        assert any(
            set(chunks[i].text.split()) & set(chunks[i + 1].text.split())
            for i in range(len(chunks) - 1)
        )

    def test_line_wraps_are_not_paragraph_breaks(self):
        # PDF extraction wraps mid-sentence; treating each wrap as a break
        # would split subjects from predicates.
        assert "\n" not in chunking.normalise("a line\nwrapped mid sentence")
        assert "\n\n" in chunking.normalise("para one\n\npara two")

    def test_soft_hyphens_are_removed(self):
        assert chunking.normalise("hy­phen") == "hyphen"


class TestEmbeddingContract:
    def test_the_dimension_matches_the_deployed_index(self):
        """Firestore rejects a KNN query whose vector length disagrees with
        the index, so this constant and firestore.indexes.json are one fact
        stored twice."""
        import json
        import pathlib

        import gemini

        cfg = json.loads(
            (pathlib.Path(__file__).resolve().parents[1] / "firestore.indexes.json").read_text()
        )
        dims = {
            f["vectorConfig"]["dimension"]
            for i in cfg["indexes"]
            for f in i["fields"]
            if "vectorConfig" in f
        }
        assert dims == {gemini.DIMENSIONS}

    def test_truncated_vectors_are_renormalised(self):
        """Verified against the live API: a 1536-dimension Gemini embedding
        comes back with norm ~0.69, not 1.0. Cosine distance over vectors of
        varying magnitude is quietly wrong, and Firestore cannot tell us the
        inputs were malformed."""
        import math

        import gemini

        raw = [0.3] * 8
        unit = gemini._unit(raw)
        assert math.isclose(math.sqrt(sum(v * v for v in unit)), 1.0, rel_tol=1e-9)

    def test_a_zero_vector_does_not_divide_by_zero(self):
        import gemini

        assert gemini._unit([0.0, 0.0]) == [0.0, 0.0]


class TestIndexBudget:
    """`index_bytes` was in the plan table from the start and enforced
    nowhere, which made it a label on a pricing page. The derived layer is the
    only thing this product hosts (§43), so it is the number that bounds a
    user's real footprint."""

    def _ent(self, limit):
        import billing

        return billing.Entitlements(
            tier="test",
            memory_window_days=None,
            backup_window_days=None,
            index_bytes=limit,
            connected_accounts=None,
            window_queries=None,
            weekly_queries=None,
        )

    def test_the_vector_dominates_the_cost(self):
        """1536 doubles is 12.3 KB, which swamps the text for any normal
        passage — so the number a user sees moves with what costs money."""
        import index_budget as b

        assert b.VECTOR_BYTES == 1536 * 8
        assert b.chunk_cost("x" * 1000) < 2 * b.VECTOR_BYTES

    def test_an_unlimited_plan_is_never_trimmed(self, monkeypatch):
        import index_budget as b

        monkeypatch.setattr(b, "used", lambda uid: 0)
        texts = ["a" * 500] * 50
        kept, note = b.fit("u", self._ent(None), texts)
        assert kept == texts
        assert note is None

    def test_the_per_memory_share_stops_one_capture_taking_everything(self, monkeypatch):
        """A link to a 900-page manual is a legitimate save. Indexing all of
        it would leave no room for the next four hundred notes."""
        import index_budget as b

        monkeypatch.setattr(b, "used", lambda uid: 0)
        limit = 100 * b.VECTOR_BYTES
        texts = ["x"] * 100
        kept, note = b.fit("u", self._ent(limit), texts)

        assert 0 < len(kept) < len(texts)
        assert note is not None
        assert "per-item limit" in note

    def test_truncation_is_always_visible(self, monkeypatch):
        """Silent truncation is the failure mode that matters: an answer that
        cannot see the second half of a document is indistinguishable from a
        document that never said it."""
        import index_budget as b

        monkeypatch.setattr(b, "used", lambda uid: 0)
        kept, note = b.fit("u", self._ent(40 * b.VECTOR_BYTES), ["x"] * 100)
        assert note is not None
        assert str(len(kept)) in note
        assert "100" in note

    def test_a_full_index_refuses_rather_than_truncating_to_nothing(self, monkeypatch):
        import index_budget as b

        limit = 1000 * b.VECTOR_BYTES
        monkeypatch.setattr(b, "used", lambda uid: limit)
        kept, note = b.fit("u", self._ent(limit), ["x"] * 10)
        assert kept == []
        assert "full" in note

    def test_the_account_ceiling_is_named_differently_from_the_item_one(self, monkeypatch):
        # The remedies differ — upgrade versus nothing you can do — so the
        # note has to say which limit bit.
        import index_budget as b

        limit = 1000 * b.VECTOR_BYTES
        monkeypatch.setattr(b, "used", lambda uid: int(limit * 0.99))
        _, note = b.fit("u", self._ent(limit), ["x"] * 100)
        assert "plan" in note

    def test_cost_is_additive(self):
        import index_budget as b

        assert b.cost_of(["a", "b"]) == b.chunk_cost("a") + b.chunk_cost("b")


class TestSourceLinks:
    """A synced memory stores its file id; the link is derived from it."""

    def test_a_drive_memory_gets_an_openable_link(self):
        import api

        assert (
            api._source_url({"provider": "google_drive", "sourceRef": "1AbC"})
            == "https://drive.google.com/open?id=1AbC"
        )

    def test_nothing_is_invented_without_a_file_id(self):
        import api

        # A captured file or a note has no provider id, and a link built from
        # nothing would open a Drive error page.
        assert api._source_url({"provider": "google_drive"}) is None
        assert api._source_url({"provider": "google_drive", "sourceRef": ""}) is None
        assert api._source_url({}) is None

    def test_the_phone_vault_has_nowhere_to_link_to(self):
        """Its files are opened on the device, not at a provider."""
        import api
        import device_vault

        assert api._source_url({"provider": device_vault.PROVIDER, "sourceRef": "x"}) is None

    def test_the_link_is_declared_on_the_profile_not_branched_on(self):
        """§9: a per-provider difference is data, not an `if` at the call site.

        Adding a provider that can be linked to should be a field on its
        profile — if this ever has to grow a second branch, the abstraction
        has stopped paying for itself.
        """
        from connectors import PROFILES

        assert PROFILES["google_drive"].file_url("1AbC") == (
            "https://drive.google.com/open?id=1AbC"
        )
        assert PROFILES["google_drive"].file_url(None) is None


class TestReconnect:
    """Reconnecting restores the index — the promise `disconnect` makes."""

    def test_a_memory_inside_the_plan_window_comes_back(self):
        import connector_api

        now = datetime(2026, 9, 21, tzinfo=UTC)
        assert connector_api.still_in_window({}, now) is True
        assert (
            connector_api.still_in_window(
                {"recallExpiresAt": datetime(2026, 12, 1, tzinfo=UTC)}, now
            )
            is True
        )

    def test_a_memory_the_plan_has_aged_out_stays_dormant(self):
        """Otherwise a free account buys back a year of history.

        Disconnect and reconnect are two taps, and reviving on
        `sourceAvailable` alone would make them a retention upgrade.
        """
        import connector_api

        now = datetime(2026, 9, 21, tzinfo=UTC)
        assert (
            connector_api.still_in_window(
                {"recallExpiresAt": datetime(2026, 8, 1, tzinfo=UTC)}, now
            )
            is False
        )


# ---------------------------------------------------------------------------
# The whole function, over a fake Firestore
# ---------------------------------------------------------------------------


class _FakeDoc:
    def __init__(self, id: str, data: dict):
        self.id = id
        self._data = data

    def to_dict(self) -> dict:
        return self._data


class _FakeQuery:
    """Just enough of a Firestore query for `search` to run against."""

    def __init__(self, docs: list, calls: list):
        self._docs = docs
        self._calls = calls

    def where(self, field, op, value):
        self._calls.append(("where", field, op, value))
        return self

    def find_nearest(self, **kwargs):
        self._calls.append(("find_nearest", kwargs["limit"], kwargs["distance_result_field"]))
        return self

    def get(self) -> list:
        return list(self._docs)


class _FakeDb:
    def __init__(self, docs: list):
        self.calls: list = []
        self._docs = docs

    def collection(self, name: str) -> _FakeQuery:
        self.calls.append(("collection", name))
        return _FakeQuery(self._docs, self.calls)


def _docs(*rows: tuple[str, str, str, float]) -> list[_FakeDoc]:
    return [
        _FakeDoc(
            id,
            {
                "text": text,
                "memoryId": f"m-{id}",
                "chunkIndex": 0,
                "memoryType": kind,
                "_distance": distance,
            },
        )
        for id, text, kind, distance in rows
    ]


class TestSearch:
    """`search` end to end — the one function `api.py` actually calls.

    Here because a scripted edit once deleted `search` outright and this suite
    stayed green: every test exercised a stage, none the whole. The deploy
    went out and every `ask` failed.
    """

    @pytest.fixture(autouse=True)
    def _embed(self, monkeypatch):
        async def fake(text: str) -> list[float]:
            return [0.0, 0.0, 1.0]

        monkeypatch.setattr(retrieval.gemini, "embed_query", fake)

    def test_it_scopes_to_the_users_active_chunks_and_fuses_both_stages(self):
        db = _FakeDb(
            _docs(
                ("v1", "general notes about billing", "pdf", 0.10),
                ("v2", "a meeting about pricing", "pdf", 0.12),
                ("v3", "invoice for SKU-4471 attached", "pdf", 0.30),
            )
        )
        marks: dict[str, float] = {}

        found = asyncio.run(retrieval.search(db, "u1", "SKU-4471 invoice", marks=marks))

        assert ("collection", "chunks") in db.calls
        assert ("where", "userId", "==", "u1") in db.calls
        assert ("where", "recallState", "==", "active") in db.calls
        assert ("find_nearest", retrieval.CANDIDATES, "_distance") in db.calls
        # Nearest by vector was v1; the keyword stage rescued the exact match.
        assert found[0].chunk_id == "v3"
        assert found[0].lexical_rank == 1
        assert found[0].vector_rank == 3
        assert found[0].memory_id == "m-v3"
        assert {"embed", "knn", "rank"} <= set(marks)

    def test_one_type_narrows_the_query_and_two_types_filter_afterwards(self):
        one = Query(search="lease", memory_types=("pdf",))
        db = _FakeDb(_docs(("a", "lease terms", "pdf", 0.1)))
        asyncio.run(retrieval.search(db, "u1", "lease", parsed=one))
        assert ("where", "memoryType", "==", "pdf") in db.calls

        two = Query(search="lease", memory_types=("photo", "screenshot"))
        db = _FakeDb(
            _docs(("a", "lease terms", "pdf", 0.1), ("b", "the lease, photographed", "photo", 0.2))
        )
        found = asyncio.run(retrieval.search(db, "u1", "lease", parsed=two))
        # Firestore cannot `in`-filter beside a vector search, so two types
        # are not sent as a filter — the wrong type is dropped afterwards.
        assert not any(c[0] == "where" and c[1] == "memoryType" for c in db.calls)
        assert [p.chunk_id for p in found] == ["b"]

    def test_nothing_left_after_the_filters_is_an_empty_list_not_an_error(self):
        parsed = Query(search="lease", memory_types=("photo", "screenshot"))
        db = _FakeDb(_docs(("a", "lease terms", "pdf", 0.1)))
        marks: dict[str, float] = {}

        found = asyncio.run(retrieval.search(db, "u1", "lease", parsed=parsed, marks=marks))

        assert found == []
        assert "rank" in marks
