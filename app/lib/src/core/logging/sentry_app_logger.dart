import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'app_logger.dart';

/// [AppLogger] backed by `dart:developer` for local output and Sentry for
/// breadcrumbs plus error reporting.
///
/// Console output is debug-only; Sentry calls are safe no-ops when the SDK was
/// never initialised (no DSN configured for the flavour).
@LazySingleton(as: AppLogger)
class SentryAppLogger implements AppLogger {
  const SentryAppLogger();

  @override
  void debug(String message, {String? name, Map<String, dynamic>? data}) =>
      _log(LogLevel.debug, message, name: name, data: data);

  @override
  void info(String message, {String? name, Map<String, dynamic>? data}) =>
      _log(LogLevel.info, message, name: name, data: data);

  @override
  void warning(String message, {String? name, Map<String, dynamic>? data}) =>
      _log(LogLevel.warning, message, name: name, data: data);

  @override
  void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    String? name,
    Map<String, dynamic>? data,
    bool report = true,
  }) {
    _log(
      LogLevel.error,
      message,
      name: name,
      data: data,
      error: error,
      stackTrace: stackTrace,
    );

    if (!report) return;

    unawaited(
      Sentry.captureException(
        error ?? message,
        stackTrace: stackTrace,
        withScope: (scope) {
          scope.level = SentryLevel.error;
          if (name != null) scope.setTag('source', name);
          if (data != null) scope.setContexts('details', data);
        },
      ),
    );
  }

  @override
  void breadcrumb(
    String message, {
    String? category,
    LogLevel level = LogLevel.info,
    Map<String, dynamic>? data,
  }) {
    Sentry.addBreadcrumb(
      Breadcrumb(
        message: message,
        category: category,
        level: _toSentryLevel(level),
        data: data,
      ),
    );
    if (kDebugMode) _log(level, message, name: category, data: data);
  }

  @override
  Future<void> setUser({String? id, String? email, String? username}) async {
    await Sentry.configureScope((scope) {
      scope.setUser(
        id == null && email == null && username == null
            ? null
            : SentryUser(id: id, email: email, username: username),
      );
    });
  }

  void _log(
    LogLevel level,
    String message, {
    String? name,
    Map<String, dynamic>? data,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (!kDebugMode) return;
    developer.log(
      data == null ? message : '$message ${_encode(data)}',
      name: name ?? 'knowra',
      level: _toDeveloperLevel(level),
      error: error,
      stackTrace: stackTrace,
      time: DateTime.now(),
    );
  }

  String _encode(Map<String, dynamic> data) =>
      data.entries.map((e) => '${e.key}=${e.value}').join(' ');

  int _toDeveloperLevel(LogLevel level) => switch (level) {
    LogLevel.debug => 500,
    LogLevel.info => 800,
    LogLevel.warning => 900,
    LogLevel.error => 1000,
    LogLevel.fatal => 1200,
  };

  SentryLevel _toSentryLevel(LogLevel level) => switch (level) {
    LogLevel.debug => SentryLevel.debug,
    LogLevel.info => SentryLevel.info,
    LogLevel.warning => SentryLevel.warning,
    LogLevel.error => SentryLevel.error,
    LogLevel.fatal => SentryLevel.fatal,
  };
}
