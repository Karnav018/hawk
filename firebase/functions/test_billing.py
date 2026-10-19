"""Plans, entitlements and retention — the logic ported from FastAPI.

Pure functions with no Firestore imports, so this runs without an emulator.
"""

from datetime import UTC, datetime, timedelta

import billing

NOW = datetime(2026, 8, 29, 12, 0, tzinfo=UTC)


class TestPlans:
    def test_the_stated_model_is_what_is_configured(self) -> None:
        free = billing.entitlements_for(billing.FREE)
        assert free.memory_window_days == 30
        assert free.connected_accounts == 1
        assert (free.window_queries, free.weekly_queries) == billing.FREE_ANSWERS

        standard = billing.entitlements_for(billing.STANDARD)
        assert standard.memory_window_days == 365
        assert standard.backup_window_days == 90
        assert (standard.window_queries, standard.weekly_queries) == billing.STANDARD_ANSWERS

        premium = billing.entitlements_for(billing.PREMIUM)
        assert premium.memory_window_days is None
        assert premium.connected_accounts is None

    def test_an_unknown_tier_degrades_to_free(self) -> None:
        # A typo in a stored tier must not grant unlimited anything.
        assert billing.entitlements_for("enterprise").tier == billing.FREE


class TestResolution:
    def test_no_subscription_is_free(self) -> None:
        assert billing.resolve(None).tier == billing.FREE

    def test_an_active_subscription_grants_its_tier(self) -> None:
        assert (
            billing.resolve({"tier": "premium", "status": "active"}, now=NOW).tier
            == billing.PREMIUM
        )

    def test_a_lapsed_period_falls_back_to_free(self) -> None:
        lapsed = {
            "tier": "premium",
            "status": "active",
            "currentPeriodEnd": NOW - timedelta(days=1),
        }
        assert billing.resolve(lapsed, now=NOW).tier == billing.FREE

    def test_a_failed_renewal_keeps_entitlements_during_grace(self) -> None:
        # A declined card must not read as data loss while the store retries.
        in_grace = {
            "tier": "premium",
            "status": "in_grace",
            "graceUntil": NOW + timedelta(days=5),
        }
        assert billing.resolve(in_grace, now=NOW).tier == billing.PREMIUM

    def test_grace_eventually_runs_out(self) -> None:
        expired = {
            "tier": "premium",
            "status": "in_grace",
            "graceUntil": NOW - timedelta(hours=1),
        }
        assert billing.resolve(expired, now=NOW).tier == billing.FREE

    def test_the_snapshot_beats_the_current_plan_table(self) -> None:
        """What someone already paid for must not be rewritten under them.

        Resolving live from the plan table would let a pricing change shrink an
        existing subscriber's memory window — which does not just reduce a
        limit, it destroys data.
        """
        held = {
            "tier": "standard",
            "status": "active",
            "memoryWindowDays": 3650,
            "backupWindowDays": 90,
            "indexBytes": 1,
            "connectedAccounts": 3,
            "dailyQueries": None,
        }
        assert billing.resolve(held, now=NOW).memory_window_days == 3650

    def test_a_malformed_subscription_never_raises(self) -> None:
        # A billing problem must not be able to take the app down.
        assert billing.resolve({}, now=NOW).tier == billing.FREE
        assert billing.resolve({"status": "cancelled"}, now=NOW).tier == billing.FREE


class TestRetention:
    def test_expiry_is_measured_from_capture(self) -> None:
        captured = NOW - timedelta(days=10)
        expiry = billing.recall_expiry(captured, billing.entitlements_for(billing.FREE))
        assert expiry == captured + timedelta(days=30)

    def test_upgrading_revives_what_you_already_have(self) -> None:
        """Measuring from capture is what makes an upgrade restore memories.

        From the subscription instead, paying would only help going forward —
        and what people pay to stop is losing what they already saved.
        """
        captured = NOW - timedelta(days=200)
        assert billing.recall_expiry(captured, billing.entitlements_for(billing.FREE)) < NOW
        assert billing.recall_expiry(captured, billing.entitlements_for(billing.STANDARD)) > NOW

    def test_unlimited_never_expires(self) -> None:
        assert billing.recall_expiry(NOW, billing.entitlements_for(billing.PREMIUM)) is None


class TestProducts:
    """A product id mismatch is the worst failure in billing: the purchase
    succeeds, the receipt validates, and the tier never changes — and the user
    has paid."""

    def test_every_product_maps_to_a_real_tier(self):
        import products

        for product in products.CATALOGUE.values():
            assert product.tier in billing.ENTITLEMENTS, product.product_id

    def test_the_key_matches_the_id(self):
        # Keyed by store product id, so a typo in the key would make the
        # product unfindable while looking correct in the list.
        import products

        for key, product in products.CATALOGUE.items():
            assert key == product.product_id

    def test_every_paid_tier_is_sold_monthly_and_only_monthly(self):
        import products

        for tier in (billing.STANDARD, billing.PREMIUM):
            months = {p.months for p in products.CATALOGUE.values() if p.tier == tier}
            assert months == {1}, tier

    def test_every_product_has_a_reference_price_for_the_paywall(self):
        # Shown until the store lists the product — the decided prices.
        import products

        prices = {p.product_id: p.reference_price for p in products.CATALOGUE.values()}
        assert prices == {"knowra.standard.monthly": "$4.99", "knowra.premium.monthly": "$9.99"}
        for p in products.CATALOGUE.values():
            assert p.reference_amount > 0 and p.currency == "USD", p.product_id

    def test_ids_avoid_encoding_a_price(self):
        """Store product ids are permanent and non-reusable, so a name has to
        survive a pricing change."""
        import products

        for pid in products.ids():
            assert not any(ch.isdigit() for ch in pid), pid

    def test_an_unknown_product_is_none_not_a_guess(self):
        import products

        assert products.product_for("knowra.free") is None


class TestSnapshot:
    """The snapshot is what stops a later pricing change shrinking an existing
    subscriber's memory window — which would destroy data they paid to keep."""

    def _verified(self, tier):
        from datetime import UTC, datetime, timedelta

        import subscriptions

        return subscriptions.Verified(
            tier=tier,
            product_id=f"knowra.{tier}.monthly",
            status="active",
            period_end=datetime.now(UTC) + timedelta(days=30),
            transaction_id="tx-1",
            store="google_play",
            auto_renewing=True,
        )

    def test_it_records_the_entitlements_not_just_the_tier(self):
        import subscriptions

        doc = subscriptions.snapshot(self._verified(billing.STANDARD))
        expected = billing.entitlements_for(billing.STANDARD)
        assert doc["memoryWindowDays"] == expected.memory_window_days
        assert doc["indexBytes"] == expected.index_bytes
        assert doc["windowQueries"] == expected.window_queries
        assert doc["weeklyQueries"] == expected.weekly_queries

    def test_resolve_reads_the_snapshot_back(self):
        import subscriptions

        doc = subscriptions.snapshot(self._verified(billing.PREMIUM))
        resolved = billing.resolve(doc)
        assert resolved.tier == billing.PREMIUM
        assert resolved.connected_accounts is None

    def test_a_stale_snapshot_survives_a_plan_table_change(self):
        """The whole point. A subscriber on an old, more generous plan keeps
        it until they change plans."""
        import subscriptions

        doc = subscriptions.snapshot(self._verified(billing.STANDARD))
        doc["memoryWindowDays"] = 9999
        assert billing.resolve(doc).memory_window_days == 9999

    def test_a_refunded_subscription_resolves_to_free(self):
        import subscriptions

        doc = subscriptions.snapshot(self._verified(billing.PREMIUM))
        doc["status"] = "refunded"
        assert billing.resolve(doc).tier == billing.FREE

    def test_an_expired_period_resolves_to_free(self):
        from datetime import UTC, datetime, timedelta

        import subscriptions

        doc = subscriptions.snapshot(self._verified(billing.PREMIUM))
        doc["currentPeriodEnd"] = datetime.now(UTC) - timedelta(days=1)
        assert billing.resolve(doc).tier == billing.FREE


class TestMissingCredentials:
    def test_apple_refuses_rather_than_trusting_the_client(self, monkeypatch):
        """A payments path that falls back to believing the app when its
        credentials are missing is worse than one that is switched off — the
        receipt it would believe is the one an attacker supplies."""
        import subscriptions

        for var in ("APPLE_KEY_P8", "APPLE_KEY_ID", "APPLE_ISSUER_ID"):
            monkeypatch.delenv(var, raising=False)

        try:
            subscriptions._apple_jwt()
        except subscriptions.NotConfigured:
            return
        raise AssertionError("expected NotConfigured")

    def test_not_configured_is_a_store_error(self):
        # So every caller's `except StoreError` covers it and it can never
        # escape as an unhandled crash on a payment path.
        import subscriptions

        assert issubclass(subscriptions.NotConfigured, subscriptions.StoreError)


class TestTestAccounts:
    """Granting the top tier without a purchase. The override is read from the
    environment, not hardcoded, and logged every time it applies."""

    def test_off_by_default(self, monkeypatch):
        monkeypatch.delenv("TEST_ACCOUNTS", raising=False)
        resolved = billing.resolve_for_user("u1", None)
        assert resolved.tier == billing.FREE

    def test_matches_by_uid(self, monkeypatch):
        monkeypatch.setenv("TEST_ACCOUNTS", "uid-abc")
        assert billing.resolve_for_user("uid-abc", None).tier == billing.PREMIUM

    def test_matches_by_email(self, monkeypatch):
        # A uid survives an email change; an email survives the account being
        # recreated. Both are accepted so either identifier works.
        monkeypatch.setenv("TEST_ACCOUNTS", "qa@example.test")
        resolved = billing.resolve_for_user("some-other-uid", None, email="QA@Example.Test")
        assert resolved.tier == billing.PREMIUM

    def test_does_not_match_a_different_account(self, monkeypatch):
        monkeypatch.setenv("TEST_ACCOUNTS", "qa@example.test")
        assert billing.resolve_for_user("u2", None, email="someone@else.test").tier == billing.FREE

    def test_an_empty_identity_never_matches(self, monkeypatch):
        """A blank email must not match a blank list entry.

        Trailing commas in config are normal, and an empty string matching an
        empty string would hand Premium to every signed-in user.
        """
        monkeypatch.setenv("TEST_ACCOUNTS", "qa@example.test,,")
        assert billing.resolve_for_user("u3", None, email="").tier == billing.FREE
        assert billing.resolve_for_user("u3", None, email=None).tier == billing.FREE

    def test_it_is_logged(self, capsys, monkeypatch):
        monkeypatch.setenv("TEST_ACCOUNTS", "uid-abc")
        billing.resolve_for_user("uid-abc", None)
        assert "test_account_entitlement" in capsys.readouterr().out

    def test_a_real_subscription_is_unaffected(self, monkeypatch):
        monkeypatch.setenv("TEST_ACCOUNTS", "uid-abc")
        resolved = billing.resolve_for_user(
            "someone-else", {"tier": billing.STANDARD, "status": "active"}
        )
        assert resolved.tier == billing.STANDARD


class TestReceipts:
    """Screen 2J's receipts, read from the stores' authenticated answers.

    The catalogue holds no prices on purpose, and a price sent by the client
    would be the client describing its own purchase. So every receipt comes
    from what the store's own API said, and a missing amount stays missing.
    """

    def test_apple_reads_the_charge(self):
        import subscriptions

        r = subscriptions.apple_receipt(
            {
                "transactionId": "2000000700",
                "purchaseDate": 1_758_499_200_000,  # 22 Sep 2025 UTC
                "price": 96000,  # milliunits
                "currency": "USD",
            }
        )
        assert r is not None
        assert r.receipt_id == "2000000700"
        assert r.amount_micros == 96_000_000
        assert r.currency == "USD"
        assert r.trial is False
        assert r.charged_at.year == 2025 and r.charged_at.month == 9

    def test_apple_free_trial_charges_nothing(self):
        import subscriptions

        r = subscriptions.apple_receipt(
            {
                "transactionId": "t1",
                "purchaseDate": 1_758_499_200_000,
                "price": 96000,
                "currency": "USD",
                "offerDiscountType": "FREE_TRIAL",
            }
        )
        assert r.trial is True
        assert r.amount_micros == 0

    def test_apple_without_a_price_says_so(self):
        import subscriptions

        r = subscriptions.apple_receipt({"transactionId": "t1"})
        # None, not zero: a missing price is unknown, not free.
        assert r.amount_micros is None

    def test_apple_without_an_id_is_not_a_receipt(self):
        import subscriptions

        assert subscriptions.apple_receipt({"price": 96000}) is None

    def test_google_reads_the_recurring_price(self):
        from datetime import UTC, datetime

        import subscriptions

        r = subscriptions.google_receipt(
            {
                "latestOrderId": "GPA.3350-1111-2222-33334..1",
                "lineItems": [
                    {
                        "autoRenewingPlan": {
                            "recurringPrice": {
                                "currencyCode": "USD",
                                "units": "96",
                                "nanos": 490000000,
                            }
                        }
                    }
                ],
            },
            datetime(2026, 9, 29, tzinfo=UTC),
            12,
        )
        assert r.receipt_id.endswith("..1")
        assert r.amount_micros == 96_490_000
        assert r.currency == "USD"
        # Dated at the start of the period it paid for, one calendar year
        # before the period ends — not 360 days before.
        assert r.charged_at == datetime(2025, 9, 29, tzinfo=UTC)

    def test_google_free_trial_phase_charges_nothing(self):
        from datetime import UTC, datetime

        import subscriptions

        r = subscriptions.google_receipt(
            {
                "latestOrderId": "GPA.1..0",
                "lineItems": [
                    {
                        "offerPhase": {"freeTrial": {}},
                        "autoRenewingPlan": {
                            "recurringPrice": {"currencyCode": "USD", "units": "96"}
                        },
                    }
                ],
            },
            datetime(2026, 9, 29, tzinfo=UTC),
            12,
        )
        assert r.trial is True
        assert r.amount_micros == 0

    def test_google_older_api_without_a_price(self):
        from datetime import UTC, datetime

        import subscriptions

        r = subscriptions.google_receipt(
            {"latestOrderId": "GPA.1..0", "lineItems": [{}]},
            datetime(2026, 9, 29, tzinfo=UTC),
            1,
        )
        assert r.amount_micros is None
        assert r.currency is None


class TestMonthsBefore:
    def test_whole_months(self):
        from datetime import UTC, datetime

        import subscriptions

        assert subscriptions.months_before(datetime(2026, 9, 29, tzinfo=UTC), 1) == datetime(
            2026, 8, 29, tzinfo=UTC
        )

    def test_across_the_year(self):
        from datetime import UTC, datetime

        import subscriptions

        assert subscriptions.months_before(datetime(2026, 1, 15, tzinfo=UTC), 1) == datetime(
            2025, 12, 15, tzinfo=UTC
        )

    def test_clamps_to_a_real_day(self):
        from datetime import UTC, datetime

        import subscriptions

        # 31 March minus a month is 28 February, not 3 March.
        assert subscriptions.months_before(datetime(2026, 3, 31, tzinfo=UTC), 1) == datetime(
            2026, 2, 28, tzinfo=UTC
        )

    def test_a_year_is_a_calendar_year(self):
        from datetime import UTC, datetime

        import subscriptions

        assert subscriptions.months_before(datetime(2026, 9, 29, tzinfo=UTC), 12) == datetime(
            2025, 9, 29, tzinfo=UTC
        )


class TestPlanSummaries:
    """What screen 1S prints comes from the table the backend enforces."""

    def test_every_tier_is_described(self):
        import billing

        s = billing.plan_summaries()
        assert set(s) == set(billing.ENTITLEMENTS)

    def test_the_numbers_are_the_enforced_ones(self):
        import billing

        free = billing.plan_summaries()[billing.FREE]
        e = billing.ENTITLEMENTS[billing.FREE]
        assert free["memoryWindowDays"] == e.memory_window_days
        assert free["indexBytes"] == e.index_bytes
        assert free["windowQueries"] == e.window_queries
        assert free["weeklyQueries"] == e.weekly_queries
        assert free["windowHours"] == billing.ANSWER_WINDOW_HOURS

    def test_forever_is_sent_as_none(self):
        import billing

        premium = billing.plan_summaries()[billing.PREMIUM]
        assert premium["memoryWindowDays"] is None


class TestFileAllowance:
    """Kept-file bytes — the axis every snapshot used to lack."""

    def test_a_snapshot_without_file_bytes_takes_the_tiers_allowance(self):
        # Every snapshot written before kept files existed looks like this,
        # including the Free one seeded at sign-up. It resolved to 0 bytes,
        # so `file_vault.fits` said no to every upload: "your plan's 0 GB of
        # file storage is full".
        held = {"tier": "standard", "status": "active", "memoryWindowDays": 365}
        standard = billing.entitlements_for(billing.STANDARD).file_bytes
        assert billing.resolve(held, now=NOW).file_bytes == standard
        free = {"tier": "free", "status": "active", "memoryWindowDays": 30}
        assert billing.resolve(free, now=NOW).file_bytes == 512 * 1024**2

    def test_a_snapshot_from_the_daily_era_takes_the_new_answer_limits(self):
        # Written before the window-and-week model: it has `dailyQueries` and
        # neither new axis. It must not resolve to "no ceiling".
        old = {"tier": "standard", "status": "active", "memoryWindowDays": 365, "dailyQueries": 200}
        resolved = billing.resolve(old, now=NOW)
        assert (resolved.window_queries, resolved.weekly_queries) == billing.STANDARD_ANSWERS

    def test_only_free_reads_with_the_cheaper_model(self):
        assert billing.reads_economy(billing.FREE)
        assert not billing.reads_economy(billing.STANDARD)
        assert not billing.reads_economy(billing.PREMIUM)

    def test_the_kept_file_allowances(self):
        # Sized against storage cost: 200 GB full was more than Premium earns.
        gib = 1024**3
        assert billing.entitlements_for(billing.FREE).file_bytes == gib // 2
        assert billing.entitlements_for(billing.STANDARD).file_bytes == 5 * gib
        assert billing.entitlements_for(billing.PREMIUM).file_bytes == 15 * gib

    def test_a_snapshot_with_file_bytes_keeps_them(self):
        held = {"tier": "standard", "status": "active", "memoryWindowDays": 365, "fileBytes": 7}
        assert billing.resolve(held, now=NOW).file_bytes == 7
        assert billing.resolve({**held, "fileBytes": None}, now=NOW).file_bytes is None

    def test_every_snapshot_writer_records_every_axis(self):
        import subscriptions
        import user_lifecycle

        axes = set(billing.snapshot_fields(billing.entitlements_for(billing.FREE)))
        assert "fileBytes" in axes

        doc = subscriptions.snapshot(TestSnapshot()._verified(billing.PREMIUM))
        assert axes <= set(doc)
        assert doc["fileBytes"] == billing.entitlements_for(billing.PREMIUM).file_bytes

        assert axes <= set(user_lifecycle.FREE_TIER)
        assert user_lifecycle.FREE_TIER["fileBytes"] == 512 * 1024**2
        assert user_lifecycle.FREE_TIER["windowQueries"] == billing.FREE_ANSWERS[0]
        assert user_lifecycle.FREE_TIER["weeklyQueries"] == billing.FREE_ANSWERS[1]
