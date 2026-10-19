import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

import '../../../../core/bloc/safe_emit.dart';
import '../../../memory/domain/entities/memory.dart';
import '../../../memory/domain/entities/memory_enums.dart';
import '../../../memory/domain/repositories/memory_repository.dart';

/// One thing home offers to ask: a short [chip] for the voice face (1Y) and
/// the full [question] the chat face (1Z) lists and either face submits.
/// [type] is what the memory is, for the chip's icon.
typedef Suggestion = ({String chip, String question, MemoryType type});

/// Suggestions built from the user's own library — never sample topics.
///
/// The design fills these with "Pricing we agreed", "Lease PDF" and
/// "Standup". Shown to a real user they would be questions about files that
/// user does not have, and the first tap would come back "No match". So they
/// are made from the most recent memories that are actually searchable, and
/// phrased by what kind of thing each one is.
///
/// **Named for a person, not a file system.** The first cut printed the
/// stored title, which for anything from the photo picker or a camera is a
/// filename like `1000047716` or `IMG_20260923_142311`. A chip reading
/// "1000047716" above the nav looked like a stray banner about a file, told
/// nobody what tapping it would do, and asked "What does 1000047716 show?"
/// — a search for a number that appears nowhere in the photo. A name that
/// is only numbers and camera words is now called what it is and when it
/// arrived — "Photo · 23 Sep" — and the question says the same, which the
/// query parser reads as a type and a date.
///
/// Only indexed memories. Offering to ask about something still in the
/// pipeline is offering a question that cannot be answered yet.
List<Suggestion> suggestionsFrom(List<Memory> memories, {int max = 3}) {
  final out = <Suggestion>[];
  final seen = <String>{};
  for (final m in memories) {
    if (m.status != ProcessingStatus.indexed &&
        m.status != ProcessingStatus.ready) {
      continue;
    }
    final name = _name(m.displayTitle);
    if (name.isEmpty) continue;

    final machine = isMachineName(name);
    final label = machine
        ? '${_kind(m.type)} · ${_day(m.createdAt)}'
        : _tidy(name);
    // Two photos from one day are the same chip; the second is skipped
    // rather than shown as a twin.
    if (label.isEmpty || !seen.add(label.toLowerCase())) continue;

    out.add((
      chip: _clip(_capitalised(label), 22),
      question: machine
          ? _aboutUnnamed(m.type, _day(m.createdAt))
          : _question(m.type, label),
      type: m.type,
    ));
    if (out.length == max) break;
  }
  return out;
}

/// The title without a file extension: "board-pack-sep.pdf" reads as a file
/// name in a question, "board-pack-sep" reads as a thing.
String _name(String title) {
  final t = title.trim();
  final dot = t.lastIndexOf('.');
  final ext = dot > 0 ? t.substring(dot + 1) : '';
  return ext.isNotEmpty && ext.length <= 5 && !ext.contains(' ')
      ? t.substring(0, dot).trim()
      : t;
}

/// Words cameras, pickers and recorders put in filenames, which say nothing
/// about what is in the file.
const _deviceWords = {
  'img',
  'image',
  'images',
  'vid',
  'video',
  'pxl',
  'dsc',
  'dscn',
  'dcim',
  'cap',
  'scaled',
  'picker',
  'photo',
  'pic',
  'screenshot',
  'screenshots',
  'scan',
  'scanned',
  'mvimg',
  'audio',
  'recording',
  'rec',
  'voice',
  'note',
  'file',
  'hawk',
  'capture',
  'cropped',
  'whatsapp',
  'signal',
  'document',
  'doc',
  'untitled',
  'new',
};

/// Whether [name] is only numbers, hashes and camera words — a name a
/// device gave the file rather than one a person did.
@visibleForTesting
bool isMachineName(String name) {
  final tokens = name
      .toLowerCase()
      .split(RegExp(r'[\s_\-.()]+'))
      .where((t) => t.isNotEmpty);
  return tokens.every(
    (t) =>
        RegExp(r'^\d+$').hasMatch(t) ||
        _deviceWords.contains(t) ||
        RegExp(r'^wa\d+$').hasMatch(t) ||
        // A hash or a uuid segment — `77b0` as much as `3f2a9c1e`. The
        // digit is what keeps "cafe" and "bead" out of it.
        (t.length >= 4 &&
            RegExp(r'\d').hasMatch(t) &&
            RegExp(r'^[0-9a-f]+$').hasMatch(t)),
  );
}

/// Separators to spaces, and timestamps out: "Screenshot_20260920-101010
/// _Chrome" is "Screenshot Chrome". Short numbers stay — "Chapter 12" and
/// "v2.0" are part of the name.
String _tidy(String name) => name
    .split(RegExp(r'[\s_\-]+'))
    .where((t) => t.isNotEmpty && !RegExp(r'^\d{6,}$').hasMatch(t))
    .join(' ');

String _capitalised(String s) {
  if (s.isEmpty) return s;
  final first = s[0];
  return first.toLowerCase() == first && first.toUpperCase() != first
      ? '${first.toUpperCase()}${s.substring(1)}'
      : s;
}

String _clip(String s, int max) =>
    s.length <= max ? s : '${s.substring(0, max - 1).trimRight()}…';

/// What a memory is, as a chip names it.
String _kind(MemoryType type) => switch (type) {
  MemoryType.pdf => 'PDF',
  MemoryType.document => 'Document',
  MemoryType.photo => 'Photo',
  MemoryType.screenshot => 'Screenshot',
  MemoryType.video => 'Video',
  MemoryType.audio => 'Recording',
  MemoryType.voiceNote => 'Voice note',
  MemoryType.link => 'Link',
  MemoryType.text || MemoryType.note => 'Note',
  MemoryType.file => 'File',
};

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// "23 Sep". From a table, not `DateFormat`: the app never initialises
/// intl's date data, and `DateFormat` throws without it.
String _day(DateTime at) {
  final local = at.toLocal();
  return '${local.day} ${_months[local.month - 1]}';
}

String _question(MemoryType type, String name) {
  final n = _clip(name, 40);
  return switch (type) {
    MemoryType.audio || MemoryType.voiceNote => 'What was said in $n?',
    MemoryType.photo || MemoryType.screenshot => 'What does $n show?',
    MemoryType.link => 'What does $n say?',
    _ => 'Summarise $n',
  };
}

/// The question for a file with no name worth saying: its kind and its day.
String _aboutUnnamed(MemoryType type, String day) {
  final kind = type == MemoryType.pdf ? 'PDF' : _kind(type).toLowerCase();
  return switch (type) {
    MemoryType.audio ||
    MemoryType.voiceNote => 'What was said in the $kind from $day?',
    MemoryType.photo ||
    MemoryType.screenshot => 'What does the $kind from $day show?',
    MemoryType.link => 'What does the link from $day say?',
    _ => 'Summarise the $kind from $day',
  };
}

/// Loads home's suggestions once, when home opens.
@injectable
class SuggestionsCubit extends Cubit<List<Suggestion>>
    with SafeEmit<List<Suggestion>> {
  SuggestionsCubit(this._memories) : super(const []) {
    load();
  }

  final MemoryRepository _memories;

  Future<void> load() async {
    // Chips from this phone's copy first, so they are there when home is.
    try {
      final cached = await _memories.cachedMemories(limit: 12);
      if (cached != null) emit(suggestionsFrom(cached.items));
    } on Object {
      // No head start.
    }
    try {
      // More than three, because the newest few may still be indexing.
      final page = await _memories.fetchMemories(limit: 12);
      emit(suggestionsFrom(page.items));
    } on Object {
      // Suggestions are a convenience. A failed read leaves home without
      // them rather than showing an error where a heading should be.
    }
  }
}
