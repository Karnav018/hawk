"""Offers and news by email (`marketing`)."""

from urllib.parse import parse_qs, urlparse

import pytest

import marketing as m

SECRET = "test-secret"


class TestUnsubscribeLinks:
    def test_a_token_verifies_for_its_own_account_only(self):
        token = m.unsubscribe_token("u", "uid-1", secret=SECRET)
        assert m.valid_token("u", "uid-1", token, secret=SECRET)
        assert not m.valid_token("u", "uid-2", token, secret=SECRET)

    def test_user_and_address_tokens_cannot_stand_in_for_each_other(self):
        token = m.unsubscribe_token("u", "someone@gmail.com", secret=SECRET)
        assert not m.valid_token("e", "someone@gmail.com", token, secret=SECRET)

    def test_a_different_secret_or_a_blank_is_refused(self):
        token = m.unsubscribe_token("e", "a@gmail.com", secret=SECRET)
        assert not m.valid_token("e", "a@gmail.com", token, secret="other")
        assert not m.valid_token("e", "a@gmail.com", "", secret=SECRET)
        assert not m.valid_token("x", "a@gmail.com", token, secret=SECRET)

    def test_addresses_ignore_case(self):
        token = m.unsubscribe_token("e", "A@Gmail.com", secret=SECRET)
        assert m.valid_token("e", "a@gmail.com", token, secret=SECRET)

    def test_the_link_carries_a_valid_token(self):
        link = m.unsubscribe_link("e", "a@gmail.com", secret=SECRET)
        assert link.startswith(m.UNSUBSCRIBE_URL + "?")
        query = {k: v[0] for k, v in parse_qs(urlparse(link).query).items()}
        assert query["i"] == "a@gmail.com"
        assert m.valid_token(query["k"], query["i"], query["t"], secret=SECRET)


class TestRender:
    def test_blank_lines_make_paragraphs(self):
        assert m.paragraphs("One\nline.\n\nTwo.\n\n\n") == ["One line.", "Two."]

    def test_both_versions_carry_the_unsubscribe_link(self):
        text, page = m.render("Hi", "Hello there.", "https://example.test/u?x=1")
        assert "Hello there." in text
        assert "Unsubscribe: https://example.test/u?x=1" in text
        assert "https://example.test/u?x=1" in page

    def test_the_body_cannot_inject_markup(self):
        _, page = m.render("Hi", "<script>alert(1)</script>", "https://example.test/u")
        assert "<script>" not in page
        assert "&lt;script&gt;" in page

    def test_testers_are_told_why_they_got_it(self):
        text, page = m.render("Hi", "Yo.", "https://x.test/u", reason=m.REASONS["test"])
        assert "one of Hawk's testers" in text
        assert "you use Hawk" not in text
        assert "testers" in page

    def test_users_are_told_how_to_turn_it_off(self):
        text, _ = m.render("Hi", "Yo.", "https://x.test/u")
        assert "Privacy and data" in text
        assert "turned on" not in text, "offers are on by default; nobody turned them on"


class TestBodyFromTheConsole:
    def test_an_array_is_one_paragraph_each(self):
        body = m.body_text(["Hi,", "  Thank you.  ", "", "Karnav"])
        assert m.paragraphs(body) == ["Hi,", "Thank you.", "Karnav"]

    def test_a_typed_newline_breaks_the_line(self):
        assert m.paragraphs(m.body_text("Hi,\\n\\nThank you.")) == ["Hi,", "Thank you."]

    def test_nothing_is_empty(self):
        assert m.body_text(None) == ""
        assert m.body_text([]) == ""


class TestRecipients:
    def test_a_test_send_goes_only_to_its_list(self):
        users = [("u1", {"email": "user@gmail.com", "marketingOptIn": True})]
        out = m.plan_recipients("test", ["Me@Gmail.com", "me@gmail.com", "bad"], users, set())
        assert [r.email for r in out] == ["me@gmail.com"]
        assert out[0].uid is None

    def test_a_test_list_is_capped(self):
        many = [f"t{i}@gmail.com" for i in range(m.TEST_LIMIT + 10)]
        assert len(m.plan_recipients("test", many, [], set())) == m.TEST_LIMIT

    def test_every_user_unless_they_turned_it_off(self):
        # On by default: no recorded choice means subscribed.
        users = [
            ("u1", {"email": "yes@gmail.com", "marketingOptIn": True}),
            ("u2", {"email": "no@gmail.com", "marketingOptIn": False}),
            ("u3", {"email": "unset@gmail.com"}),
            ("u4", {"marketingOptIn": True}),
            ("u5", {"email": "paused@gmail.com", "status": "deactivated"}),
        ]
        out = m.plan_recipients("users", None, users, set())
        assert [(r.key, r.email) for r in out] == [
            ("u1", "yes@gmail.com"),
            ("u3", "unset@gmail.com"),
        ]

    def test_an_address_that_unsubscribed_is_skipped(self):
        users = [("u1", {"email": "gone@gmail.com"})]
        assert m.plan_recipients("users", None, users, {"gone@gmail.com"}) == []
        assert m.plan_recipients("test", ["gone@gmail.com"], [], {"gone@gmail.com"}) == []

    def test_an_unknown_audience_reaches_nobody(self):
        users = [("u1", {"email": "yes@gmail.com"})]
        assert m.plan_recipients("friends", ["a@gmail.com"], users, set()) == []

    def test_subscribed_by_default(self):
        assert m.subscribed({})
        assert m.subscribed({"marketingOptIn": True})
        assert not m.subscribed({"marketingOptIn": False})
        assert not m.subscribed({"status": "deactivated"})


def _people(n):
    return [m.Recipient(key=f"k{i}", email=f"p{i}@gmail.com") for i in range(n)]


class TestRun:
    def test_nobody_is_sent_to_twice(self):
        sent = []
        outcome = m.run(_people(3), {"k1"}, room=10, deliver=lambda r: sent.append(r.key))
        assert sent == ["k0", "k2"]
        assert outcome.skipped == 1

    def test_it_stops_at_the_daily_room(self):
        sent = []
        outcome = m.run(_people(5), set(), room=2, deliver=lambda r: sent.append(r.key))
        assert sent == ["k0", "k1"]
        assert outcome.stopped_at_cap

    def test_one_failure_does_not_stop_the_rest(self):
        def deliver(recipient):
            if recipient.key == "k1":
                raise OSError("mailbox full")

        outcome = m.run(_people(3), set(), room=10, deliver=deliver)
        assert outcome.sent == ["k0", "k2"]
        assert outcome.failed == 1
        assert not outcome.stopped_at_cap


class TestSendCampaignChecks:
    def test_a_missing_subject_or_body_is_an_error(self):
        result = m.send_campaign(None, "c1", {"body": "Hi", "audience": "test"}, None)
        assert result["status"] == "error"
        result = m.send_campaign(None, "c1", {"subject": "Hi", "audience": "test"}, None)
        assert result["status"] == "error"

    def test_an_unknown_audience_is_an_error(self):
        result = m.send_campaign(
            None, "c1", {"subject": "Hi", "body": "Yo", "audience": "friends"}, None
        )
        assert result["status"] == "error"
        assert '"users"' in result["note"]

    def test_an_unwritten_template_is_not_sent(self):
        data = {"subject": "Offer", "body": ["Hi,", m.WRITE_HERE, "Karnav"], "audience": "test"}
        result = m.send_campaign(None, "c1", data, None)
        assert result["status"] == "error"
        assert m.WRITE_HERE in result["note"]


class TestTemplate:
    def test_a_new_campaign_gets_every_field(self, monkeypatch):
        monkeypatch.setenv("CAMPAIGN_TEST_TO", "me@gmail.com, you@gmail.com")
        monkeypatch.setenv("CAMPAIGN_SIGNATURE", "Karnav")
        fields = m.template_fields({})
        assert fields["subject"] == ""
        assert fields["body"] == ["Hi,", m.WRITE_HERE, "Thank you,", "Karnav"]
        assert fields["audience"] == "test"
        assert fields["testTo"] == ["me@gmail.com", "you@gmail.com"]
        assert fields["status"] == "draft"
        assert "createdAt" in fields

    def test_what_was_typed_is_kept(self):
        fields = m.template_fields({"subject": "Diwali offer", "status": "draft"})
        assert "subject" not in fields
        assert "status" not in fields
        assert "body" in fields

    def test_a_blank_setting_falls_back(self, monkeypatch):
        monkeypatch.delenv("CAMPAIGN_TEST_TO", raising=False)
        monkeypatch.delenv("CAMPAIGN_SIGNATURE", raising=False)
        fields = m.template_fields({})
        assert fields["testTo"] == []
        assert fields["body"][-1] == "The Hawk team"


class TestDailyCap:
    def test_default_and_override(self, monkeypatch):
        monkeypatch.delenv("MARKETING_DAILY_CAP", raising=False)
        assert m.daily_cap() == 300
        monkeypatch.setenv("MARKETING_DAILY_CAP", "50")
        assert m.daily_cap() == 50

    @pytest.mark.parametrize("raw", ["lots", "-5"])
    def test_nonsense_is_safe(self, monkeypatch, raw):
        monkeypatch.setenv("MARKETING_DAILY_CAP", raw)
        assert 0 <= m.daily_cap() <= 300
