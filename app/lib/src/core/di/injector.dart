import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';

import 'injector.config.dart';

/// The single service locator instance.
final GetIt getIt = GetIt.instance;

/// Generated wiring entry point.
///
/// Run `dart run build_runner build --delete-conflicting-outputs` after adding
/// or changing any `@injectable` / `@module` annotation.
@InjectableInit(
  initializerName: 'init',
  preferRelativeImports: true,
  asExtension: true,
)
Future<GetIt> configureDependencies({String? environment}) async =>
    getIt.init(environment: environment);

/// Named environments, so a mock data source can replace a real one without
/// touching call sites: `@Environment(Env.dev)`.
abstract final class AppEnv {
  static const dev = Environment.dev;
  static const prod = Environment.prod;
  static const test = Environment.test;
}
