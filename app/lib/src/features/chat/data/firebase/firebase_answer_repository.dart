import 'package:cloud_functions/cloud_functions.dart';
import 'package:injectable/injectable.dart';

import '../../../../core/error/app_exception.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../memory/domain/entities/memory_enums.dart';
import '../../domain/entities/answer.dart';
import '../../domain/repositories/answer_repository.dart';

/// [AnswerRepository] over the `ask` callable.
///
/// A callable rather than a Firestore read, for the reason architecture §47
/// gives about not letting the model enforce access control: retrieval has to
/// happen somewhere the caller cannot influence which documents are in scope.
/// It is also the only place with the model's API key.
///
/// `ask` is currently `UNIMPLEMENTED` on the server — deliberately, rather
/// than returning a plausible answer built from nothing. This class is written
/// against the shape it *will* return so the screens are real, and it
/// surfaces the server's refusal verbatim instead of inventing content.
/// Registered as itself, not as [AnswerRepository]: the app's repository is
/// `LocalAnswerRepository`, which retrieves on the phone and uses this for
/// the model calls — and for everything while the local index is still
/// being built.
@lazySingleton
class FirebaseAnswerRepository implements AnswerRepository {
  FirebaseAnswerRepository(this._functions, this._logger);

  final FirebaseFunctions _functions;
  final AppLogger _logger;

  @override
  Future<MatchResults> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return (matches: const <Match>[], signals: const QuerySignals());
    }

    try {
      final result = await _functions.httpsCallable('search').call<Object?>({
        'query': trimmed,
        'tzOffsetMinutes': _tzOffsetMinutes,
      });

      final data = result.data;
      if (data is! Map) throw const AppException.parsing();
      final map = data.map((k, v) => MapEntry(k.toString(), v));

      return (
        matches: [
          for (final raw in (map['matches'] as List? ?? const []))
            Match(
              memoryId: (raw as Map)['memoryId'] as String? ?? '',
              chunkId: raw['chunkId'] as String? ?? '',
              title: raw['title'] as String? ?? 'Untitled',
              type: MemoryType.parse(raw['type'] as String?),
              excerpt: raw['excerpt'] as String? ?? '',
              score: (raw['score'] as num?)?.round() ?? 0,
              locator: raw['locator'] as String?,
              url: raw['url'] as String?,
              storagePath: raw['storagePath'] as String?,
            ),
        ],
        signals: _signals(map['signals']),
      );
    } on FirebaseFunctionsException catch (error, stackTrace) {
      _logger.warning(
        'search failed',
        name: 'chat',
        data: {'code': error.code},
      );
      throw _map(error, stackTrace);
    }
  }

  @override
  Future<Answer> ask(
    String question, {
    String? conversationId,
    List<String> earlier = const [],
  }) => _ask(question, {'conversationId': ?conversationId});

  /// Answers from passages the phone already chose — see
  /// `LocalAnswerRepository`. The server reads them by id.
  Future<Answer> askWithPassages(
    String question,
    List<({String chunkId, double distance})> passages, {
    String? conversationId,
    QuerySignals signals = const QuerySignals(),
  }) => _ask(question, {
    'conversationId': ?conversationId,
    'passages': [
      for (final p in passages) {'chunkId': p.chunkId, 'distance': p.distance},
    ],
  });

  /// The phone's zone, so the server reads "yesterday" as the user's
  /// yesterday when it parses the question itself.
  static int get _tzOffsetMinutes => DateTime.now().timeZoneOffset.inMinutes;

  Future<Answer> _ask(String question, Map<String, Object?> extra) async {
    final trimmed = question.trim();
    if (trimmed.isEmpty) {
      throw const AppException.badRequest(message: 'Ask something first.');
    }

    final started = DateTime.now();
    try {
      final result = await _functions.httpsCallable('ask').call<Object?>({
        'question': trimmed,
        'tzOffsetMinutes': _tzOffsetMinutes,
        ...extra,
      });

      final data = result.data;
      if (data is! Map) throw const AppException.parsing();
      return _answer(
        trimmed,
        data.map((k, v) => MapEntry(k.toString(), v)),
        // Measured client-side as a fallback: what the user experiences is
        // the round trip, not the server's own stopwatch.
        fallbackLatency: DateTime.now().difference(started),
      );
    } on FirebaseFunctionsException catch (error, stackTrace) {
      _logger.warning('ask failed', name: 'chat', data: {'code': error.code});
      throw _map(error, stackTrace);
    }
  }

  AppException _map(
    FirebaseFunctionsException error,
    StackTrace stackTrace,
  ) => switch (error.code) {
    'unauthenticated' => const AppException.unauthorized(),
    // The daily allowance. Carries the server's message because it names the
    // limit and when it resets, and distinguishes a free-tier paywall from a
    // fair-use ceiling — which a generic string cannot.
    'resource-exhausted' => AppException.badRequest(
      message: error.message ?? 'That is all your questions for today.',
    ),
    // A model or key problem. Retrying will not help.
    'failed-precondition' => AppException.badRequest(
      message: error.message ?? 'Answering is unavailable right now.',
    ),
    'unavailable' => const AppException.network(),
    'deadline-exceeded' => const AppException.timeout(),
    _ => AppException.unknown(cause: error, stackTrace: stackTrace),
  };

  QuerySignals _signals(Object? raw) {
    if (raw is! Map) return const QuerySignals();
    return QuerySignals(
      type: raw['type'] as String?,
      after: raw['after'] as String?,
      before: raw['before'] as String?,
      rewritten: raw['rewritten'] as bool? ?? false,
    );
  }

  Answer _answer(
    String question,
    Map<String, dynamic> data, {
    required Duration fallbackLatency,
  }) {
    final citations = <Citation>[
      for (final (i, raw) in (data['citations'] as List? ?? const []).indexed)
        Citation(
          memoryId: (raw as Map)['memoryId'] as String? ?? '',
          index: (raw['index'] as num?)?.toInt() ?? i + 1,
          title: raw['title'] as String? ?? 'Untitled',
          type: MemoryType.parse(raw['type'] as String?),
          locator: raw['locator'] as String?,
          score: (raw['score'] as num?)?.round() ?? 0,
          url: raw['url'] as String?,
          storagePath: raw['storagePath'] as String?,
          updatedAt: DateTime.tryParse(raw['updatedAt'] as String? ?? ''),
        ),
    ];

    final serverMs = (data['latencyMs'] as num?)?.toInt();

    return Answer(
      id: data['id'] as String? ?? '',
      question: question,
      blocks: [
        for (final (i, raw) in (data['blocks'] as List? ?? const []).indexed)
          AnswerBlock(
            text: (raw as Map)['text'] as String? ?? '',
            citations: [
              for (final c in (raw['citations'] as List? ?? const []))
                (c as num).toInt(),
            ],
            isLead: i == 0,
          ),
      ],
      citations: citations,
      confidence: AnswerConfidence.parse(data['confidence'] as String?),
      conversationId: data['conversationId'] as String?,
      signals: _signals(data['signals']),
      // Defaults true so an older backend that does not send the field is
      // read as "answered", which is what it used to mean.
      answered: data['answered'] as bool? ?? true,
      answeredAt:
          DateTime.tryParse(data['answeredAt'] as String? ?? '') ??
          DateTime.now(),
      latency: serverMs != null
          ? Duration(milliseconds: serverMs)
          : fallbackLatency,
    );
  }
}
