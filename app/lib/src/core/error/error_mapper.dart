import 'dart:async' as async;
import 'dart:io';

import 'app_exception.dart';

/// Normalises anything throwable into an [AppException].
///
/// Provider-specific errors are mapped where they are raised — Firebase codes
/// in the repositories that call Firebase. This handles what is left: platform
/// exceptions, parsing failures, and passing an already-mapped [AppException]
/// through untouched so a rethrow does not re-wrap it.
abstract final class ErrorMapper {
  static AppException map(Object error, [StackTrace? stackTrace]) {
    if (error is AppException) return error;
    if (error is SocketException) return const AppException.network();
    if (error is async.TimeoutException) return const AppException.timeout();
    if (error is FormatException || error is TypeError) {
      return const AppException.parsing();
    }
    return AppException.unknown(cause: error, stackTrace: stackTrace);
  }
}
