import '../../../memory/domain/entities/memory_enums.dart';
import '../../domain/entities/answer.dart';

/// A question, split into what to match and what to narrow by.
///
/// A port of the backend's `query_understanding.understand_locally`, kept
/// line for line where it can be: the index now lives on the phone, so the
/// phone has to read the question the way the server used to. "Find that
/// video about vector databases I watched around July" carries three signals,
/// and an embedding of the whole sentence uses only one — "video" and "July"
/// get averaged into the vector where they compete with the content instead
/// of narrowing it. Lifted out as filters they do the opposite.
class LocalQuery {
  const LocalQuery({
    required this.search,
    this.memoryTypes = const {},
    this.after,
    this.before,
    this.signals = const QuerySignals(),
  });

  /// The text actually embedded. Falls back to the raw question.
  final String search;
  final Set<MemoryType> memoryTypes;
  final DateTime? after;
  final DateTime? before;
  final QuerySignals signals;

  bool get hasFilters =>
      memoryTypes.isNotEmpty || after != null || before != null;

  /// Whether a candidate falls inside the window.
  ///
  /// A candidate with no capture date **passes**. Hiding anything we cannot
  /// date would silently drop every memory saved before the field existed,
  /// and a filter that removes the answer is worse than one that removes
  /// nothing.
  bool withinDates(DateTime? captured) {
    if (captured == null) return true;
    if (after != null && captured.isBefore(after!)) return false;
    if (before != null && captured.isAfter(before!)) return false;
    return true;
  }
}

/// Words a person uses for a kind of file, longest first so "voice note" is
/// not read as "note". The kind maps to the wire types stored on chunks.
const _typeVocabulary = <(String, String)>[
  ('voice note', 'audio'),
  ('voice memo', 'audio'),
  ('screenshot', 'image'),
  ('recording', 'audio'),
  ('document', 'document'),
  ('picture', 'image'),
  ('article', 'link'),
  ('podcast', 'audio'),
  ('video', 'video'),
  ('photo', 'image'),
  ('image', 'image'),
  ('audio', 'audio'),
  ('clip', 'video'),
  ('note', 'note'),
  ('link', 'link'),
  ('url', 'link'),
  ('pdf', 'document'),
  ('doc', 'document'),
];

const _typeWords = <String, Set<MemoryType>>{
  'video': {MemoryType.video},
  'audio': {MemoryType.audio, MemoryType.voiceNote},
  'image': {MemoryType.photo, MemoryType.screenshot},
  'document': {MemoryType.pdf, MemoryType.document},
  'note': {MemoryType.note, MemoryType.text},
  'link': {MemoryType.link},
};

/// Openers that carry no content. Stripped from the front only.
const _openers = [
  'can you find',
  'do i have',
  'show me',
  'find me',
  'search for',
  'look for',
  'where is',
  'where are',
  'what was',
  'what did',
  'remind me',
  'get me',
  'find',
  'show',
];

const _filler = {
  'a', 'an', 'and', 'about', 'all', 'any', 'anything', 'around', 'as', 'at', //
  'be', 'by', 'did', 'do', 'for', 'from', 'have', 'i', 'in', 'is', 'it',
  'its', 'me', 'my', 'of', 'on', 'or', 'our', 'saw', 'some', 'that', 'the',
  'their', 'then', 'there', 'these', 'they', 'this', 'those', 'to', 'was',
  'watched', 'we', 'were', 'what', 'when', 'where', 'which', 'with', 'you',
};

const _months = <String, int>{
  'january': 1, 'jan': 1, 'february': 2, 'feb': 2, 'march': 3, 'mar': 3, //
  'april': 4, 'apr': 4, 'may': 5, 'june': 6, 'jun': 6, 'july': 7, 'jul': 7,
  'august': 8, 'aug': 8, 'september': 9, 'sep': 9, 'october': 10, 'oct': 10,
  'november': 11, 'nov': 11, 'december': 12, 'dec': 12,
};

/// A moment in the zone of [like]: UTC when [like] is UTC (tests), the
/// phone's own zone otherwise. Every window is built this way, so
/// "yesterday" is the user's yesterday — for a user in India the UTC one
/// disagrees until 05:30 every morning.
DateTime _at(
  DateTime like,
  int year,
  int month,
  int day, [
  int hour = 0,
  int minute = 0,
  int second = 0,
]) => like.isUtc
    ? DateTime.utc(year, month, day, hour, minute, second)
    : DateTime(year, month, day, hour, minute, second);

(DateTime, DateTime) _monthWindow(DateTime like, int year, int month) {
  final last = _at(like, year, month + 1, 0).day;
  return (_at(like, year, month, 1), _at(like, year, month, last, 23, 59, 59));
}

/// Longest names first, so "september" is never read as "sep".
final _monthAlternation =
    (_months.keys.toList()..sort((a, b) => b.length.compareTo(a.length))).join(
      '|',
    );

/// One named day — "27 Sep" — as that day's window, in [today]'s zone.
///
/// Checked before the bare month names, or "27 sep" reads as all of
/// September. Without a year the day is the most recent one that has
/// already happened: "27 Sep" asked on 11 Sep is last year's, asked on 27
/// Sep it is today. An impossible day (31 Sep) is left for the month rule.
(DateTime, DateTime, RegExp)? _explicitDay(String lowered, DateTime today) {
  // (pattern, day group, month group, year group); a month group may hold
  // a number or a name.
  final shapes = <(RegExp, int, int, int)>[
    // 2026-09-27
    (RegExp(r'\b(20\d{2})-(\d{1,2})-(\d{1,2})\b'), 3, 2, 1),
    // 27/09/2026, 27-09-2026, 27.09.2026 — day first, as this product's
    // users write it.
    (RegExp(r'\b(\d{1,2})[/.-](\d{1,2})[/.-](20\d{2})\b'), 1, 2, 3),
    // 27 sep, 27th of september 2026
    (
      RegExp(
        '\\b(?:on |from )?(\\d{1,2})(?:st|nd|rd|th)?\\s+(?:of\\s+)?'
        '($_monthAlternation)\\b(?:,?\\s+(20\\d{2}))?',
        caseSensitive: false,
      ),
      1,
      2,
      3,
    ),
    // sep 27, september 27th, 2026
    (
      RegExp(
        '\\b(?:on |from )?($_monthAlternation)\\s+(\\d{1,2})(?:st|nd|rd|th)?\\b'
        '(?:,?\\s+(20\\d{2}))?',
        caseSensitive: false,
      ),
      2,
      1,
      3,
    ),
  ];
  for (final (pattern, dayAt, monthAt, yearAt) in shapes) {
    final match = pattern.firstMatch(lowered);
    if (match == null) continue;
    final rawMonth = match.group(monthAt)!;
    final month = int.tryParse(rawMonth) ?? _months[rawMonth.toLowerCase()];
    if (month == null || month < 1 || month > 12) continue;
    final day = int.parse(match.group(dayAt)!);
    final given = match.group(yearAt);
    var year = given == null ? today.year : int.parse(given);
    if (day < 1 || day > _at(today, year, month + 1, 0).day) continue;
    if (given == null && _at(today, year, month, day).isAfter(today)) {
      year -= 1;
      if (day > _at(today, year, month + 1, 0).day) continue;
    }
    return (
      _at(today, year, month, day),
      _at(today, year, month, day, 23, 59, 59),
      pattern,
    );
  }
  return null;
}

/// Parse filters out of a question with no network call.
LocalQuery understandLocally(String question, {DateTime? now}) {
  final moment = now ?? DateTime.now();
  final text = question.trim();
  final lowered = text.toLowerCase();

  String? kind;
  final matched = <RegExp>[];
  for (final (word, canonical) in _typeVocabulary) {
    // `\b…s?\b`, so "videos" matches and "videographer" does not.
    final pattern = RegExp('\\b${RegExp.escape(word)}s?\\b');
    if (pattern.hasMatch(lowered)) {
      kind = canonical;
      matched.add(pattern);
      break;
    }
  }

  final (after, before, datePattern) = _parseDates(lowered, moment);
  if (datePattern != null) matched.add(datePattern);

  final search = _remainder(text, matched);

  String day(DateTime? d) =>
      d == null ? '' : d.toIso8601String().substring(0, 10);

  return LocalQuery(
    search: search,
    memoryTypes: kind == null ? const {} : (_typeWords[kind] ?? const {}),
    after: after,
    before: before,
    signals: QuerySignals(
      type: kind,
      after: after == null ? null : day(after),
      before: before == null ? null : day(before),
      rewritten: search != text,
    ),
  );
}

/// What is left to embed once the filters have been lifted out — or the
/// whole question when too little survives, because "my from" is not worth
/// embedding and the filters still apply either way.
String _remainder(String text, List<RegExp> patterns) {
  var stripped = text;
  for (final pattern in patterns) {
    stripped = stripped.replaceAll(
      RegExp(pattern.pattern, caseSensitive: false),
      ' ',
    );
  }
  stripped = _stripOpener(stripped);
  stripped = stripped.replaceAll(RegExp(r'\s+'), ' ');
  stripped = stripped.replaceAll(RegExp(r'^[ ,.?!-]+|[ ,.?!-]+$'), '');

  final words = stripped.split(' ').where((w) => w.isNotEmpty).toList();
  String bare(String w) =>
      w.toLowerCase().replaceAll(RegExp(r'^[,.?!]+|[,.?!]+$'), '');
  while (words.isNotEmpty && _filler.contains(bare(words.first))) {
    words.removeAt(0);
  }
  while (words.isNotEmpty && _filler.contains(bare(words.last))) {
    words.removeLast();
  }
  final content = words.where((w) => !_filler.contains(bare(w))).length;
  if (content < 1 || words.join(' ').length < 3) return text;
  return words.join(' ');
}

String _stripOpener(String text) {
  final stripped = text.trim();
  final lowered = stripped.toLowerCase();
  for (final opener in _openers) {
    if (lowered.startsWith(opener)) {
      return stripped
          .substring(opener.length)
          .replaceAll(RegExp(r'^[ ,]+'), '');
    }
  }
  return stripped;
}

/// The date window, and the pattern to remove from the search text. Most
/// specific first, so "last month" is tested before a bare month name.
(DateTime?, DateTime?, RegExp?) _parseDates(String lowered, DateTime now) {
  final today = _at(now, now.year, now.month, now.day);

  final lastDays = RegExp(r'\blast (\d{1,3}) days?\b').firstMatch(lowered);
  if (lastDays != null) {
    final days = int.parse(lastDays.group(1)!).clamp(0, 3650);
    return (
      today.subtract(Duration(days: days)),
      null,
      RegExp(r'\blast \d{1,3} days?\b'),
    );
  }
  if (RegExp(r'\b(today)\b').hasMatch(lowered)) {
    return (today, null, RegExp(r'\b(today)\b'));
  }
  if (RegExp(r'\byesterday\b').hasMatch(lowered)) {
    final y = today.subtract(const Duration(days: 1));
    return (
      y,
      _at(now, y.year, y.month, y.day, 23, 59, 59),
      RegExp(r'\byesterday\b'),
    );
  }
  if (RegExp(r'\b(this|last|past) week\b').hasMatch(lowered)) {
    return (
      today.subtract(const Duration(days: 7)),
      null,
      RegExp(r'\b(this|last|past) week\b'),
    );
  }
  if (RegExp(r'\b(last|past) month\b').hasMatch(lowered)) {
    final previous = _at(now, today.year, today.month, 0);
    final (start, end) = _monthWindow(now, previous.year, previous.month);
    return (start, end, RegExp(r'\b(last|past) month\b'));
  }
  if (RegExp(r'\bthis month\b').hasMatch(lowered)) {
    final (start, _) = _monthWindow(now, today.year, today.month);
    return (start, null, RegExp(r'\bthis month\b'));
  }
  if (RegExp(r'\b(last|past) year\b').hasMatch(lowered)) {
    final year = today.year - 1;
    return (
      _at(now, year, 1, 1),
      _at(now, year, 12, 31, 23, 59, 59),
      RegExp(r'\b(last|past) year\b'),
    );
  }
  final explicit = _explicitDay(lowered, today);
  if (explicit != null) return explicit;
  // A named month, optionally with a year. Full names before abbreviations,
  // so "september" is not matched as "sep".
  final names = _months.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  for (final name in names) {
    final pattern = RegExp(
      '\\b(?:in |around |during |from )?$name\\b(?:\\s+(\\d{4}))?',
    );
    final match = pattern.firstMatch(lowered);
    if (match == null) continue;
    final number = _months[name]!;
    var year = match.group(1) == null ? today.year : int.parse(match.group(1)!);
    // "July" said in March means last July — a question is always about
    // something already saved.
    if (match.group(1) == null && number > today.month) year -= 1;
    final (start, end) = _monthWindow(now, year, number);
    return (start, end, pattern);
  }
  final year = RegExp(r'\b(20\d{2})\b').firstMatch(lowered);
  if (year != null) {
    final y = int.parse(year.group(1)!);
    return (
      _at(now, y, 1, 1),
      _at(now, y, 12, 31, 23, 59, 59),
      RegExp(r'\b20\d{2}\b'),
    );
  }
  return (null, null, null);
}

/// Fold a follow-up into text that can stand on its own for retrieval.
///
/// "What about Team?" retrieves nothing by itself — the subject is in the
/// previous turn. The recent questions are prepended to the *embedding text*
/// only; the server still answers the question as asked.
String contextualise(String question, List<String> earlier, {int limit = 4}) {
  final recent = [
    for (final q in earlier.reversed.take(limit).toList().reversed)
      if (q.trim().isNotEmpty) q.trim(),
  ];
  if (recent.isEmpty) return question;
  return [...recent, question].join(' ');
}
