import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/core/feedback/snack.dart';
import 'package:knowra/src/core/feedback/snack_controller.dart';

Snack _confirm(String message) => Snack.confirmation(message: message);
Snack _progress(double fraction) =>
    Snack.progress(message: 'Reading', fraction: fraction);

void main() {
  late SnackController controller;

  setUp(() => controller = SnackController());
  tearDown(() => controller.dispose());

  test('shows the first snack immediately', () {
    controller.show(_confirm('Saved'));
    expect(controller.current, isA<ConfirmationSnack>());
  });

  test('a second snack queues rather than stomping the first', () {
    controller
      ..show(_confirm('Saved'))
      ..show(_confirm('Indexed'));

    // Two events firing together must both be readable; the second is usually
    // still worth seeing.
    expect((controller.current! as ConfirmationSnack).message, 'Saved');
    expect(controller.queued, hasLength(1));
  });

  test('dismissing advances the queue', () {
    controller
      ..show(_confirm('Saved'))
      ..show(_confirm('Indexed'))
      ..dismiss();

    expect((controller.current! as ConfirmationSnack).message, 'Indexed');
    expect(controller.queued, isEmpty);
  });

  test('auto-dismisses after the hold', () {
    fakeAsync((async) {
      controller.show(
        const Snack.confirmation(message: 'Saved', hold: Duration(seconds: 4)),
      );
      expect(controller.current, isNotNull);

      async.elapse(const Duration(seconds: 4, milliseconds: 1));
      expect(controller.current, isNull);
    });
  });

  test('progress never auto-dismisses', () {
    fakeAsync((async) {
      controller.show(_progress(0.1));
      async.elapse(const Duration(minutes: 5));

      // The only snack allowed to outlive four seconds — it is status, not
      // news.
      expect(controller.current, isA<ProgressSnack>());
    });
  });

  test('a progress update replaces the bar instead of queueing behind it', () {
    controller
      ..show(_progress(0.1))
      ..show(_progress(0.5))
      ..show(_progress(0.9));

    // A job reporting every percent would otherwise fill the queue with
    // hundreds of stale bars.
    expect((controller.current! as ProgressSnack).fraction, 0.9);
    expect(controller.queued, isEmpty);
  });

  test('real news interrupts progress, and progress comes back', () {
    controller
      ..show(_progress(0.4))
      ..show(_confirm('Saved'));

    expect(controller.current, isA<ConfirmationSnack>());

    controller.dismiss();
    expect(controller.current, isA<ProgressSnack>());
    expect((controller.current! as ProgressSnack).fraction, 0.4);
  });

  test('an update arriving behind news replaces the bar waiting there', () {
    // An upload reports every percent; while a confirmation is up those
    // updates must not stack into a queue of stale bars behind it.
    controller
      ..show(_progress(0.2))
      ..show(_confirm('Saved'))
      ..show(_progress(0.3))
      ..show(_progress(0.4));

    expect(controller.queued, hasLength(1));
    expect((controller.queued.single as ProgressSnack).fraction, 0.4);
  });

  test('a finished job clears its bar wherever it is', () {
    controller
      ..show(_confirm('Saved'))
      ..show(_progress(0.9))
      ..dismissPersistent();

    expect(controller.current, isA<ConfirmationSnack>());
    expect(controller.queued, isEmpty);
  });

  test('clearing empties everything', () {
    controller
      ..show(_confirm('a'))
      ..show(_confirm('b'))
      ..clear();

    expect(controller.current, isNull);
    expect(controller.queued, isEmpty);
  });

  group('the design rules, enforced by the type', () {
    test('a snack can carry one action, and there is no way to add two', () {
      // `SnackAction?` rather than a list: nobody can add a second action
      // later without changing the type, which is the point.
      const snack = ConfirmationSnack(message: 'Saved');
      expect(snack.action, isNull);
    });

    test('only progress gets a close button; the rest are swiped away', () {
      expect(_progress(0.5).hasCloseButton, isTrue);
      for (final snack in [
        _confirm('a'),
        const Snack.detail(title: 't', subtitle: 's'),
        const Snack.assistant(message: 'm'),
        Snack.undo(message: 'm', onUndo: () {}),
      ]) {
        expect(snack.hasCloseButton, isFalse, reason: '$snack');
      }
    });

    test('undo holds a second longer than everything else', () {
      expect(
        Snack.undo(message: 'm', onUndo: () {}).autoDismissAfter,
        const Duration(seconds: 5),
      );
      expect(_confirm('m').autoDismissAfter, const Duration(seconds: 4));
    });

    test('every snack announces itself', () {
      expect(
        const Snack.progress(
          message: 'Reading 2 files',
          fraction: 0.64,
        ).semanticLabel,
        'Reading 2 files, 64 percent',
      );
      expect(
        const Snack.detail(title: 'f.docx', subtitle: 'Indexed').semanticLabel,
        'f.docx. Indexed',
      );
    });
  });
}
