import 'package:flutter/widgets.dart';

import '../../domain/repositories/auth_repository.dart';

/// Re-checks the session whenever the app comes back to the foreground.
///
/// A session can end while the phone is in a pocket — the account revoked
/// from another device, deleted, disabled. Firebase only discovers that on its
/// next token refresh, roughly hourly, so without this the first thing the
/// user does after resuming is a write that gets rejected, with no explanation
/// and no way back to sign-in.
///
/// Checking on resume rather than on a timer is the cheap version of the same
/// guarantee: it costs one round trip at the exact moment somebody is about to
/// interact, and nothing at all while they are not.
///
/// It renders nothing and decides nothing. [AuthRepository.verifySession]
/// either ends the session or leaves it alone, and the router guard does the
/// navigating — the same rule the rest of the app follows.
class SessionWatcher extends StatefulWidget {
  const SessionWatcher({required this.auth, required this.child, super.key});

  final AuthRepository auth;
  final Widget child;

  @override
  State<SessionWatcher> createState() => _SessionWatcherState();
}

class _SessionWatcherState extends State<SessionWatcher>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // `resumed` only. `inactive` fires for a notification shade pull and for
    // the OAuth sheet opening over the app, which would mean a token round
    // trip every time somebody glanced at a notification.
    if (state != AppLifecycleState.resumed) return;

    // Unawaited by design: resuming must not wait on the network, and a
    // negative result arrives through the session stream regardless.
    widget.auth.verifySession();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
