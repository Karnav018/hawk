import 'package:shared_preferences/shared_preferences.dart';

/// Screen 2K's switches, and the one of them that is currently real.
///
/// Read through a cached static rather than a repository, because the only
/// consumer that matters — Sentry's `beforeSend` — runs on the error path and
/// cannot await anything. A crash reporter that had to load a preference
/// before deciding whether to report would either block the crash or miss it.
///
/// **Opt-out, not opt-in.** Reports are on by default, which is the honest
/// default for a diagnostic that carries no file names and no content (see
/// `_beforeSend`), and the switch turns them off for good rather than for
/// this launch.
class PrivacySettings {
  const PrivacySettings._();

  static const _crashKey = 'privacy.crashReports';

  /// Cached so [crashReportsEnabled] can answer synchronously. Defaults to
  /// true before [load] has run, so a crash during startup is still reported.
  static bool _crashReports = true;

  static bool get crashReportsEnabled => _crashReports;

  /// Called once during bootstrap, before Sentry is initialised.
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _crashReports = prefs.getBool(_crashKey) ?? true;
  }

  static Future<void> setCrashReports({required bool enabled}) async {
    _crashReports = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_crashKey, enabled);
  }
}
