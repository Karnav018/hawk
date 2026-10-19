"""Test accounts added from the Firebase console (`firestore_test_accounts`)."""

import pytest

import billing
import firestore_test_accounts as listed_accounts


@pytest.fixture(autouse=True)
def fresh(monkeypatch):
    """No cache, no deployment, no env list, unless a test sets them."""
    monkeypatch.setattr(listed_accounts, "_state", {"at": None, "ids": frozenset()})
    for name in ("K_SERVICE", "FUNCTIONS_EMULATOR", "TEST_ACCOUNTS"):
        monkeypatch.delenv(name, raising=False)


def _serve(monkeypatch, ids):
    """Pretend to be deployed, with `ids` in the collection. Returns a call log."""
    calls = []

    def fetch():
        calls.append(1)
        if isinstance(ids, Exception):
            raise ids
        return frozenset(ids)

    monkeypatch.setenv("K_SERVICE", "ask")
    monkeypatch.setattr(listed_accounts, "_fetch", fetch)
    return calls


class TestListed:
    def test_never_reads_the_database_off_a_server(self, monkeypatch):
        called = []
        monkeypatch.setattr(listed_accounts, "_fetch", lambda: called.append(1))
        assert listed_accounts.listed() == frozenset()
        assert called == [], "unit tests and scripts must not touch a real database"

    def test_the_emulator_counts_as_a_server(self, monkeypatch):
        _serve(monkeypatch, {"qa@hawk.test"})
        monkeypatch.delenv("K_SERVICE")
        monkeypatch.setenv("FUNCTIONS_EMULATOR", "true")
        assert listed_accounts.listed(now=0) == {"qa@hawk.test"}

    def test_reads_once_a_minute(self, monkeypatch):
        calls = _serve(monkeypatch, {"reviewer@gmail.com"})
        assert listed_accounts.listed(now=0) == {"reviewer@gmail.com"}
        assert listed_accounts.listed(now=59) == {"reviewer@gmail.com"}
        assert len(calls) == 1
        listed_accounts.listed(now=61)
        assert len(calls) == 2

    def test_a_failed_read_keeps_the_last_good_list(self, monkeypatch):
        _serve(monkeypatch, {"reviewer@gmail.com"})
        listed_accounts.listed(now=0)
        _serve(monkeypatch, RuntimeError("unavailable"))
        assert listed_accounts.listed(now=120) == {"reviewer@gmail.com"}

    def test_a_failed_first_read_means_nobody(self, monkeypatch, capsys):
        _serve(monkeypatch, RuntimeError("unavailable"))
        assert listed_accounts.listed(now=0) == frozenset()
        assert "test_accounts_read_failed" in capsys.readouterr().out


class TestBillingUsesTheConsoleList:
    def test_a_listed_email_gets_premium(self, monkeypatch):
        _serve(monkeypatch, {"reviewer@gmail.com"})
        resolved = billing.resolve_for_user("uid-1", None, email="Reviewer@Gmail.com")
        assert resolved.tier == billing.PREMIUM

    def test_a_listed_uid_gets_premium(self, monkeypatch):
        _serve(monkeypatch, {"uid-7"})
        assert billing.resolve_for_user("UID-7", None).tier == billing.PREMIUM

    def test_the_profile_badge_follows(self, monkeypatch):
        _serve(monkeypatch, {"reviewer@gmail.com"})
        assert billing.is_test_account("uid-1", email="reviewer@gmail.com")
        assert not billing.is_test_account("uid-2", email="someone@gmail.com")

    def test_both_lists_count(self, monkeypatch):
        _serve(monkeypatch, {"console@gmail.com"})
        monkeypatch.setenv("TEST_ACCOUNTS", "env@gmail.com")
        console = billing.resolve_for_user("a", None, email="console@gmail.com")
        from_env = billing.resolve_for_user("b", None, email="env@gmail.com")
        assert console.tier == from_env.tier == billing.PREMIUM

    def test_unlisted_accounts_are_unaffected(self, monkeypatch):
        _serve(monkeypatch, {"reviewer@gmail.com"})
        assert billing.resolve_for_user("c", None, email="someone@gmail.com").tier == billing.FREE
        assert billing.resolve_for_user("c", None, email="").tier == billing.FREE
