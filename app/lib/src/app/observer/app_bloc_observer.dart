import 'package:bloc/bloc.dart';

import '../../core/logging/app_logger.dart';

/// Turns BLoC lifecycle into Sentry breadcrumbs and routes BLoC errors to the
/// crash reporter.
///
/// Breadcrumbs are the cheapest debugging win available: when a crash lands in
/// Sentry it arrives with the exact sequence of state transitions that led to
/// it, so you rarely have to reproduce anything locally.
class AppBlocObserver extends BlocObserver {
  const AppBlocObserver(this._logger);

  final AppLogger _logger;

  @override
  void onEvent(Bloc<dynamic, dynamic> bloc, Object? event) {
    super.onEvent(bloc, event);
    _logger.breadcrumb(
      '${bloc.runtimeType} ← ${event.runtimeType}',
      category: 'bloc.event',
    );
  }

  @override
  void onTransition(
    Bloc<dynamic, dynamic> bloc,
    Transition<dynamic, dynamic> transition,
  ) {
    super.onTransition(bloc, transition);
    _logger.breadcrumb(
      '${bloc.runtimeType} ${transition.currentState.runtimeType} → '
      '${transition.nextState.runtimeType}',
      category: 'bloc.transition',
    );
  }

  @override
  void onError(BlocBase<dynamic> bloc, Object error, StackTrace stackTrace) {
    _logger.error(
      'Unhandled error in ${bloc.runtimeType}',
      error: error,
      stackTrace: stackTrace,
      name: 'bloc',
    );
    super.onError(bloc, error, stackTrace);
  }
}
