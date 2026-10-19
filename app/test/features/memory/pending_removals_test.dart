import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/core/error/app_exception.dart';
import 'package:knowra/src/core/feedback/snack.dart';
import 'package:knowra/src/core/feedback/snack_controller.dart';
import 'package:knowra/src/features/memory/domain/repositories/memory_repository.dart';
import 'package:knowra/src/features/memory/presentation/bloc/pending_removals.dart';
import 'package:mocktail/mocktail.dart';

class _Memories extends Mock implements MemoryRepository {}

/// Removing a memory — the one path that uses the undo snack (2E). Nothing
/// is deleted until its five seconds are up.
void main() {
  late _Memories memories;
  late SnackController snacks;
  late PendingRemovals removals;

  setUp(() {
    memories = _Memories();
    snacks = SnackController();
    removals = PendingRemovals(memories, snacks);
    when(() => memories.deleteMemory(any())).thenAnswer((_) async {});
  });

  test('hides at once, offers Undo, and deletes when the window closes', () {
    fakeAsync((time) {
      removals.remove('m1');
      expect(removals.hidden, {'m1'});
      expect(snacks.current, isA<UndoSnack>());
      expect((snacks.current! as UndoSnack).message, 'Memory removed');
      verifyNever(() => memories.deleteMemory(any()));

      time.elapse(const Duration(seconds: 4));
      verifyNever(() => memories.deleteMemory(any()));

      time.elapse(const Duration(seconds: 1));
      time.flushMicrotasks();
      verify(() => memories.deleteMemory('m1')).called(1);
      // Still hidden: the Library's page of rows has not reloaded yet.
      expect(removals.hidden, {'m1'});
    });
  });

  test('Undo cancels the delete and puts the row back', () {
    fakeAsync((time) {
      removals.remove('m1');
      (snacks.current! as UndoSnack).onUndo();
      expect(removals.hidden, isEmpty);

      time.elapse(const Duration(seconds: 10));
      verifyNever(() => memories.deleteMemory(any()));
    });
  });

  test('a delete that fails says so and brings the row back', () {
    when(
      () => memories.deleteMemory(any()),
    ).thenThrow(const AppException.network());
    fakeAsync((time) {
      removals.remove('m1');
      snacks.clear();
      time.elapse(const Duration(seconds: 5));
      time.flushMicrotasks();

      expect(removals.hidden, isEmpty);
      final island = snacks.current! as DetailSnack;
      expect(island.title, 'Could not remove it');
      expect(island.mark, SnackMark.failure);
    });
  });
}
