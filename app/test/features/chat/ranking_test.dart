import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/features/chat/data/local/ranking.dart';

/// The server's ranking, on the phone. The cases are `test_retrieval.py`'s,
/// so the two implementations are held to the same answers.
void main() {
  Candidate c(String id, String text, [double distance = 0.2]) =>
      (id: id, text: text, distance: distance);

  test('a keyword-only hit survives', () {
    // The whole reason hybrid retrieval exists: the vector stage ranks the
    // exact phrase low, the keyword stage rescues it.
    final ranked = rank('SKU-4471 invoice', [
      c('v1', 'general notes about billing'),
      c('v2', 'a meeting about pricing'),
      c('v3', 'invoice for SKU-4471 attached'),
    ]);
    expect(ranked.first.id, 'v3');
    expect(ranked.first.lexicalRank, 1);
  });

  test('agreement wins', () {
    // Both stages like it: it should beat one that only one stage likes.
    final ranked = rank('pricing tiers', [
      c('a', 'pricing tiers for the team plan', 0.1),
      c('b', 'unrelated but nearest by accident', 0.05),
      c('c', 'tiers'),
    ]);
    expect(ranked.first.id, 'a');
  });

  test('rare terms count for more, repetition saturates', () {
    final scores = lexical('lease deposit', [
      c('x', 'lease lease lease lease lease'),
      c('y', 'lease deposit terms'),
      c('z', 'lease'),
    ]);
    // The chunk with the rare term wins outright.
    expect(scores['y']!, greaterThan(scores['x']!));
    expect(scores['y']!, greaterThan(scores['z']!));
    // Five repetitions are worth nowhere near five mentions — saturation
    // and length normalisation together make the repeater score *below*
    // the single mention, exactly as the server's formula does.
    expect(scores['x']!, lessThan(scores['z']!));
    expect(scores['x']!, lessThan(5 * scores['z']!));
  });

  test('a query of only stopwords scores nothing', () {
    expect(lexical('what is the', [c('a', 'what is the plan')]), isEmpty);
  });

  test('relevance maps distance to a percentage and never leaves 0–100', () {
    Ranked at(double d) =>
        Ranked(id: 'x', distance: d, vectorRank: 1, lexicalRank: 0, score: 1);
    expect(at(0).relevance, 100);
    expect(at(0.4).relevance, 80);
    expect(at(2).relevance, 0);
  });

  test('cosine distance of unit vectors is one minus the dot product', () {
    final a = Float32List.fromList([1, 0, 0]);
    final b = Float32List.fromList([0, 1, 0]);
    final c2 = Float32List.fromList([-1, 0, 0]);
    expect(cosineDistance(a, a), closeTo(0, 1e-6));
    expect(cosineDistance(a, b), closeTo(1, 1e-6));
    expect(cosineDistance(a, c2), closeTo(2, 1e-6));
  });

  test('the top of the list is capped at the context size', () {
    final ranked = rank('note', [
      for (var i = 0; i < 20; i++) c('n$i', 'note $i', i / 20),
    ]);
    expect(ranked, hasLength(contextSize));
    expect(ranked.first.id, 'n0');
  });
}
