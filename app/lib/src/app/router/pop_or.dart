import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Going back, for a screen that cannot be certain there is a back.
///
/// `context.pop()` throws `GoError: There is nothing to pop` when the stack is
/// empty, and a screen's own code is the worst place to work out whether it
/// is. The same screen is a pushed route in one flow and a tab root in
/// another; a guard redirect and a deep link both arrive with nothing behind
/// them; and `go` replaces the location rather than stacking on it. v2 hit
/// this the moment the profile became a tab — the back button it had carried
/// since it was a pushed screen started throwing on every tap.
///
/// So the question is never "does this screen have a back button" but "where
/// does back *mean* here", and that has an answer even when the stack is
/// empty. Every caller names it.
extension PopOr on BuildContext {
  /// Pops if there is anything to pop, and otherwise goes to [fallbackName].
  ///
  /// [fallbackName] is a route *name*, not a path: names survive a path being
  /// restructured, which is exactly the kind of change that leaves a hard
  /// coded fallback pointing at nothing.
  void popOrGo(String fallbackName) {
    if (canPop()) {
      pop();
    } else {
      goNamed(fallbackName);
    }
  }
}
