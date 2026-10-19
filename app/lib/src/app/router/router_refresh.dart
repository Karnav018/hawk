import 'dart:async';

import 'package:flutter/foundation.dart';

/// Bridges a stream into go_router's `refreshListenable`.
///
/// go_router only re-evaluates `redirect` when something notifies it, so
/// without this a session change would not move the user until the next
/// navigation — you would be signed out and still looking at your library.
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
