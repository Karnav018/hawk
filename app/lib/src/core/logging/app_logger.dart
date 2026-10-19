/// Severity levels, ordered from most to least verbose.
enum LogLevel { debug, info, warning, error, fatal }

/// App-wide logging contract.
///
/// The rest of the codebase depends on this interface, never on Sentry
/// directly — so the transport can be swapped (or made a no-op in tests)
/// without touching call sites.
abstract interface class AppLogger {
  void debug(String message, {String? name, Map<String, dynamic>? data});

  void info(String message, {String? name, Map<String, dynamic>? data});

  void warning(String message, {String? name, Map<String, dynamic>? data});

  /// Logs and — unless [report] is false — sends the error to the crash
  /// reporter.
  void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    String? name,
    Map<String, dynamic>? data,
    bool report = true,
  });

  /// Leaves a trail of what happened before a crash (navigation, taps,
  /// requests). Cheap: breadcrumbs are only uploaded when an event is sent.
  void breadcrumb(
    String message, {
    String? category,
    LogLevel level = LogLevel.info,
    Map<String, dynamic>? data,
  });

  /// Attaches (or clears, when null) the signed-in user on subsequent events.
  Future<void> setUser({String? id, String? email, String? username});
}
