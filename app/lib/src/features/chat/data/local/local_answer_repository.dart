import 'package:injectable/injectable.dart';

import '../../../../core/error/app_exception.dart';
import '../../../memory/domain/entities/memory.dart';
import '../../../memory/domain/repositories/memory_repository.dart';
import '../../../memory/presentation/widgets/memory_row.dart';
import '../../domain/entities/answer.dart';
import '../../domain/repositories/answer_repository.dart';
import '../firebase/firebase_answer_repository.dart';
import 'index_sync.dart';
import 'local_index.dart';
import 'local_query.dart';
import 'ranking.dart';

/// [AnswerRepository] with retrieval on the phone.
///
/// Search never leaves the device except to embed the question: the
/// nearest-neighbour pass, the keyword pass and the fusion all run over the
/// vectors in [LocalIndex]. Asking sends the server the *ids* of the passages
/// this ranked highest, and the server answers from those — it reads them by
/// id, so a device can only ever choose among the user's own, still
/// recallable chunks; it can never supply text.
///
/// Until the local index is complete — the first minutes after install, or
/// on a second device — both calls fall back to the server, which still
/// searches its own copy of the vectors for as long as it has one.
@LazySingleton(as: AnswerRepository)
class LocalAnswerRepository implements AnswerRepository {
  LocalAnswerRepository(this._remote, this._sync, this._index, this._memories);

  final FirebaseAnswerRepository _remote;
  final IndexSync _sync;
  final LocalIndex _index;
  final MemoryRepository _memories;

  @override
  Future<MatchResults> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return (matches: const <Match>[], signals: const QuerySignals());
    }
    if (!_sync.isReady) return _remote.search(trimmed);

    final parsed = understandLocally(trimmed);
    final ranked = await _retrieve(trimmed, parsed.search, parsed);
    return (matches: await _matches(ranked), signals: parsed.signals);
  }

  @override
  Future<Answer> ask(
    String question, {
    String? conversationId,
    List<String> earlier = const [],
  }) async {
    final trimmed = question.trim();
    if (trimmed.isEmpty) {
      throw const AppException.badRequest(message: 'Ask something first.');
    }
    if (!_sync.isReady) {
      return _remote.ask(
        trimmed,
        conversationId: conversationId,
        earlier: earlier,
      );
    }

    final parsed = understandLocally(trimmed);
    // A follow-up is retrieved with its context folded in but answered as
    // asked — the same split the server made when it retrieved.
    final ranked = await _retrieve(
      trimmed,
      contextualise(parsed.search, earlier),
      parsed,
    );
    return _remote.askWithPassages(
      trimmed,
      [for (final r in ranked) (chunkId: r.id, distance: r.distance)],
      conversationId: conversationId,
      signals: parsed.signals,
    );
  }

  Future<List<Ranked>> _retrieve(
    String question,
    String embedText,
    LocalQuery parsed,
  ) async {
    final vector = await _sync.embedQuery(embedText);
    final nearest = _index.nearest(vector, parsed);
    return rank(question, [
      for (final n in nearest)
        (id: n.chunk.id, text: n.chunk.text, distance: n.distance),
    ]);
  }

  /// [Match]es for the ranked passages: title and type from the chunk, the
  /// place to open from the memory itself.
  Future<List<Match>> _matches(List<Ranked> ranked) async {
    if (ranked.isEmpty) return const [];
    final chunks = [
      for (final r in ranked) _index[r.id],
    ].whereType<LocalChunk>();
    final ids = {
      for (final c in chunks) c.memoryId,
    }.where((id) => id.isNotEmpty);
    final memories = <String, Memory>{};
    try {
      final found = await _memories
          .watchMemories(ids.toList())
          .first
          .timeout(const Duration(seconds: 4));
      for (final m in found) {
        memories[m.id] = m;
      }
    } on Object {
      // Rows without somewhere to open are still results; the viewer can
      // resolve the original itself.
    }
    return [
      for (final r in ranked)
        if (_index[r.id] case final chunk?)
          Match(
            memoryId: chunk.memoryId,
            chunkId: chunk.id,
            title: memories[chunk.memoryId]?.displayTitle ?? chunk.memoryTitle,
            type: chunk.memoryType,
            excerpt: excerpt(chunk.text),
            score: r.relevance,
            locator: 'part ${chunk.chunkIndex + 1}',
            url: memories[chunk.memoryId] == null
                ? null
                : MemoryRow.originalOf(memories[chunk.memoryId]!).url,
            storagePath: memories[chunk.memoryId]?.storagePath,
          ),
    ];
  }
}

/// A readable fragment for a match row, cut on a word boundary — the
/// server's `_excerpt`.
String excerpt(String text, {int limit = 220}) {
  final clean = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).join(' ');
  if (clean.length <= limit) return clean;
  final cut = clean.substring(0, limit);
  final space = cut.lastIndexOf(' ');
  return '${space > limit ~/ 2 ? cut.substring(0, space) : cut}…';
}
