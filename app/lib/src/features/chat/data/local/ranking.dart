import 'dart:math' as math;
import 'dart:typed_data';

/// The ranking the server used to do, done on the phone.
///
/// A port of `retrieval.py`'s pure half: the nearest-neighbour pass over the
/// device's vectors, a keyword pass over those candidates, and Reciprocal
/// Rank Fusion of the two. Same constants, so a result on the phone is the
/// result the server would have produced from the same vectors.

/// How many chunks the vector stage pulls before rescoring. Generous on
/// purpose — this is the only stage that can bring a passage into play.
const candidates = 60;

/// How many survive into the model's context.
const contextSize = 8;

/// RRF's damping constant, from the original paper.
const rrfK = 60;

const _stop = {
  'a', 'an', 'and', 'are', 'as', 'at', 'be', 'by', 'did', 'do', 'does', //
  'for', 'from', 'had', 'has', 'have', 'how', 'i', 'if', 'in', 'is', 'it',
  'its', 'me', 'my', 'of', 'on', 'or', 'our', 'so', 'than', 'that', 'the',
  'their', 'them', 'then', 'there', 'these', 'they', 'this', 'to', 'was',
  'we', 'were', 'what', 'when', 'where', 'which', 'who', 'why', 'will',
  'with', 'you', 'your',
};

final _word = RegExp(r"[a-z0-9][a-z0-9'./-]*");

/// A candidate passage: what the lexical stage and fusion need.
typedef Candidate = ({String id, String text, double distance});

/// One ranked passage, in the order the answer will be built from.
class Ranked {
  const Ranked({
    required this.id,
    required this.distance,
    required this.vectorRank,
    required this.lexicalRank,
    required this.score,
  });

  final String id;

  /// Cosine distance from the query. 0 is identical, 2 is opposite.
  final double distance;
  final int vectorRank;

  /// 0 means the keyword stage did not rank it at all.
  final int lexicalRank;
  final double score;

  /// 0–100, from the cosine distance rather than the fused score — the fused
  /// score is a rank artefact with no meaning outside this result set.
  int get relevance => ((1.0 - distance / 2.0) * 100).round().clamp(0, 100);
}

List<String> terms(String text) => [
  for (final m in _word.allMatches(text.toLowerCase()))
    if (!_stop.contains(m[0]!) && m[0]!.length > 1) m[0]!,
];

/// Score candidates by term overlap, weighted by term rarity — BM25's idea
/// without its bookkeeping, computed over the candidate set.
Map<String, double> lexical(String query, List<Candidate> passages) {
  final queryTerms = terms(query).toSet();
  if (queryTerms.isEmpty) return const {};

  final docTerms = {for (final p in passages) p.id: terms(p.text)};
  final df = <String, int>{};
  for (final ts in docTerms.values) {
    for (final t in ts.toSet()) {
      if (queryTerms.contains(t)) df[t] = (df[t] ?? 0) + 1;
    }
  }

  final n = passages.length;
  final scores = <String, double>{};
  for (final MapEntry(key: id, value: ts) in docTerms.entries) {
    if (ts.isEmpty) continue;
    final counts = <String, int>{};
    for (final t in ts) {
      if (queryTerms.contains(t)) counts[t] = (counts[t] ?? 0) + 1;
    }
    var score = 0.0;
    for (final MapEntry(key: t, value: count) in counts.entries) {
      final idf = math.log(1 + n / (1 + (df[t] ?? 0)));
      // Saturating term frequency: the fifth occurrence of a word says much
      // less than the second.
      final tf = count / (count + 1.5);
      score += idf * tf;
    }
    // Length normalisation, so a long chunk does not win on volume alone.
    scores[id] = score / math.sqrt(ts.length);
  }
  return scores;
}

/// Reciprocal Rank Fusion over two rankings. A passage both rank highly
/// wins; one that only the keyword stage likes still places.
Map<String, double> fuse(
  List<String> vectorOrder,
  List<String> lexicalOrder, {
  int k = rrfK,
}) {
  final scores = <String, double>{};
  for (final order in [vectorOrder, lexicalOrder]) {
    for (final (i, id) in order.indexed) {
      scores[id] = (scores[id] ?? 0) + 1.0 / (k + i + 1);
    }
  }
  return scores;
}

/// The server's whole pure ranking: candidates in vector order in, the top
/// [limit] passages out.
List<Ranked> rank(
  String query,
  List<Candidate> inVectorOrder, {
  int limit = contextSize,
}) {
  if (inVectorOrder.isEmpty) return const [];
  final vectorOrder = [for (final c in inVectorOrder) c.id];
  final lexicalScores = lexical(query, inVectorOrder);
  final lexicalOrder =
      (lexicalScores.entries.where((e) => e.value > 0).toList()
            ..sort((a, b) => b.value.compareTo(a.value)))
          .map((e) => e.key)
          .toList();

  final fused = fuse(vectorOrder, lexicalOrder);
  final byId = {for (final c in inVectorOrder) c.id: c};
  final vectorRank = {for (final (i, id) in vectorOrder.indexed) id: i + 1};
  final lexicalRank = {for (final (i, id) in lexicalOrder.indexed) id: i + 1};

  final ranked = fused.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return [
    for (final entry in ranked.take(limit))
      Ranked(
        id: entry.key,
        distance: byId[entry.key]!.distance,
        vectorRank: vectorRank[entry.key] ?? 0,
        lexicalRank: lexicalRank[entry.key] ?? 0,
        score: entry.value,
      ),
  ];
}

/// Cosine distance between two unit vectors: `1 - dot`.
///
/// Both sides are unit length — `gemini.py` re-normalises the truncated
/// embedding, and the query comes from the same call — so the dot product
/// is the cosine and no norms are needed per comparison.
double cosineDistance(Float32List a, Float32List b) {
  var dot = 0.0;
  for (var i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
  }
  return (1.0 - dot).clamp(0.0, 2.0);
}
