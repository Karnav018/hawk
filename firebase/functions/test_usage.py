"""Answer metering — the rolling two-hour window and the week.

The Firestore transaction needs the emulator; the rules do not, and they are
all in `Ledger`, `standing`, `take` and `give_back`.
"""

from datetime import UTC, datetime, timedelta, timezone

import pytest

import billing
import usage

IST = timezone(timedelta(hours=5, minutes=30))
# A Saturday, 10:00 in India.
T0 = datetime(2026, 9, 26, 4, 30, tzinfo=UTC)
FREE = billing.entitlements_for(billing.FREE)
STANDARD = billing.entitlements_for(billing.STANDARD)
PREMIUM = billing.entitlements_for(billing.PREMIUM)


def _take(ledger, ent, at, zone=IST):
    return usage.take(ledger, ent, at, zone)


class TestTheWindow:
    """Each answer comes back two hours after it was used, on its own."""

    def test_answers_return_one_by_one_not_all_at_once(self):
        ledger = usage.Ledger()
        ledger, _ = _take(ledger, FREE, T0)  # 10:00
        ledger, _ = _take(ledger, FREE, T0 + timedelta(minutes=50))  # 10:50

        # Out: the next one is back at 12:00, when the first was used + 2 h.
        now = T0 + timedelta(minutes=55)
        s = usage.standing(usage.Ledger.read(ledger.to_doc(now), now), FREE, now, IST)
        assert s.window_remaining == 0
        assert s.spent == "window"
        assert s.available_at == T0 + timedelta(hours=2)

        # At 12:00 exactly one comes back — not both.
        noon = T0 + timedelta(hours=2)
        s = usage.standing(usage.Ledger.read(ledger.to_doc(noon), noon), FREE, noon, IST)
        assert s.window_remaining == 1
        assert s.window_next_at == T0 + timedelta(hours=2, minutes=50)

    def test_the_refusal_names_the_next_return_in_the_users_clock(self):
        ledger = usage.Ledger()
        ledger, _ = _take(ledger, FREE, T0)
        ledger, _ = _take(ledger, FREE, T0 + timedelta(minutes=10))
        with pytest.raises(usage.Spent) as caught:
            _take(ledger, FREE, T0 + timedelta(minutes=20))
        error = usage.exhausted(FREE, caught.value.standing, IST)
        assert "back at 12:00 pm" in error.message
        assert "Upgrade" in error.message
        assert error.details["which"] == "window"
        assert error.details["upgradeable"] is True

    def test_no_burst_fits_two_windows_across_a_boundary(self):
        # A fixed window let 2 at 11:59 and 2 at 12:00. A rolling one never
        # allows more than the limit inside any two hours.
        ledger = usage.Ledger()
        start = T0
        for i in range(FREE.window_queries):
            ledger, _ = _take(ledger, FREE, start + timedelta(seconds=i))
        with pytest.raises(usage.Spent):
            _take(ledger, FREE, start + timedelta(hours=1, minutes=59))


class TestTheWeek:
    """The cost cap: resets Monday 00:00 in the zone the week began in."""

    def test_the_week_ends_on_the_next_monday_in_the_users_zone(self):
        ledger, reservation = _take(usage.Ledger(), FREE, T0)
        monday_ist = datetime(2026, 9, 28, 0, 0, tzinfo=IST)
        assert ledger.week_ends_at == monday_ist
        assert reservation.week_ends_at == monday_ist

    def test_a_spent_week_waits_for_monday_even_with_the_window_free(self):
        ledger = usage.Ledger(
            week_count=FREE.weekly_queries, week_ends_at=datetime(2026, 9, 28, tzinfo=IST)
        )
        with pytest.raises(usage.Spent) as caught:
            _take(ledger, FREE, T0)
        s = caught.value.standing
        assert s.spent == "week"
        assert s.available_at == datetime(2026, 9, 28, tzinfo=IST)
        assert "reset on Monday" in usage.exhausted(FREE, s, IST).message

    def test_monday_starts_the_count_again(self):
        ends = datetime(2026, 9, 28, tzinfo=IST)
        doc = usage.Ledger(week_count=20, week_ends_at=ends).to_doc(T0)
        after = usage.Ledger.read(doc, ends + timedelta(seconds=1))
        assert after.week_count == 0
        assert after.week_ends_at is None

    def test_changing_the_phones_zone_cannot_reset_the_week(self):
        # The end is recorded when the week begins. A client claiming a zone
        # where it is already Monday still waits for the recorded end.
        ends = datetime(2026, 9, 28, tzinfo=IST)
        ledger = usage.Ledger(week_count=FREE.weekly_queries, week_ends_at=ends)
        sunday_night = datetime(2026, 9, 27, 17, 0, tzinfo=UTC)  # 22:30 IST
        far_east = timezone(timedelta(hours=14))  # already Monday there
        with pytest.raises(usage.Spent):
            _take(ledger, FREE, sunday_night, far_east)


class TestReserveAndGiveBack:
    """A slot is taken before answering and returned if it should not count."""

    def test_giving_back_restores_both_allowances(self):
        ledger, reservation = _take(usage.Ledger(), STANDARD, T0)
        assert (len(ledger.stamps), ledger.week_count) == (1, 1)
        back = usage.give_back(ledger, reservation)
        assert (len(back.stamps), back.week_count) == (0, 0)

    def test_the_reservation_round_trips_through_the_stored_document(self):
        ledger, reservation = _take(usage.Ledger(), STANDARD, T0)
        stored = usage.Ledger.read(ledger.to_doc(T0), T0 + timedelta(seconds=3))
        back = usage.give_back(stored, reservation)
        assert back.stamps == () and back.week_count == 0

    def test_a_give_back_after_the_week_ended_takes_nothing_from_the_new_one(self):
        ledger, reservation = _take(usage.Ledger(), STANDARD, T0)
        new_week = usage.Ledger(week_count=3, week_ends_at=datetime(2026, 10, 5, tzinfo=IST))
        assert usage.give_back(new_week, reservation).week_count == 3

    def test_the_report_after_a_take_counts_it(self):
        _, reservation = _take(usage.Ledger(), STANDARD, T0)
        report = reservation.report
        assert report["window"] == {
            "limit": 10,
            "used": 1,
            "remaining": 9,
            "hours": 2,
            "nextAt": (T0 + timedelta(hours=2)).isoformat(),
        }
        assert report["week"]["remaining"] == 149
        assert report["remaining"] == 9
        assert report["spent"] is None and report["availableAt"] is None


class TestPlans:
    def test_every_plan_has_both_limits(self):
        for ent in (FREE, STANDARD, PREMIUM):
            assert ent.window_queries and ent.weekly_queries, ent.tier

    def test_the_decided_numbers(self):
        assert (FREE.window_queries, FREE.weekly_queries) == (2, 20)
        assert (STANDARD.window_queries, STANDARD.weekly_queries) == (10, 150)
        assert (PREMIUM.window_queries, PREMIUM.weekly_queries) == (25, 400)
        assert billing.ANSWER_WINDOW_HOURS == 2

    def test_each_plan_is_more_generous_than_the_one_below(self):
        assert FREE.window_queries < STANDARD.window_queries < PREMIUM.window_queries
        assert FREE.weekly_queries < STANDARD.weekly_queries < PREMIUM.weekly_queries

    def test_only_premium_is_told_there_is_nothing_to_upgrade_to(self):
        ledger = usage.Ledger(
            week_count=PREMIUM.weekly_queries, week_ends_at=datetime(2026, 9, 28, tzinfo=IST)
        )
        with pytest.raises(usage.Spent) as caught:
            _take(ledger, PREMIUM, T0)
        error = usage.exhausted(PREMIUM, caught.value.standing, IST)
        assert "Upgrade" not in error.message
        assert error.details["upgradeable"] is False
        assert billing.answers_upgradeable(billing.STANDARD)


class TestWhatCounts:
    """One answer per question that found something — and nothing else."""

    def test_an_answer_from_your_files_counts(self):
        assert usage.counts_as_ask(answered=True, cited=2)

    def test_nothing_found_is_free(self):
        assert not usage.counts_as_ask(answered=False, cited=0)

    def test_a_stray_tap_is_free(self):
        assert not usage.counts_as_ask(answered=False, cited=3)

    def test_an_answer_with_no_source_is_free(self):
        assert not usage.counts_as_ask(answered=True, cited=0)


def test_clock_reads_like_a_person_writes_it():
    assert usage._clock(datetime(2026, 9, 26, 6, 30, tzinfo=UTC), IST) == "12:00 pm"
    assert usage._clock(datetime(2026, 9, 26, 18, 35, tzinfo=UTC), IST) == "12:05 am"
    assert usage._clock(datetime(2026, 9, 26, 9, 42, tzinfo=UTC), IST) == "3:12 pm"
