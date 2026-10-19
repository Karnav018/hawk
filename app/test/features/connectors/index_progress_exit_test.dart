import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/core/error/app_exception.dart';
import 'package:knowra/src/features/connectors/domain/entities/index_job.dart';
import 'package:knowra/src/features/connectors/presentation/bloc/index_progress_cubit.dart';

/// QA-002. Screen 3L is reached by `pushReplacement`, so there is no back
/// stack to escape into — its Continue button is the only exit. That button
/// was gated on progress arriving, which makes any failure a dead end: a
/// refused stream, a deleted job, a worker that died before its first
/// progress write.
void main() {
  IndexProgressState state({
    IndexJob? job,
    bool isLoading = false,
    AppException? exception,
  }) =>
      IndexProgressState(job: job, isLoading: isLoading, exception: exception);

  IndexJob job({
    IndexJobState phase = IndexJobState.processing,
    int processed = 0,
    String? error,
  }) => IndexJob(id: 'j', state: phase, processed: processed, error: error);

  group('canLeave', () {
    test('false only while genuinely still starting', () {
      expect(state(isLoading: true).canLeave, isFalse);
      expect(state(job: job()).canLeave, isFalse);
    });

    test('true once anything has landed', () {
      expect(state(job: job(processed: 1)).canLeave, isTrue);
    });

    test('true when the stream was refused', () {
      // Previously invisible *and* inescapable.
      expect(
        state(exception: const AppException.unauthorized()).canLeave,
        isTrue,
      );
    });

    test('true when the job document is gone', () {
      // The repository filters non-existent docs, so a deleted job closes the
      // stream without emitting. `onDone` has to settle loading or the screen
      // spins forever.
      expect(state().canLeave, isTrue);
    });

    test('true when the job itself failed', () {
      expect(state(job: job(phase: IndexJobState.failed)).canLeave, isTrue);
    });
  });

  group('failure surfacing', () {
    test('a stream error is shown, not swallowed', () {
      final s = state(exception: const AppException.unauthorized());
      expect(s.failure, isNotNull);
      expect(s.hasFailed, isTrue);
    });

    test('a job error is shown', () {
      expect(state(job: job(error: 'token expired')).failure, 'token expired');
    });

    test('a healthy job reports no failure', () {
      final s = state(job: job(processed: 5));
      expect(s.failure, isNull);
      expect(s.hasFailed, isFalse);
    });
  });
}
