import 'package:freezed_annotation/freezed_annotation.dart';

part 'app_exception.freezed.dart';

/// The single error currency of the app.
///
/// Everything thrown below the presentation layer — `DioException`, a parsing
/// error, a platform channel failure — is normalised into one of these cases by
/// [ErrorMapper]. BLoCs therefore only ever have to reason about this sealed
/// set, and the UI can exhaustively `switch` over it.
@freezed
sealed class AppException with _$AppException implements Exception {
  const AppException._();

  /// No usable connection, DNS failure, socket closed.
  const factory AppException.network({
    @Default('No internet connection.') String message,
  }) = NetworkException;

  /// Connect / send / receive timeout.
  const factory AppException.timeout({
    @Default('The request timed out.') String message,
  }) = TimeoutException;

  /// 401 / 403 — token missing, expired or rejected.
  const factory AppException.unauthorized({
    @Default('Your session has expired. Please sign in again.') String message,
  }) = UnauthorizedException;

  /// 4xx other than 401/403, usually with a server-supplied message.
  const factory AppException.badRequest({
    required String message,
    int? statusCode,
    Map<String, dynamic>? errors,
  }) = BadRequestException;

  /// 404.
  const factory AppException.notFound({@Default('Not found.') String message}) =
      NotFoundException;

  /// 5xx.
  const factory AppException.server({
    @Default('Something went wrong on our side.') String message,
    int? statusCode,
  }) = ServerException;

  /// The request was cancelled (e.g. the user navigated away).
  const factory AppException.cancelled({
    @Default('Request cancelled.') String message,
  }) = CancelledException;

  /// Response body did not match the expected shape.
  const factory AppException.parsing({
    @Default('Unexpected response from the server.') String message,
  }) = ParsingException;

  /// Anything we could not classify.
  const factory AppException.unknown({
    @Default('Something went wrong.') String message,
    Object? cause,
    StackTrace? stackTrace,
  }) = UnknownException;

  /// Human-readable text safe to surface in the UI.
  String get displayMessage => switch (this) {
    NetworkException(:final message) => message,
    TimeoutException(:final message) => message,
    UnauthorizedException(:final message) => message,
    BadRequestException(:final message) => message,
    NotFoundException(:final message) => message,
    ServerException(:final message) => message,
    CancelledException(:final message) => message,
    ParsingException(:final message) => message,
    UnknownException(:final message) => message,
  };

  /// Whether a retry has any chance of succeeding.
  bool get isRetryable => switch (this) {
    NetworkException() || TimeoutException() || ServerException() => true,
    _ => false,
  };

  /// Cancellations and expected auth failures are noise in Sentry.
  bool get shouldReport => switch (this) {
    CancelledException() ||
    UnauthorizedException() ||
    NetworkException() => false,
    _ => true,
  };

  @override
  String toString() => '$runtimeType: $displayMessage';
}
