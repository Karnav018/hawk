import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:injectable/injectable.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../../core/di/injector.dart';
import '../../core/widgets/vault_dock.dart';
import '../../features/account/presentation/pages/profile_page.dart';
import '../../features/account/presentation/pages/vault_page.dart';
import '../../features/auth/domain/entities/auth_session.dart';
import '../../features/auth/domain/entities/auth_user.dart';
import '../../features/auth/domain/repositories/auth_repository.dart';
import '../../features/auth/presentation/bloc/email_sign_in_cubit.dart';
import '../../features/auth/presentation/bloc/onboarding_cubit.dart';
import '../../features/auth/presentation/bloc/session_cubit.dart';
import '../../features/auth/presentation/bloc/sign_in_cubit.dart';
import '../../features/auth/presentation/pages/email_address_page.dart';
import '../../features/auth/presentation/pages/how_you_ask_page.dart';
import '../../features/auth/presentation/pages/sign_in_page.dart';
import '../../features/auth/presentation/pages/verify_code_page.dart';
import '../../features/billing/presentation/bloc/billing_cubit.dart';
import '../../features/billing/presentation/bloc/paywall_cubit.dart';
import '../../features/billing/presentation/pages/billing_page.dart';
import '../../features/billing/presentation/pages/paywall_page.dart';
import '../../features/capture/presentation/bloc/capture_cubit.dart';
import '../../features/capture/presentation/bloc/speak_capture_cubit.dart';
import '../../features/capture/presentation/bloc/upload_center.dart';
import '../../features/capture/presentation/pages/capture_page.dart';
import '../../features/capture/presentation/pages/indexing_page.dart';
import '../../features/capture/presentation/pages/speak_capture_page.dart';
import '../../features/chat/domain/entities/recent_find.dart';
import '../../features/chat/domain/entities/seeded_question.dart';
import '../../features/chat/presentation/bloc/answer_cubit.dart';
import '../../features/chat/presentation/pages/answer_page.dart';
import '../../features/connectors/domain/entities/storage_account.dart';
import '../../features/connectors/presentation/bloc/connect_storage_cubit.dart';
import '../../features/connectors/presentation/bloc/folder_selection_cubit.dart';
import '../../features/connectors/presentation/bloc/index_progress_cubit.dart';
import '../../features/connectors/presentation/bloc/permissions_cubit.dart';
import '../../features/connectors/presentation/pages/choose_folders_page.dart';
import '../../features/connectors/presentation/pages/connect_storage_page.dart';
import '../../features/connectors/presentation/pages/index_progress_page.dart';
import '../../features/connectors/presentation/pages/permissions_page.dart';
import '../../features/connectors/presentation/pages/vault_ready_page.dart';
import '../../features/memory/presentation/bloc/file_viewer_cubit.dart';
import '../../features/memory/presentation/pages/file_viewer_page.dart';
import '../../features/memory/presentation/pages/library_page.dart';
import '../../features/splash/presentation/pages/splash_page.dart';
import '../../features/voice/presentation/bloc/voice_cubit.dart';
import '../../features/voice/presentation/pages/home_page.dart';
import '../../features/voice/presentation/pages/result_stack_page.dart';
import 'router_refresh.dart';
import 'tab_shell.dart';

/// Declarative route table plus the session guard.
///
/// One `redirect` decides where anyone is allowed to be, from one source of
/// truth. Screens never navigate on sign-in themselves — they change the
/// session and the guard moves them, so there is no way for a screen to
/// disagree with the session about which half of the app you are in.
@lazySingleton
class AppRouter {
  AppRouter(this._session, this._auth) {
    _router = GoRouter(
      initialLocation: SplashPage.routePath,
      refreshListenable: Listenable.merge([
        GoRouterRefreshStream(_session.stream),
        _splashComplete,
      ]),
      redirect: _guard,
      observers: [SentryNavigatorObserver(setRouteNameAsTransaction: true)],
      routes: [
        GoRoute(
          path: SplashPage.routePath,
          name: SplashPage.routeName,
          builder: (context, state) => SplashPage(
            // Session restore overlaps the brand moment instead of becoming a
            // spinner after it.
            readyWhen: _restore,
            onComplete: () => _splashComplete.value = true,
          ),
        ),

        // One shell so the email cubit survives the 3H → 3I hop; a per-route
        // provider would drop the address and the resend countdown between
        // the two screens.
        ShellRoute(
          builder: (context, state, child) => MultiBlocProvider(
            providers: [
              BlocProvider(create: (_) => getIt<SignInCubit>()),
              BlocProvider(create: (_) => getIt<EmailSignInCubit>()),
            ],
            child: child,
          ),
          routes: [
            GoRoute(
              path: SignInPage.routePath,
              name: SignInPage.routeName,
              builder: (context, state) => const SignInPage(),
            ),
            GoRoute(
              path: EmailAddressPage.routePath,
              name: EmailAddressPage.routeName,
              builder: (context, state) => const EmailAddressPage(),
            ),
            GoRoute(
              path: VerifyCodePage.routePath,
              name: VerifyCodePage.routeName,
              builder: (context, state) => const VerifyCodePage(),
            ),
          ],
        ),

        GoRoute(
          path: HowYouAskPage.routePath,
          name: HowYouAskPage.routeName,
          builder: (context, state) => BlocProvider(
            create: (_) => getIt<OnboardingCubit>(),
            child: const HowYouAskPage(),
          ),
        ),

        // Screens 3F–3L. One shell so `ConnectStorageCubit` — which owns the
        // live catalogue *and* the "setup is finished" call — survives the
        // whole run: screen 3L needs to end onboarding, and re-creating the
        // cubit per route would mean re-subscribing to the catalogue on every
        // hop through it.
        ShellRoute(
          builder: (context, state, child) => BlocProvider(
            create: (_) => getIt<ConnectStorageCubit>(),
            child: child,
          ),
          routes: [
            GoRoute(
              path: ConnectStoragePage.routePath,
              name: ConnectStoragePage.routeName,
              builder: (context, state) => const ConnectStoragePage(),
            ),
            GoRoute(
              path: PermissionsPage.routePath,
              name: PermissionsPage.routeName,
              // A sheet, so the route must not be opaque: `SheetScaffold`
              // dims the screen underneath, and an opaque route would have
              // nothing underneath to dim.
              pageBuilder: (context, state) => CustomTransitionPage(
                key: state.pageKey,
                opaque: false,
                barrierDismissible: true,
                transitionDuration: const Duration(milliseconds: 260),
                transitionsBuilder: (context, animation, _, child) =>
                    SlideTransition(
                      position:
                          Tween(
                            begin: const Offset(0, 1),
                            end: Offset.zero,
                          ).animate(
                            CurvedAnimation(
                              parent: animation,
                              curve: Curves.easeOutCubic,
                            ),
                          ),
                      child: child,
                    ),
                child: _permissionsFor(state),
              ),
            ),
            GoRoute(
              path: ChooseFoldersPage.routePath,
              name: ChooseFoldersPage.routeName,
              builder: (context, state) => BlocProvider(
                create: (_) => getIt<FolderSelectionCubit>(
                  param1: state.pathParameters['accountId'],
                ),
                child: const ChooseFoldersPage(),
              ),
            ),
            GoRoute(
              path: IndexProgressPage.routePath,
              name: IndexProgressPage.routeName,
              builder: (context, state) => BlocProvider(
                create: (_) => getIt<IndexProgressCubit>(
                  param1: state.pathParameters['jobId'],
                ),
                child: const IndexProgressPage(),
              ),
            ),
            GoRoute(
              path: VaultReadyPage.routePath,
              name: VaultReadyPage.routeName,
              builder: (context, state) => const VaultReadyPage(),
            ),
          ],
        ),

        // The same screen 3F, reached from the vault dock after onboarding.
        // Its own provider rather than the shell's: this route lives outside
        // `/welcome`, and a cubit shared across the two would keep a
        // catalogue subscription alive for a run that has ended.
        GoRoute(
          path: ConnectStoragePage.manageRoutePath,
          name: ConnectStoragePage.manageRouteName,
          builder: (context, state) => BlocProvider(
            create: (_) => getIt<ConnectStorageCubit>(),
            child: const ConnectStoragePage(flow: ConnectFlow.manage),
          ),
        ),

        // The three tabs — Home, Library, You.
        //
        // A *stateful* shell, not three sibling routes: each tab keeps its own
        // navigation stack, so opening a file from Library and then tapping
        // Home and back again returns to the file rather than to the top of
        // the library. An IndexedStack keeps all three alive, which is what
        // makes that possible and what keeps the orb from being rebuilt —
        // and re-permissioned — every time somebody checks their plan.
        //
        // Storage is deliberately absent. v2 put it in the dock, which gave a
        // setup screen equal billing with the two things people do daily; v3
        // moves it inside You → Vault.
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) =>
              TabShell(shell: navigationShell),
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: HomePage.routePath,
                  name: HomePage.routeName,
                  builder: (context, state) => BlocProvider(
                    create: (_) => getIt<VoiceCubit>(),
                    // `StartDictation` arrives when the microphone was tapped
                    // on another screen, so home opens already listening
                    // rather than asking for the same tap twice.
                    child: HomePage(
                      startListening: state.extra is StartDictation,
                    ),
                  ),
                  routes: [
                    // A **child** of home, not a sibling. The design draws
                    // the nav pill on 1O, which only happens if the route
                    // resolves inside this shell branch — a top-level route
                    // would replace the shell and take the nav with it.
                    // Screen 1P is the opposite case and stays at the root.
                    GoRoute(
                      path: ResultStackPage.routePath,
                      name: ResultStackPage.routeName,
                      builder: (context, state) {
                        // The question travels as `extra` rather than a query
                        // parameter: it is free text somebody just spoke, and
                        // round-tripping it through a URL means escaping,
                        // length limits, and a question sitting in history.
                        final question = state.extra;
                        // LAST FOUND: reopened from this phone, not asked
                        // again — see [AnswerCubit.replay].
                        // Released with its files already found: the rows
                        // are on screen at once, only the answer is fetched.
                        if (question is SeededQuestion) {
                          return BlocProvider(
                            create: (_) =>
                                AnswerCubit.seeded(getIt(), getIt(), question),
                            child: const ResultStackPage(),
                          );
                        }
                        if (question is RecentFind) {
                          return BlocProvider(
                            create: (_) =>
                                AnswerCubit.replay(getIt(), getIt(), question),
                            child: const ResultStackPage(),
                          );
                        }
                        if (question is! String || question.trim().isEmpty) {
                          return const HomePage();
                        }
                        return BlocProvider(
                          create: (_) => getIt<AnswerCubit>(param1: question),
                          child: const ResultStackPage(),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: LibraryPage.routePath,
                  name: LibraryPage.routeName,
                  builder: (context, state) => const LibraryPage(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                // The profile provides its own cubit rather than taking one
                // from here, because it is the only screen that wants the
                // account summary and keeping that cubit alive app-wide would
                // mean four aggregation queries nobody asked for.
                GoRoute(
                  path: ProfilePage.routePath,
                  name: ProfilePage.routeName,
                  builder: (context, state) => const ProfilePage(),
                ),
              ],
            ),
          ],
        ),

        // 1M — the file viewer. On the root navigator, outside the shell:
        // the design draws no nav pill on it, and it reserves no clearance
        // for one.
        GoRoute(
          path: FileViewerPage.routePath,
          name: FileViewerPage.routeName,
          builder: (context, state) => BlocProvider(
            create: (_) => getIt<FileViewerCubit>(
              param1: state.pathParameters['memoryId'],
            ),
            child: const FileViewerPage(),
          ),
        ),

        // The Links tile's sheet. Same shape as 1H: a `SheetScaffold` dims
        // what is behind it, so the route must not be opaque or there is
        // nothing there to dim.
        GoRoute(
          path: AddLinkSheet.routePath,
          name: AddLinkSheet.routeName,
          pageBuilder: (context, state) => CustomTransitionPage(
            key: state.pageKey,
            opaque: false,
            barrierDismissible: true,
            transitionDuration: const Duration(milliseconds: 260),
            transitionsBuilder: (context, animation, _, child) =>
                SlideTransition(
                  position: Tween(begin: const Offset(0, 1), end: Offset.zero)
                      .animate(
                        CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOutCubic,
                        ),
                      ),
                  child: child,
                ),
            child: BlocProvider(
              create: (_) => getIt<CaptureCubit>(),
              child: const AddLinkSheet(),
            ),
          ),
        ),

        // 1R — the Vault, reached from the profile. Outside the shell for the
        // same reason as 1M: no nav pill is drawn on it.
        GoRoute(
          path: VaultPage.routePath,
          name: VaultPage.routeName,
          builder: (context, state) => const VaultPage(),
        ),

        GoRoute(
          path: CapturePage.routePath,
          name: CapturePage.routeName,
          builder: (context, state) => BlocProvider(
            create: (_) => getIt<CaptureCubit>(),
            child: const CapturePage(),
          ),
        ),

        GoRoute(
          path: SpeakCapturePage.routePath,
          name: SpeakCapturePage.routeName,
          builder: (context, state) => BlocProvider(
            create: (_) => getIt<SpeakCaptureCubit>(),
            child: const SpeakCapturePage(),
          ),
        ),

        // The Library's Indexing screen (F1·4). Outside the shell: the design
        // draws no nav pill on it. The center is app-wide and provided by
        // value, so leaving this screen never closes it — the upload keeps
        // going and the island picks it up.
        GoRoute(
          path: IndexingPage.routePath,
          name: IndexingPage.routeName,
          builder: (context, state) => BlocProvider<UploadCenter>.value(
            value: getIt<UploadCenter>(),
            child: IndexingPage(batchId: state.pathParameters['batchId']!),
          ),
        ),

        GoRoute(
          path: BillingPage.routePath,
          name: BillingPage.routeName,
          builder: (context, state) => BlocProvider(
            create: (_) => getIt<BillingCubit>(),
            child: const BillingPage(),
          ),
        ),

        GoRoute(
          path: PaywallPage.routePath,
          name: PaywallPage.routeName,
          builder: (context, state) => BlocProvider(
            create: (_) => getIt<PaywallCubit>(),
            child: const PaywallPage(),
          ),
        ),

        GoRoute(
          path: AnswerPage.routePath,
          name: AnswerPage.routeName,
          builder: (context, state) {
            // The question travels as `extra` rather than a query parameter:
            // it is free text a user just spoke or typed, and round-tripping
            // it through a URL means escaping, length limits, and a question
            // sitting in navigation history.
            final question = state.extra;
            if (question is! String || question.trim().isEmpty) {
              return const HomePage();
            }
            return BlocProvider(
              create: (_) => getIt<AnswerCubit>(param1: question),
              child: const AnswerPage(),
            );
          },
        ),
      ],
      errorBuilder: (context, state) =>
          Scaffold(body: Center(child: Text('Route not found: ${state.uri}'))),
    );
  }

  /// The account arrives as `extra` rather than as a path parameter: it was
  /// just created by the connect call and is fully in hand, so refetching it
  /// by id to render the screen that caused it would be a round trip for
  /// nothing.
  static Widget _permissionsFor(GoRouterState state) {
    final account = state.extra;
    if (account is! StorageAccount) return const ConnectStoragePage();
    return BlocProvider(
      create: (_) => getIt<PermissionsCubit>(param1: account),
      child: const PermissionsPage(),
    );
  }

  final SessionCubit _session;
  final AuthRepository _auth;

  /// Started once, lazily, and handed to the splash.
  late final Future<void> _restore = _auth.restore();

  /// The splash owns the screen until its animation finishes; the guard must
  /// not yank it away mid-transform just because the session resolved.
  final ValueNotifier<bool> _splashComplete = ValueNotifier(false);

  late final GoRouter _router;

  GoRouter get config => _router;

  static bool _isSignIn(String location) => location.startsWith('/sign-in');
  static bool _isOnboarding(String location) => location.startsWith('/welcome');

  String? _guard(BuildContext context, GoRouterState state) => guardFor(
    status: _session.state,
    location: state.matchedLocation,
    splashComplete: _splashComplete.value,
  );

  /// The whole redirect policy, as a pure function.
  ///
  /// Public and static so the test suite exercises *this* rather than a copy
  /// of it. A duplicated decision table passes happily while the real guard
  /// drifts away from it, which is the failure mode it was meant to prevent.
  @visibleForTesting
  static String? guardFor({
    required AuthStatus status,
    required String location,
    required bool splashComplete,
  }) {
    final onSplash = location == _splashPath;

    // Nothing is decided until storage has been read *and* the animation has
    // played. Redirecting earlier would flash the sign-in screen at somebody
    // who is already signed in.
    if (onSplash && !splashComplete) return null;

    return switch (status) {
      AuthUnknown() => onSplash ? null : _splashPath,
      AuthUnauthenticated() =>
        _isSignIn(location) ? null : SignInPage.routePath,

      // Onboarding is a run of screens now, not one screen, so the guard
      // sends people to the *first outstanding step* rather than always to
      // 3J. That is also the handoff: completing 3J sets `onboardedAt`, this
      // re-evaluates, and the same redirect that used to hold someone on the
      // name screen now moves them to 3F.
      AuthOnboarding(:final user) => switch (location) {
        _ when !_isOnboarding(location) => _firstStep(user),
        // Inside the run but on a step already behind them.
        _ when location == HowYouAskPage.routePath && !user.needsAskStep =>
          ConnectStoragePage.routePath,
        _ => null,
      },

      AuthAuthenticated() =>
        _isSignIn(location) || _isOnboarding(location) || onSplash
            ? HomePage.routePath
            : null,
    };
  }

  static String _firstStep(AuthUser user) => user.needsAskStep
      ? HowYouAskPage.routePath
      : ConnectStoragePage.routePath;

  static const _splashPath = SplashPage.routePath;
}
