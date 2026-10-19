import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';

import 'snack.dart';

/// Owns which snack is on screen, and for how long.
///
/// A queue rather than a stack: two events firing together must not stomp on
/// each other, and the second one is usually still worth reading. Persistent
/// snacks (progress) jump the queue and stay until replaced or dismissed —
/// they are status, not news.
@lazySingleton
class SnackController extends ChangeNotifier {
  final _queue = <Snack>[];
  Snack? _current;
  Timer? _timer;

  Snack? get current => _current;

  /// Everything waiting behind the current one. Exposed for tests.
  @visibleForTesting
  List<Snack> get queued => List.unmodifiable(_queue);

  void show(Snack snack) {
    if (_current == null) {
      _present(snack);
      return;
    }

    // A progress update replaces a progress bar rather than queueing behind
    // it — otherwise a job reporting every percent would fill the queue with
    // hundreds of stale bars.
    if (snack is ProgressSnack && _current is ProgressSnack) {
      _present(snack);
      return;
    }

    // Something persistent is showing and real news arrives: the news wins,
    // and the persistent bar returns underneath it.
    if (_current!.isPersistent && !snack.isPersistent) {
      _queue.insert(0, _current!);
      _present(snack);
      return;
    }

    // News is showing and a progress update arrives: it replaces the bar
    // already waiting behind the news, for the same reason as above.
    if (snack is ProgressSnack) {
      final waiting = _queue.indexWhere((s) => s is ProgressSnack);
      if (waiting >= 0) {
        _queue[waiting] = snack;
        return;
      }
    }

    _queue.add(snack);
  }

  /// Dismiss whatever is showing and move on.
  void dismiss() {
    _timer?.cancel();
    _timer = null;

    if (_queue.isNotEmpty) {
      _present(_queue.removeAt(0));
    } else {
      _current = null;
      notifyListeners();
    }
  }

  /// Remove a persistent snack that is no longer true — a finished upload —
  /// whether or not it is the one currently showing.
  void dismissPersistent() {
    _queue.removeWhere((snack) => snack.isPersistent);
    if (_current?.isPersistent ?? false) {
      dismiss();
    } else {
      notifyListeners();
    }
  }

  void clear() {
    _timer?.cancel();
    _timer = null;
    _queue.clear();
    _current = null;
    notifyListeners();
  }

  void _present(Snack snack) {
    _timer?.cancel();
    _current = snack;
    notifyListeners();

    final hold = snack.autoDismissAfter;
    if (hold != null) _timer = Timer(hold, dismiss);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
