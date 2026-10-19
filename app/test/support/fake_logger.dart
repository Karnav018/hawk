import 'package:knowra/src/core/logging/app_logger.dart';

/// Swallows everything. Keeps tests off Sentry and out of the console.
class FakeLogger implements AppLogger {
  final breadcrumbs = <String>[];
  final errors = <String>[];

  @override
  void breadcrumb(
    String message, {
    String? category,
    LogLevel level = LogLevel.info,
    Map<String, dynamic>? data,
  }) => breadcrumbs.add(message);

  @override
  void debug(String message, {String? name, Map<String, dynamic>? data}) {}

  @override
  void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    String? name,
    Map<String, dynamic>? data,
    bool report = true,
  }) => errors.add(message);

  @override
  void info(String message, {String? name, Map<String, dynamic>? data}) {}

  @override
  Future<void> setUser({String? id, String? email, String? username}) async {}

  @override
  void warning(String message, {String? name, Map<String, dynamic>? data}) {}
}
