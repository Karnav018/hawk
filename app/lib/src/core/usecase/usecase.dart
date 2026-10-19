/// A single unit of application behaviour.
///
/// Use cases keep BLoCs thin: the BLoC decides *when* something happens, the
/// use case knows *what* happens. Failures surface as thrown `AppException`s.
abstract interface class UseCase<Result, Params> {
  Future<Result> call(Params params);
}

/// Marker for use cases that take no arguments.
///
/// ```dart
/// final result = await getProfile(const NoParams());
/// ```
class NoParams {
  const NoParams();

  @override
  bool operator ==(Object other) => other is NoParams;

  @override
  int get hashCode => 0;
}
