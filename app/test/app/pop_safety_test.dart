import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `context.pop()` throws `GoError: There is nothing to pop` on an empty
/// stack, and it crashed a real screen: the profile carried a back button
/// from when it was a pushed route, and v3 made it a tab root — so every tap
/// on it threw.
///
/// The failure is invisible in review because the call is correct *in the
/// flow the author had in mind*. It only breaks in the other one: a guard
/// redirect, a deep link, a `go` that replaced the location instead of
/// stacking on it, or the same screen being reused as a tab root.
///
/// So the rule is mechanical — a bare `pop()` must be guarded, or must go
/// through `popOrGo`, which names where back means when there is no back.
void main() {
  test('no screen pops without knowing there is something to pop', () {
    final offenders = <String>[];

    for (final file
        in Directory('lib/src')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))) {
      final lines = file.readAsLinesSync();

      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trimLeft();
        // Prose mentions the call while explaining why it is dangerous.
        if (line.startsWith('//') || line.startsWith('///')) continue;
        if (!line.contains('context.pop()')) continue;

        // The guard may be on this line (a ternary) or just above it (an
        // `if`). Two lines of lookback covers both without matching a
        // `canPop` that belongs to some other statement entirely.
        final window = lines.sublist(i > 1 ? i - 2 : 0, i + 1).join('\n');
        if (window.contains('canPop')) continue;

        offenders.add('${file.path}:${i + 1}');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Unguarded context.pop() — wrap in `if (context.canPop())` or use '
          '`context.popOrGo(<routeName>)`:\n  ${offenders.join('\n  ')}',
    );
  });

  test('popOrGo is reached through the extension, not reimplemented', () {
    // Four screens had grown their own `canPop() ? pop() : go(...)` ternary
    // before the extension existed. That is fine — it is the same logic —
    // but a fifth copy is a sign the helper is not discoverable, so this
    // keeps the count visible rather than letting it drift upwards.
    final copies = <String>[];

    for (final file
        in Directory('lib/src')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))) {
      final source = file.readAsStringSync();
      if (source.contains('canPop()') &&
          source.contains('context.pop()') &&
          !source.contains('popOrGo')) {
        copies.add(file.path.split('/').last);
      }
    }

    expect(
      copies.length,
      lessThanOrEqualTo(5),
      reason:
          'Hand-rolled pop-or-go in: ${copies.join(', ')}. Prefer '
          'context.popOrGo(<routeName>).',
    );
  });
}
