import '../../../memory/domain/entities/memory_enums.dart';
import 'answer.dart';

/// A question that found something, kept so it can be opened again for free.
///
/// Reopening one is a replay of what was already on screen — the answer and
/// the files it cited — not a new question. It never reaches the server, so
/// it never spends an ask: somebody going back to what they found a minute
/// ago has not asked anything.
class RecentFind {
  const RecentFind({
    required this.question,
    required this.answer,
    required this.foundAt,
    this.matches = const [],
  });

  factory RecentFind.fromJson(Map<String, dynamic> json) => RecentFind(
    question: json['question'] as String? ?? '',
    foundAt:
        DateTime.tryParse(json['foundAt'] as String? ?? '') ?? DateTime.now(),
    answer: _answerFrom(
      Map<String, dynamic>.from(json['answer'] as Map? ?? const {}),
    ),
    matches: [
      for (final raw in (json['matches'] as List? ?? const []))
        _matchFrom(Map<String, dynamic>.from(raw as Map)),
    ],
  );

  final String question;
  final Answer answer;
  final List<Match> matches;
  final DateTime foundAt;

  /// The kind of the file the answer leaned on first — the chip's icon.
  MemoryType get leadType =>
      answer.citations.firstOrNull?.type ??
      matches.firstOrNull?.type ??
      MemoryType.file;

  Map<String, dynamic> toJson() => {
    'question': question,
    'foundAt': foundAt.toIso8601String(),
    'answer': {
      'id': answer.id,
      'question': answer.question,
      'answered': answer.answered,
      'confidence': answer.confidence.name,
      'conversationId': answer.conversationId,
      'answeredAt': answer.answeredAt?.toIso8601String(),
      'blocks': [
        for (final b in answer.blocks)
          {'text': b.text, 'citations': b.citations, 'isLead': b.isLead},
      ],
      'citations': [
        for (final c in answer.citations)
          {
            'memoryId': c.memoryId,
            'index': c.index,
            'title': c.title,
            'type': c.type.wireName,
            'locator': c.locator,
            'score': c.score,
            'url': c.url,
            'storagePath': c.storagePath,
          },
      ],
    },
    'matches': [
      for (final m in matches)
        {
          'memoryId': m.memoryId,
          'chunkId': m.chunkId,
          'title': m.title,
          'type': m.type.wireName,
          'excerpt': m.excerpt,
          'score': m.score,
          'locator': m.locator,
          'url': m.url,
          'storagePath': m.storagePath,
        },
    ],
  };

  static Answer _answerFrom(Map<String, dynamic> a) => Answer(
    id: a['id'] as String? ?? '',
    question: a['question'] as String? ?? '',
    answered: a['answered'] as bool? ?? true,
    confidence: AnswerConfidence.parse(a['confidence'] as String?),
    conversationId: a['conversationId'] as String?,
    answeredAt: DateTime.tryParse(a['answeredAt'] as String? ?? ''),
    blocks: [
      for (final raw in (a['blocks'] as List? ?? const []))
        AnswerBlock(
          text: (raw as Map)['text'] as String? ?? '',
          citations: [
            for (final c in (raw['citations'] as List? ?? const []))
              (c as num).toInt(),
          ],
          isLead: raw['isLead'] as bool? ?? false,
        ),
    ],
    citations: [
      for (final raw in (a['citations'] as List? ?? const []))
        Citation(
          memoryId: (raw as Map)['memoryId'] as String? ?? '',
          index: (raw['index'] as num?)?.toInt() ?? 0,
          title: raw['title'] as String? ?? 'Untitled',
          type: MemoryType.parse(raw['type'] as String?),
          locator: raw['locator'] as String?,
          score: (raw['score'] as num?)?.toInt() ?? 0,
          url: raw['url'] as String?,
          storagePath: raw['storagePath'] as String?,
        ),
    ],
  );

  static Match _matchFrom(Map<String, dynamic> m) => Match(
    memoryId: m['memoryId'] as String? ?? '',
    chunkId: m['chunkId'] as String? ?? '',
    title: m['title'] as String? ?? 'Untitled',
    type: MemoryType.parse(m['type'] as String?),
    excerpt: m['excerpt'] as String? ?? '',
    score: (m['score'] as num?)?.toInt() ?? 0,
    locator: m['locator'] as String?,
    url: m['url'] as String?,
    storagePath: m['storagePath'] as String?,
  );
}
