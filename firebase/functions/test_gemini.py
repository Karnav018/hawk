"""What extraction asks the model for, by file type."""

import asyncio

import httpx
import pytest

import gemini


class TestExtractionBrief:
    """A picture is described; everything else is transcribed."""

    def test_a_picture_is_described_and_its_words_transcribed(self):
        for mime in ("image/jpeg", "image/png", "image/heic", "image/webp"):
            system, prompt = gemini.extraction_brief(mime)
            assert prompt == "Describe this picture.", mime
            assert system.startswith("You describe pictures"), mime
            # The words in it still arrive verbatim, under a heading of their
            # own — a citation must never pass the description off as text
            # the picture contained.
            assert "Text in the picture:" in system
            assert "verbatim" in system

    def test_a_document_or_a_recording_is_transcribed_verbatim(self):
        for mime in ("application/pdf", "audio/mp4", "audio/mpeg"):
            system, prompt = gemini.extraction_brief(mime)
            assert prompt == "Transcribe this file.", mime
            assert system.startswith("You transcribe documents"), mime
            assert "Do NOT summarise" in system

    def test_the_file_name_travels_with_the_request(self):
        _, prompt = gemini.extraction_brief("image/jpeg", "IMG_0412.heic")
        assert prompt == "File name: IMG_0412.heic\n\nDescribe this picture."
        _, prompt = gemini.extraction_brief("application/pdf", "lease.pdf")
        assert prompt == "File name: lease.pdf\n\nTranscribe this file."

    def test_both_briefs_keep_the_no_content_sentinel(self):
        # `extract_file` turns exactly this word into "nothing readable";
        # a brief that dropped it would make blank files look like text.
        for mime in ("image/jpeg", "application/pdf"):
            system, _ = gemini.extraction_brief(mime)
            assert "return exactly: NO_CONTENT" in system


def _ok(text: str) -> httpx.Response:
    return httpx.Response(200, json={"candidates": [{"content": {"parts": [{"text": text}]}}]})


class TestRetries:
    """A rate-limited call waits and tries again, on a schedule the caller sets."""

    def _wire(self, monkeypatch, responses: list[httpx.Response]):
        calls: list[str] = []
        waits: list[float] = []

        class _Client:
            def post(self, url, **kwargs):
                calls.append(url)
                return responses.pop(0)

        async def fake_sleep(seconds: float) -> None:
            waits.append(seconds)

        monkeypatch.setattr(gemini, "_client", _Client)
        monkeypatch.setattr(gemini, "_key", lambda: "k")
        monkeypatch.setattr(gemini.asyncio, "sleep", fake_sleep)
        return calls, waits

    def test_it_retries_on_the_schedule_until_the_call_succeeds(self, monkeypatch):
        calls, waits = self._wire(
            monkeypatch, [httpx.Response(429), httpx.Response(503), _ok("read")]
        )
        response = asyncio.run(
            gemini._post(
                "https://x/y", json={}, timeout=gemini.CHAT_TIMEOUT, retries=(2.0, 5.0, 12.0)
            )
        )
        assert response.status_code == 200
        assert waits == [2.0, 5.0]
        assert len(calls) == 3

    def test_when_the_schedule_runs_out_the_last_answer_comes_back(self, monkeypatch):
        calls, waits = self._wire(monkeypatch, [httpx.Response(429)] * 3)
        response = asyncio.run(
            gemini._post("https://x/y", json={}, timeout=gemini.CHAT_TIMEOUT, retries=(1.0, 2.0))
        )
        assert response.status_code == 429
        assert waits == [1.0, 2.0]
        assert len(calls) == 3

    def test_no_schedule_means_no_retry(self, monkeypatch):
        calls, waits = self._wire(monkeypatch, [httpx.Response(429), _ok("never")])
        response = asyncio.run(gemini._post("https://x/y", json={}, timeout=gemini.CHAT_TIMEOUT))
        assert response.status_code == 429
        assert waits == [] and len(calls) == 1

    def test_retry_after_is_honoured_within_a_minute(self):
        assert gemini._retry_after(httpx.Response(429, headers={"retry-after": "7"}), 2.0) == 7.0
        assert gemini._retry_after(httpx.Response(429, headers={"retry-after": "900"}), 2.0) == 60.0
        assert gemini._retry_after(httpx.Response(429, headers={"retry-after": "soon"}), 2.0) == 2.0
        assert gemini._retry_after(httpx.Response(429), 2.0) == 2.0


class TestLadder:
    """A refused or exhausted model steps down; nothing is lost on a bad id."""

    @pytest.fixture(autouse=True)
    def _fresh(self, monkeypatch):
        gemini._refused.clear()
        monkeypatch.setattr(gemini, "EXTRACT_LADDER", ("flagship", "lite", "old"))
        monkeypatch.setattr(gemini, "CHAT_LADDER", ("lite", "old"))
        yield
        gemini._refused.clear()

    @staticmethod
    def _post_by_model(answers: dict[str, list[httpx.Response]], seen: list):
        async def fake_post(url, *, json, timeout, retries=()):
            model = url.split("/models/")[1].split(":")[0]
            seen.append((model, retries))
            return answers[model].pop(0)

        return fake_post

    def test_a_refused_id_is_skipped_and_remembered(self, monkeypatch):
        seen: list = []
        answers = {
            "flagship": [httpx.Response(404)],
            "lite": [_ok("What the picture shows: a garden."), _ok("second")],
        }
        monkeypatch.setattr(gemini, "_post", self._post_by_model(answers, seen))

        text, model = asyncio.run(gemini.extract_file(b"img", "image/jpeg"))
        assert (text.startswith("What the picture shows"), model) == (True, "lite")
        assert "flagship" in gemini._refused

        # The next call never asks the refused model again.
        text, model = asyncio.run(gemini.extract_file(b"img", "image/jpeg"))
        assert (text, model) == ("second", "lite")
        assert [m for m, _ in seen] == ["flagship", "lite", "lite"]

    def test_quota_steps_down_but_is_not_remembered(self, monkeypatch):
        seen: list = []
        answers = {"flagship": [httpx.Response(429)], "lite": [_ok("read")]}
        monkeypatch.setattr(gemini, "_post", self._post_by_model(answers, seen))

        text, model = asyncio.run(gemini.extract_file(b"pdf", "application/pdf"))
        assert (text, model) == ("read", "lite")
        assert "flagship" not in gemini._refused
        # The head gets the whole schedule; a later rung gets one retry.
        assert seen[0][1] == gemini.EXTRACT_RETRIES
        assert seen[1][1] == gemini.EXTRACT_RETRIES[:1]

    def test_a_healthy_head_reads_it_itself(self, monkeypatch):
        seen: list = []
        answers = {"flagship": [_ok("the lease terms")]}
        monkeypatch.setattr(gemini, "_post", self._post_by_model(answers, seen))
        assert asyncio.run(gemini.extract_file(b"pdf", "application/pdf")) == (
            "the lease terms",
            "flagship",
        )
        assert len(seen) == 1

    def test_every_rung_out_of_quota_is_a_retryable_error(self, monkeypatch):
        answers = {m: [httpx.Response(429)] for m in ("flagship", "lite", "old")}
        monkeypatch.setattr(gemini, "_post", self._post_by_model(answers, []))
        with pytest.raises(gemini.ModelError) as caught:
            asyncio.run(gemini.extract_file(b"pdf", "application/pdf"))
        assert caught.value.retryable

    def test_every_rung_refused_is_a_plain_error(self, monkeypatch):
        answers = {m: [httpx.Response(404)] for m in ("flagship", "lite", "old")}
        monkeypatch.setattr(gemini, "_post", self._post_by_model(answers, []))
        with pytest.raises(gemini.ModelError) as caught:
            asyncio.run(gemini.extract_file(b"pdf", "application/pdf"))
        assert not caught.value.retryable
        assert gemini._refused == {"flagship", "lite", "old"}

    def test_answering_walks_its_own_ladder(self, monkeypatch):
        seen: list = []
        answers = {"lite": [httpx.Response(404)], "old": [_ok('{"answer": "x"}')]}
        monkeypatch.setattr(gemini, "_post", self._post_by_model(answers, seen))
        assert asyncio.run(gemini.generate("sys", "q")) == '{"answer": "x"}'
        assert [m for m, _ in seen] == ["lite", "old"]

    def test_the_free_tier_reads_with_the_economy_ladder(self, monkeypatch):
        monkeypatch.setattr(gemini, "EXTRACT_ECONOMY_LADDER", ("cheap", "old"))
        seen: list = []
        answers = {"cheap": [_ok("What the picture shows: a garden.")]}
        monkeypatch.setattr(gemini, "_post", self._post_by_model(answers, seen))
        text, model = asyncio.run(gemini.extract_file(b"img", "image/jpeg", economy=True))
        assert model == "cheap"
        assert [m for m, _ in seen] == ["cheap"]

    def test_the_economy_ladder_starts_on_3_1_lite_and_falls_back_up(self):
        assert gemini.EXTRACT_ECONOMY_LADDER[0] == gemini.EXTRACT_ECONOMY_MODEL
        assert gemini.EXTRACT_ECONOMY_MODEL == "gemini-3.1-flash-lite"
        assert len(gemini.EXTRACT_ECONOMY_LADDER) > 1

    def test_the_ladder_keeps_order_and_dedupes(self):
        net = ("x", "y")
        assert gemini._ladder("a", "b", "a", net=net) == ("a", "b", "x", "y")
        assert gemini._ladder("y", net=net) == ("y", "x")
        # Reading falls to the fuller model first; answering to the faster.
        assert gemini._READ_SAFETY_NET[0] == "gemini-3.6-flash"
        assert gemini._ANSWER_SAFETY_NET[0] == "gemini-3.5-flash-lite"
