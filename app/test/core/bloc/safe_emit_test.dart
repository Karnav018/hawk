import 'package:bloc/bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/core/bloc/safe_emit.dart';

class _Plain extends Cubit<int> {
  _Plain() : super(0);
  void bump() => emit(state + 1);
}

class _Safe extends Cubit<int> with SafeEmit<int> {
  _Safe() : super(0);
  void bump() => emit(state + 1);
}

/// QA-010. Several cubits emit after an await whose success changes the
/// session — and the router disposes the providing route as a direct
/// consequence of that change. Whether the trailing emit lands depends on
/// which async event wins, so the crash was intermittent and surfaced as an
/// unhandled error rather than a race.
void main() {
  test('bloc throws on a late emit by default', () async {
    // The baseline this mixin exists to change. If a future bloc release
    // stops throwing, this failing tells us the mixin became redundant.
    final cubit = _Plain();
    await cubit.close();
    expect(cubit.bump, throwsStateError);
  });

  test('SafeEmit makes it a no-op', () async {
    final cubit = _Safe();
    cubit.bump();
    expect(cubit.state, 1);

    await cubit.close();
    expect(cubit.bump, returnsNormally);
    expect(cubit.state, 1, reason: 'the state must not change after close');
  });

  test('emits normally while open', () async {
    final cubit = _Safe();
    final seen = <int>[];
    final sub = cubit.stream.listen(seen.add);

    cubit.bump();
    cubit.bump();
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();

    expect(seen, [1, 2], reason: 'guarding must not swallow live emits');
    await cubit.close();
  });
}
