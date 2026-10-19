"""The local filter parser — architecture §24 without a model call.

These tests exist because the parser replaced something that could not be
tested at all: a model call whose output varied run to run and failed one
time in three. A deterministic parser can be pinned to examples, and every
example below is a phrase a person would actually say.
"""

from datetime import UTC, datetime, timedelta, timezone

import query_understanding as qu

NOW = datetime(2026, 9, 11, 14, 30, tzinfo=UTC)


def parse(question: str):
    return qu.understand_locally(question, now=NOW)


class TestTypes:
    def test_names_the_type_and_lifts_it_out_of_the_search_text(self):
        q = parse("find that video about vector databases")
        assert q.memory_types == ("video",)
        assert "video" not in q.search.lower()
        assert "vector databases" in q.search

    def test_plural(self):
        assert parse("show me my screenshots").memory_types == (
            "photo",
            "screenshot",
        )

    def test_longest_pattern_wins(self):
        # "voice note" must not be read as "note", which maps elsewhere.
        assert parse("the voice note about the flat").memory_types == (
            "audio",
            "voiceNote",
        )

    def test_word_boundary(self):
        # "videographer" contains "video" and is not a type.
        assert parse("the videographer invoice").memory_types == ()

    def test_no_type_named(self):
        assert parse("what did we agree on pricing").memory_types == ()


class TestDates:
    def test_named_month_resolves_to_that_whole_month(self):
        q = parse("the deck from July")
        assert q.after == datetime(2026, 7, 1, tzinfo=UTC)
        assert q.before.date().isoformat() == "2026-07-31"

    def test_month_still_to_come_means_last_year(self):
        # Asked in September, "December" cannot mean a December that has not
        # happened — nothing could have been saved in it.
        q = parse("the invoice from December")
        assert q.after.year == 2025

    def test_explicit_year_is_respected(self):
        q = parse("the contract from March 2024")
        assert q.after == datetime(2024, 3, 1, tzinfo=UTC)

    def test_last_week(self):
        assert parse("anything from last week").after == datetime(2026, 9, 4, tzinfo=UTC)

    def test_last_n_days_beats_last_week(self):
        # Both patterns could match "last 10 days" if ordering were wrong.
        assert parse("notes from the last 10 days").after == datetime(2026, 9, 1, tzinfo=UTC)

    def test_last_month_is_the_previous_calendar_month(self):
        q = parse("invoices from last month")
        assert q.after == datetime(2026, 8, 1, tzinfo=UTC)
        assert q.before.date().isoformat() == "2026-08-31"

    def test_bare_year(self):
        q = parse("anything from 2025")
        assert q.after.year == 2025
        assert q.before.year == 2025

    def test_no_date_named(self):
        q = parse("the pricing brochure")
        assert q.after is None and q.before is None


class TestRemainder:
    def test_openers_are_stripped(self):
        assert parse("show me the pricing brochure").search == "pricing brochure"

    def test_trailing_filler_is_trimmed(self):
        # "invoices from last month" leaves a dangling "from".
        assert parse("invoices from last month").search == "invoices"

    def test_falls_back_when_only_filters_remain(self):
        # Reduces to "my from", which is long enough to pass a length check
        # and meaningless to embed. The filters still apply.
        q = parse("show me my screenshots from last week")
        assert q.search == "show me my screenshots from last week"
        assert q.memory_types == ("photo", "screenshot")
        assert q.after is not None

    def test_a_bare_term_is_left_alone(self):
        assert parse("ardhya aura").search == "ardhya aura"

    def test_signals_report_what_was_read(self):
        q = parse("find the video about pricing from July")
        assert q.signals["type"] == "video"
        assert q.signals["after"] == "2026-07-01"
        assert q.signals["rewritten"] is True

    def test_rewritten_is_false_when_the_text_was_kept(self):
        # "find the video from July" is nothing but filters, so the fallback
        # keeps the whole question — and `rewritten` has to say so. A signal
        # that claims a rewrite that did not happen would send the UI looking
        # for a narrowed query that is not there.
        q = parse("find the video from July")
        assert q.signals["rewritten"] is False
        assert q.search == "find the video from July"


class TestContract:
    def test_never_raises(self):
        for question in ("", "   ", "?", "a", "video " * 200, "🙂"):
            assert isinstance(parse(question), qu.Query)

    def test_search_is_never_empty(self):
        for question in ("video", "last week", "show me", "pdf from July"):
            assert parse(question).search.strip()

    def test_within_dates_passes_undated_candidates(self):
        # A filter that removes the answer is worse than one that removes
        # nothing — memories ingested before capturedAt existed have none.
        q = parse("anything from last week")
        assert q.within_dates(None) is True


IST = timezone(timedelta(hours=5, minutes=30))


class TestExplicitDays:
    """One named day is that day, not its month."""

    def test_day_then_month_is_the_most_recent_such_day(self):
        # Asked on 11 Sep 2026: 27 Sep has not happened yet this year.
        q = qu.understand_locally("What does the photo from 27 Sep show?", now=NOW)
        assert q.after == datetime(2025, 9, 27, tzinfo=UTC)
        assert q.before == datetime(2025, 9, 27, 23, 59, 59, tzinfo=UTC)
        assert q.memory_types == ("photo", "screenshot")
        assert "27" not in q.search and "Sep" not in q.search

    def test_month_then_day_with_an_ordinal_and_a_year(self):
        q = qu.understand_locally("the invoice from Sep 3rd, 2026", now=NOW)
        assert q.after == datetime(2026, 9, 3, tzinfo=UTC)
        assert q.search == "invoice"

    def test_numeric_dates_iso_and_day_first(self):
        assert qu.understand_locally("notes 2026-09-03", now=NOW).after == datetime(
            2026, 9, 3, tzinfo=UTC
        )
        assert qu.understand_locally("notes 03/09/2026", now=NOW).after == datetime(
            2026, 9, 3, tzinfo=UTC
        )

    def test_an_impossible_day_falls_back_to_the_month(self):
        q = qu.understand_locally("31 sep", now=NOW)
        assert q.after == datetime(2026, 9, 1, tzinfo=UTC)
        assert q.before == datetime(2026, 9, 30, 23, 59, 59, tzinfo=UTC)

    def test_a_month_with_a_year_is_still_the_month(self):
        q = qu.understand_locally("invoices from september 2025", now=NOW)
        assert q.after == datetime(2025, 9, 1, tzinfo=UTC)


class TestZones:
    """Windows are built in the zone of `now`, and the API passes the phone's."""

    def test_today_is_the_users_today(self):
        # 01:30 on 27 Sep in India. A photo taken at 20:22 UTC on the 26th
        # is 01:52 on the 27th there — today. In UTC it was yesterday.
        captured = datetime(2026, 9, 26, 20, 22, tzinfo=UTC)
        india = qu.understand_locally("today", now=datetime(2026, 9, 27, 1, 30, tzinfo=IST))
        assert india.after == datetime(2026, 9, 27, tzinfo=IST)
        assert india.within_dates(captured)
        assert india.signals["after"] == "2026-09-27"
        greenwich = qu.understand_locally("today", now=datetime(2026, 9, 27, 1, 30, tzinfo=UTC))
        assert not greenwich.within_dates(captured)

    def test_a_named_day_said_that_day_is_today_not_last_year(self):
        q = qu.understand_locally("27 sep", now=datetime(2026, 9, 27, 1, 30, tzinfo=IST))
        assert q.after == datetime(2026, 9, 27, tzinfo=IST)

    def test_the_api_reads_the_phones_offset(self):
        import api

        assert api._zone(330).utcoffset(None) == timedelta(minutes=330)
        assert api._zone("330").utcoffset(None) == timedelta(minutes=330)
        assert api._zone(None) is UTC
        assert api._zone("later") is UTC
        assert api._zone(10_000) is UTC
