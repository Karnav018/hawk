"""Tests for reading the page behind a saved link.

Weighted towards the guards rather than the parsing: a regex that misses a
`<script>` costs a few junk tokens in an index, and a guard that misses
`169.254.169.254` hands out a service-account token. The parsing tests here
are the ones where being wrong is silent — a page indexed as its own
JavaScript looks like a working link until somebody searches for it.
"""

from __future__ import annotations

import asyncio

import pytest

import extraction
import link_archive as archive


class TestGuards:
    @pytest.mark.parametrize(
        "url",
        [
            # The one that matters: GCP's metadata server hands out tokens.
            "http://169.254.169.254/computeMetadata/v1/",
            "http://localhost:8080/admin",
            "http://127.0.0.1/",
            "http://[::1]/",
            "http://10.0.0.5/internal",
            "http://192.168.1.1/",
            "http://172.16.0.1/",
        ],
    )
    def test_private_addresses_are_refused(self, url):
        with pytest.raises(archive.Unreachable):
            archive.guard(url)

    @pytest.mark.parametrize(
        "url",
        ["file:///etc/passwd", "gopher://example.com/", "ftp://example.com/x", "data:text/html,x"],
    )
    def test_only_http_and_https_are_links(self, url):
        with pytest.raises(archive.Unreachable):
            archive.guard(url)

    def test_a_public_page_is_allowed(self):
        archive.guard("https://example.com/pricing")

    def test_a_url_with_no_host_is_refused(self):
        with pytest.raises(archive.Unreachable):
            archive.guard("https:///nowhere")

    def test_redirects_are_bounded(self):
        """A redirect loop must not hold a function instance."""
        assert archive.MAX_REDIRECTS <= 10

    def test_the_body_is_bounded(self):
        """A response that never ends must not fill the instance's memory."""
        assert archive.MAX_BYTES <= 8 * 1024 * 1024


class TestReadable:
    def test_the_page_title_is_kept(self):
        title, _ = archive.readable("<html><head><title> Q3 &amp; Q4 </title></head></html>")
        assert title == "Q3 & Q4"

    def test_scripts_and_styles_are_not_indexed(self):
        """The largest thing on a page is its JavaScript, and none of it is
        what the page says. Indexed, it dominates the chunks and the file is
        found by searching for `addEventListener`."""
        _, text = archive.readable(
            "<html><body><script>var secret = 'addEventListener'</script>"
            "<style>.a{color:red}</style><p>The price is ten pounds.</p></body></html>"
        )
        assert "The price is ten pounds." in text
        assert "addEventListener" not in text
        assert "color:red" not in text

    def test_a_page_with_no_title_still_reads(self):
        title, text = archive.readable("<p>Just words.</p>")
        assert title is None
        assert text == "Just words."

    def test_entities_and_whitespace_are_normalised(self):
        _, text = archive.readable("<p>a &mdash;   b</p>\n\n\n<p>c</p>")
        assert "—" in text
        assert "   " not in text


class TestFallback:
    """A link that cannot be read is still a link the user kept."""

    def _run(self, memory, monkeypatch, failure):
        async def _boom(url):
            raise failure

        monkeypatch.setattr(archive, "fetch", _boom)
        return asyncio.run(extraction.extract_link(memory))

    def test_an_unreachable_page_keeps_the_memory_indexed(self, monkeypatch):
        memory = {
            "type": "link",
            "title": "Pricing",
            "url": "https://example.com/pricing",
        }
        result = self._run(memory, monkeypatch, archive.Unreachable("paywall"))
        # Still indexed on what we do know, exactly as before this existed —
        # not demoted to `unsupported`, which would drop it out of search.
        assert result.ok
        assert "Pricing" in result.text
        assert "example.com" in result.text

    def test_a_blocked_page_fails_the_capture_with_the_way_out(self, monkeypatch):
        # A login or a paywall is a verdict about the page: the url alone is
        # not what the user meant to keep. The app shows this sentence as it
        # is (`Hawk Snackbars.dc.html`, capture_page · error).
        memory = {"type": "link", "title": "", "url": "https://example.com/x"}
        result = self._run(memory, monkeypatch, archive.Blocked(archive.BLOCKED_MESSAGE))
        assert not result.ok
        assert result.failure == "That page blocks readers. Save it as a PDF instead."

    def test_only_refusals_count_as_blocked(self):
        # A 404 or a 500 is the page being broken or gone — the link is kept
        # on its title and url, as before. Only "you may not read this" fails.
        assert {401, 403}.issubset(archive.BLOCKED_STATUSES)
        assert 404 not in archive.BLOCKED_STATUSES
        assert 500 not in archive.BLOCKED_STATUSES
        assert issubclass(archive.Blocked, archive.Unreachable)

    def test_an_unexpected_error_falls_back_too(self, monkeypatch):
        memory = {"type": "link", "title": "Pricing", "url": "https://example.com/x"}
        result = self._run(memory, monkeypatch, RuntimeError("bad certificate"))
        assert result.ok

    def test_the_page_text_is_indexed_when_it_reads(self, monkeypatch):
        async def _ok(url):
            return "Plans and pricing", "Standard is nine pounds a month."

        monkeypatch.setattr(archive, "fetch", _ok)
        result = asyncio.run(
            extraction.extract_link(
                {"type": "link", "title": "Pricing", "url": "https://example.com/x"}
            )
        )
        assert "nine pounds" in result.text
        assert "Plans and pricing" in result.text

    def test_a_link_with_no_url_is_not_fetched(self):
        result = asyncio.run(extraction.extract_link({"type": "link", "title": "Empty"}))
        assert result.text == "Empty"
