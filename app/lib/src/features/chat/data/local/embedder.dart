import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:injectable/injectable.dart';

import '../../../../core/error/app_exception.dart';

/// Turns text into vectors for the phone's own index.
///
/// An interface so the model can move: today it is Gemini, reached through
/// `embed_texts`, which returns the vectors and stores nothing. Because each
/// device embeds its own chunks *and* its own questions, swapping this for an
/// on-device model later is a per-device rebuild with no server coordination
/// — the one rule is that a device's documents and its queries go through
/// the same embedder.
abstract interface class Embedder {
  /// Vectors for chunk text, one per input, unit length.
  Future<List<Float32List>> documents(List<String> texts);

  /// The vector for a question. A different task type from [documents];
  /// mixing them measurably hurts recall.
  Future<Float32List> query(String text);

  /// The most texts one [documents] call takes.
  static const batch = 50;

  /// The most characters of one text that get embedded. The server cuts a
  /// longer one to this (`local_index.MAX_TEXT_CHARS`), so sending the rest
  /// buys nothing: the vector is of the head, and the keyword stage still
  /// reads the whole chunk.
  static const maxChars = 8000;
}

@LazySingleton(as: Embedder)
class CallableEmbedder implements Embedder {
  CallableEmbedder(this._functions);

  final FirebaseFunctions _functions;

  @override
  Future<List<Float32List>> documents(List<String> texts) async {
    if (texts.isEmpty) return const [];
    final out = <Float32List>[];
    for (var start = 0; start < texts.length; start += Embedder.batch) {
      final window = texts.sublist(
        start,
        (start + Embedder.batch).clamp(0, texts.length),
      );
      out.addAll(await _call(window, task: 'document'));
    }
    return out;
  }

  @override
  Future<Float32List> query(String text) async =>
      (await _call([text], task: 'query')).single;

  Future<List<Float32List>> _call(
    List<String> texts, {
    required String task,
  }) async {
    try {
      final result = await _functions
          .httpsCallable('embed_texts')
          .call<Object?>({'texts': texts, 'task': task});
      final data = result.data;
      if (data is! Map) throw const AppException.parsing();
      final raw = data['vectors'] as List? ?? const [];
      if (raw.length != texts.length) {
        // A short answer would pair every chunk with somebody else's
        // vector, which is worse than failing.
        throw const AppException.parsing();
      }
      return [
        for (final v in raw)
          Float32List.fromList([
            for (final x in (v as List)) (x as num).toDouble(),
          ]),
      ];
    } on FirebaseFunctionsException catch (error, stackTrace) {
      throw switch (error.code) {
        'unauthenticated' => const AppException.unauthorized(),
        'unavailable' => const AppException.network(),
        'deadline-exceeded' => const AppException.timeout(),
        'failed-precondition' => AppException.badRequest(
          message: error.message ?? 'Indexing is unavailable right now.',
        ),
        // The server's reason, kept: "every text must be a non-empty
        // string" in the log is a fix; "unknown" is an afternoon.
        'invalid-argument' => AppException.badRequest(
          message: error.message ?? 'The server refused these texts.',
        ),
        _ => AppException.unknown(cause: error, stackTrace: stackTrace),
      };
    }
  }
}

/// The cloud's side of the move: deleting the vectors it used to hold.
abstract interface class CloudIndex {
  /// Deletes one page of the signed-in user's cloud vectors. Returns the
  /// cursor for the next page, or null when there is nothing left.
  Future<String?> purge({String? after});
}

@LazySingleton(as: CloudIndex)
class CallableCloudIndex implements CloudIndex {
  CallableCloudIndex(this._functions);

  final FirebaseFunctions _functions;

  @override
  Future<String?> purge({String? after}) async {
    final result = await _functions
        .httpsCallable('purge_cloud_embeddings')
        .call<Object?>({'after': ?after});
    final data = result.data;
    if (data is! Map) return null;
    if (data['done'] == true) return null;
    return data['after'] as String?;
  }
}
