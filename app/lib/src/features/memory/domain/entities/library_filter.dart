import 'memory_enums.dart';

/// What the Library's Recent list is narrowed to.
///
/// Groups, not raw [MemoryType]s: someone looking for "the photo" neither
/// knows nor cares whether it was captured as a photo or a screenshot, and
/// "audio" is a recording and a dictated note alike. Each group is a set the
/// repository turns into one `type in […]` query.
enum LibraryFilter {
  all('All', {}),
  docs('Docs', {MemoryType.pdf, MemoryType.document, MemoryType.file}),
  images('Images', {MemoryType.photo, MemoryType.screenshot}),
  audio('Audio', {MemoryType.audio, MemoryType.voiceNote}),
  notes('Notes', {MemoryType.note, MemoryType.text}),
  links('Links', {MemoryType.link}),
  video('Video', {MemoryType.video});

  const LibraryFilter(this.label, this.types);

  final String label;

  /// The kinds this group shows. Empty means no narrowing.
  final Set<MemoryType> types;

  bool get isAll => types.isEmpty;
}
