import 'package:json_annotation/json_annotation.dart';

/// Re-exported so nothing in the memory feature had to change when
/// [StorageProvider] moved to `connectors`, where the dependency belongs.
export '../../../connectors/domain/entities/storage_provider.dart'
    show StorageProvider;

/// What the user captured — episodic memory (architecture §19).
@JsonEnum(fieldRename: FieldRename.snake)
enum MemoryType {
  text,
  note,
  link,
  pdf,
  document,
  screenshot,
  photo,
  video,
  audio,
  voiceNote,
  file;

  /// Unknown values from a newer backend degrade to [file] instead of throwing.
  static MemoryType parse(String? raw) => switch (raw) {
    'text' => text,
    'note' => note,
    'link' => link,
    'pdf' => pdf,
    'document' => document,
    'screenshot' => screenshot,
    'photo' => photo,
    'video' => video,
    'audio' => audio,
    'voice_note' => voiceNote,
    _ => file,
  };

  /// The value stored in Firestore.
  ///
  /// snake_case, matching what the Python pipeline writes — `name` would give
  /// `voiceNote`, and the two sides would silently disagree about one value.
  String get wireName => this == voiceNote ? 'voice_note' : name;

  /// Whether the original *is* the content, rather than a container the
  /// text was pulled out of.
  ///
  /// The viewer reads the index, not the file — which is right for a PDF,
  /// where the extracted text is what the answers were built from. For a
  /// photo it is not: the index holds a *description* of the picture and
  /// the words in it, and a screen that printed that instead of the picture
  /// once said "nothing readable in this file" about a picture that was
  /// perfectly fine. These types show the original instead.
  bool get isVisual => this == photo || this == screenshot;

  /// A recording: screen 2H plays the original above its transcript. A
  /// dictated note (2F) is `voiceNote` too, and simply has nothing to play.
  bool get isAudio => this == audio || this == voiceNote;

  /// Display name. Spelled out here rather than derived from [name], which
  /// would render `voiceNote` as "VOICENOTE" once upper-cased.
  String get label => switch (this) {
    text => 'Text',
    note => 'Note',
    link => 'Link',
    pdf => 'PDF',
    document => 'Document',
    screenshot => 'Screenshot',
    photo => 'Photo',
    video => 'Video',
    audio => 'Audio',
    voiceNote => 'Voice note',
    file => 'File',
  };
}

/// The ingestion state machine (architecture §22).
///
/// `uploaded → processing → extracted → enriching → embedding → indexed →
/// ready`, with `failed` reachable from anywhere.
@JsonEnum(fieldRename: FieldRename.snake)
enum ProcessingStatus {
  uploaded,
  processing,
  extracted,
  enriching,
  embedding,
  indexed,
  ready,
  failed;

  static ProcessingStatus parse(String? raw) => switch (raw) {
    'uploaded' => uploaded,
    'processing' => processing,
    'extracted' => extracted,
    'enriching' => enriching,
    'embedding' => embedding,
    'indexed' => indexed,
    'ready' => ready,
    'failed' => failed,
    _ => processing,
  };

  /// Nothing more will happen without user action.
  bool get isTerminal => this == ready || this == failed;

  /// Still moving through the pipeline — the UI should show progress.
  bool get isWorking => !isTerminal;

  /// Roughly how far through the pipeline a memory in this state has come,
  /// 0..1.
  ///
  /// Screen 1K draws a number inside an accent dot on a row that is still
  /// indexing, and there is nothing else to draw it from: the pipeline writes
  /// a *stage*, not a percentage, because none of its stages know how long
  /// the next one will take. So the stage is the progress, and this is the
  /// one place that mapping is written down.
  ///
  /// The steps are deliberately uneven. Extraction is the long pole on a
  /// scanned PDF and embedding is the long pole on a transcript, so an even
  /// seven-way split would sit at 43% through most of the work on one kind of
  /// file and at 43% through almost none of it on another. These are weighted
  /// by what the pipeline actually spends its time on.
  ///
  /// It is an estimate and the UI must not pretend otherwise — hence a dot
  /// with a number in it rather than a bar that claims to be measuring
  /// something.
  double get indexFraction => switch (this) {
    uploaded => 0.05,
    processing => 0.20,
    extracted => 0.45,
    enriching => 0.62,
    embedding => 0.80,
    indexed => 0.95,
    ready || failed => 1.0,
  };
}
