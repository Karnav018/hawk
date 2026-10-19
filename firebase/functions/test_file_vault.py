"""Keeping the user's files, inside the plan's allowance.

The quota is the whole reason keeping files is affordable, so these pin the
arithmetic rather than the plumbing: what fits, what does not, and that
releasing bytes can never hand back more than was taken.
"""

import billing
import file_vault


class TestQuota:
    def test_a_tier_with_room_accepts_the_file(self, monkeypatch):
        monkeypatch.setattr(file_vault, "used", lambda uid: 0)
        free = billing.ENTITLEMENTS[billing.FREE]
        assert file_vault.fits("u", free, 10 * 1024 * 1024) is True

    def test_a_file_that_would_cross_the_ceiling_is_refused(self, monkeypatch):
        free = billing.ENTITLEMENTS[billing.FREE]
        # One byte short of the limit, then asked for two.
        monkeypatch.setattr(file_vault, "used", lambda uid: (free.file_bytes or 0) - 1)
        assert file_vault.fits("u", free, 2) is False

    def test_exactly_filling_the_ceiling_is_allowed(self, monkeypatch):
        free = billing.ENTITLEMENTS[billing.FREE]
        monkeypatch.setattr(file_vault, "used", lambda uid: 0)
        assert file_vault.fits("u", free, free.file_bytes or 0) is True

    def test_an_unlimited_tier_always_fits(self, monkeypatch):
        monkeypatch.setattr(file_vault, "used", lambda uid: 10**15)
        unlimited = billing.Entitlements("custom", None, None, None, None, None, None, None)
        assert file_vault.fits("u", unlimited, 10**12) is True

    def test_a_tier_with_no_file_storage_keeps_nothing(self, monkeypatch):
        monkeypatch.setattr(file_vault, "used", lambda uid: 0)
        none = billing.Entitlements("none", 30, 0, 1, 1, 2, 20, 0)
        assert file_vault.fits("u", none, 1) is False

    def test_every_shipped_tier_can_keep_something(self):
        # A vault that cannot hand back a single file it was given is hard to
        # trust, so no tier is allowed to have nothing.
        for tier, plan in billing.ENTITLEMENTS.items():
            assert plan.file_bytes is None or plan.file_bytes > 0, tier

    def test_paid_tiers_keep_more_than_free(self):
        free = billing.ENTITLEMENTS[billing.FREE].file_bytes or 0
        for tier in (billing.STANDARD, billing.PREMIUM):
            allowed = billing.ENTITLEMENTS[tier].file_bytes
            assert allowed is None or allowed > free, tier


class TestAllowance:
    def test_reports_what_is_left(self, monkeypatch):
        monkeypatch.setattr(file_vault, "used", lambda uid: 400)
        plan = billing.Entitlements("t", None, None, None, None, None, None, 1000)
        assert file_vault.allowance("u", plan) == {
            "usedBytes": 400,
            "limitBytes": 1000,
            "remainingBytes": 600,
        }

    def test_over_the_ceiling_reports_zero_left_not_a_negative(self, monkeypatch):
        # A negative remaining renders as "-3 GB left" on the profile.
        monkeypatch.setattr(file_vault, "used", lambda uid: 1500)
        plan = billing.Entitlements("t", None, None, None, None, None, None, 1000)
        assert file_vault.allowance("u", plan)["remainingBytes"] == 0

    def test_unlimited_has_no_remaining_figure(self, monkeypatch):
        monkeypatch.setattr(file_vault, "used", lambda uid: 5)
        plan = billing.Entitlements("t", None, None, None, None, None, None, None)
        assert file_vault.allowance("u", plan)["remainingBytes"] is None


class TestObjectPaths:
    def test_scoped_by_user_then_memory(self):
        path = file_vault.object_path("u1", "m1", "Pricing v4.pdf")
        # `storage.rules` matches on the `users/{uid}/originals/` prefix, and
        # `delete_account` purges by it.
        assert path == "users/u1/originals/m1/Pricing v4.pdf"

    def test_a_filename_cannot_leave_the_prefix(self):
        path = file_vault.object_path("u1", "m1", "../../other/evil.pdf")
        assert path.startswith("users/u1/originals/m1/")
        assert ".." not in path

    def test_an_empty_name_still_produces_an_object(self):
        assert file_vault.object_path("u1", "m1", "   ").endswith("/original")
