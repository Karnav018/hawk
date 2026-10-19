import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/features/chat/data/local/local_query.dart';
import 'package:knowra/src/features/memory/domain/entities/memory_enums.dart';

/// The phone reads a question the way the server used to
/// (`query_understanding.understand_locally`). Same cases, same answers.
void main() {
  final march = DateTime.utc(2026, 3, 10, 12);

  test('a type word becomes a filter and leaves the search text', () {
    final q = understandLocally('show me the videos about vector databases');
    expect(q.memoryTypes, {MemoryType.video});
    // Leading filler goes too — "about" is in the server's FILLER set.
    expect(q.search, 'vector databases');
    expect(q.signals.type, 'video');
    expect(q.signals.rewritten, isTrue);
  });

  test('"voice note" is audio, not a note', () {
    expect(understandLocally('the voice note from the standup').memoryTypes, {
      MemoryType.audio,
      MemoryType.voiceNote,
    });
  });

  test('"videographer" is not a video', () {
    expect(understandLocally('the videographer quote').memoryTypes, isEmpty);
  });

  test('last week is a window from seven days ago', () {
    final q = understandLocally('screenshots from last week', now: march);
    expect(q.memoryTypes, {MemoryType.photo, MemoryType.screenshot});
    expect(q.after, DateTime.utc(2026, 3, 3));
    expect(q.before, isNull);
  });

  test('a month named in the past year means last year\'s month', () {
    // "July" said in March: the July that has happened.
    final q = understandLocally('the lease I signed in July', now: march);
    expect(q.after, DateTime.utc(2025, 7));
    expect(q.before, DateTime.utc(2025, 7, 31, 23, 59, 59));
    expect(q.search, 'lease I signed');
  });

  test('september is not read as sep-tember of something else', () {
    final q = understandLocally('invoices from september 2025', now: march);
    expect(q.after, DateTime.utc(2025, 9));
    expect(q.signals.after, '2025-09-01');
  });

  test('yesterday is one day, both ends', () {
    final q = understandLocally('what did I save yesterday', now: march);
    expect(q.after, DateTime.utc(2026, 3, 9));
    expect(q.before, DateTime.utc(2026, 3, 9, 23, 59, 59));
  });

  test('a question that is nothing but filters embeds itself whole', () {
    // "my from" is not worth embedding; the filters still narrow.
    final q = understandLocally('show me my screenshots from last week');
    expect(q.search, 'show me my screenshots from last week');
    expect(q.hasFilters, isTrue);
  });

  test('a capture with no date passes every window', () {
    final q = understandLocally('photos from last week', now: march);
    expect(q.withinDates(null), isTrue);
    expect(q.withinDates(DateTime.utc(2026, 3, 8)), isTrue);
    expect(q.withinDates(DateTime.utc(2026, 2, 1)), isFalse);
  });

  test('a day with a month name is that day, the most recent one', () {
    // Asked on 10 March 2026: 27 Sep has not happened this year.
    final q = understandLocally(
      'What does the photo from 27 Sep show?',
      now: march,
    );
    expect(q.after, DateTime.utc(2025, 9, 27));
    expect(q.before, DateTime.utc(2025, 9, 27, 23, 59, 59));
    expect(q.memoryTypes, {MemoryType.photo, MemoryType.screenshot});
    expect(q.signals.after, '2025-09-27');
    expect(q.search, isNot(contains('Sep')));
  });

  test('month then day, with an ordinal and a year', () {
    final q = understandLocally('the invoice from Sep 3rd, 2026', now: march);
    expect(q.after, DateTime.utc(2026, 9, 3));
    expect(q.search, 'invoice');
  });

  test('numeric dates: ISO and day-first', () {
    expect(
      understandLocally('notes 2026-09-03', now: march).after,
      DateTime.utc(2026, 9, 3),
    );
    expect(
      understandLocally('notes 03/09/2026', now: march).after,
      DateTime.utc(2026, 9, 3),
    );
  });

  test('an impossible day falls back to the month', () {
    final q = understandLocally('31 sep', now: march);
    expect(q.after, DateTime.utc(2025, 9));
    expect(q.before, DateTime.utc(2025, 9, 30, 23, 59, 59));
  });

  test('windows are built in the zone of now, never forced to UTC', () {
    // 01:30 on 27 Sep on the phone: "today" is the phone's 27 Sep, and
    // "27 sep" said that day is today, not last year.
    final local = DateTime(2026, 9, 27, 1, 30);
    final today = understandLocally('today', now: local);
    expect(today.after!.isUtc, isFalse);
    expect(
      (
        today.after!.year,
        today.after!.month,
        today.after!.day,
        today.after!.hour,
      ),
      (2026, 9, 27, 0),
    );
    expect(today.signals.after, '2026-09-27');
    final named = understandLocally('27 sep', now: local);
    expect((named.after!.year, named.after!.day), (2026, 27));
  });

  test('a follow-up is retrieved with its earlier questions', () {
    expect(
      contextualise('what about Team?', ['pricing tiers we agreed']),
      'pricing tiers we agreed what about Team?',
    );
    expect(contextualise('lease', []), 'lease');
    expect(contextualise('e', ['a', 'b', 'c', 'd', 'x']).split(' '), [
      'b',
      'c',
      'd',
      'x',
      'e',
    ], reason: 'the last four, in order');
  });
}
