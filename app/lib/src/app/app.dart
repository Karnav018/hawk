import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/config/app_config.dart';
import '../core/di/injector.dart';
import '../core/feedback/snack_host.dart';
import '../features/auth/domain/repositories/auth_repository.dart';
import '../features/auth/presentation/bloc/session_cubit.dart';
import '../features/auth/presentation/widgets/session_watcher.dart';
import '../features/billing/presentation/bloc/subscription_cubit.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';
import 'theme/theme_cubit.dart';

/// Root widget. Everything below it is resolved from get_it.
class HawkApp extends StatelessWidget {
  const HawkApp({super.key});

  @override
  Widget build(BuildContext context) {
    final config = getIt<AppConfig>();

    return MultiBlocProvider(
      providers: [
        BlocProvider<ThemeCubit>.value(value: getIt<ThemeCubit>()),
        // Session lives above the router so any screen can read it — sign-out
        // from settings, the current user's name in a header.
        BlocProvider<SessionCubit>.value(value: getIt<SessionCubit>()),
        // The current plan, above the router for the same reason as the
        // session: entitlements shape what several screens are allowed to
        // offer, and a plan each screen fetched for itself would be four
        // round trips and four chances to disagree.
        BlocProvider<SubscriptionCubit>.value(
          value: getIt<SubscriptionCubit>(),
        ),
      ],
      child: BlocBuilder<ThemeCubit, ThemeMode>(
        builder: (context, themeMode) => MaterialApp.router(
          title: config.appName,
          debugShowCheckedModeBanner: !config.isProduction,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: themeMode,
          routerConfig: getIt<AppRouter>().config,
          // Above every route: a snack confirming a save has to survive the
          // navigation that follows it, and a revoked session has to be
          // noticed wherever the user happens to be standing.
          builder: (context, child) => SessionWatcher(
            auth: getIt<AuthRepository>(),
            child: SnackHost(child: child ?? const SizedBox.shrink()),
          ),
        ),
      ),
    );
  }
}
