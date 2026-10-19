import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/tab_shell.dart';
import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/di/injector.dart';
import '../../../../core/feedback/snack.dart';
import '../../../../core/feedback/snack_controller.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../../../core/widgets/app_screen.dart';
import '../../../../core/widgets/hawk_icons.dart';
import '../../../../core/widgets/hawk_kit.dart';
import '../../../../core/widgets/plan_gate.dart';
import '../../../account/domain/repositories/account_repository.dart';
import '../../../auth/domain/entities/auth_session.dart';
import '../../../auth/domain/entities/auth_user.dart';
import '../../../auth/presentation/bloc/session_cubit.dart';
import '../../../billing/presentation/bloc/subscription_cubit.dart';
import '../../../billing/presentation/pages/paywall_page.dart';
import '../../../billing/presentation/widgets/ask_limit_sheet.dart';
import '../../../billing/presentation/widgets/plan_alert_actions.dart';
import '../../../billing/presentation/widgets/plan_alerts.dart';
import '../../../capture/presentation/bloc/quick_shot_cubit.dart';
import '../../../capture/presentation/widgets/saved_snack.dart';
import '../../../chat/data/recent_finds.dart';
import '../../../chat/presentation/bloc/answer_cubit.dart';
import '../../../chat/presentation/widgets/ask_field.dart';
import '../../../chat/presentation/widgets/chat_thread.dart';
import '../bloc/suggestions_cubit.dart';
import '../bloc/vault_ready_cubit.dart';
import '../bloc/voice_cubit.dart';
import '../widgets/home_chrome.dart';
import 'voice_home_page.dart';

/// `/` — home, in whichever form the account asked for.
///
/// Screen 1F ends with a question — *"How will you mostly ask?"* — and this is
/// where its answer is spent. `InputPreference.voice` opens the orb;
/// `InputPreference.typing` opens the chat face. Not two routes and not a
/// setting buried in the account screen: one root that renders what was asked
/// for, which is the only reading of 1F's promise ("This sets what home opens
/// to") that is actually true.
///
/// **The chrome is shared and the middle is not.** The greeting row and the
/// Speak / Type control are identical in both faces — from the final block of
/// `Hawk Logo v3.dc.html` — so they live here and the faces supply only what
/// sits between them and the nav. That is what makes the tab switch read as
/// one screen changing its mind rather than as two screens swapping places.
///
/// Switching tabs does **not** write the preference back to the account. The
/// tabs are "how I want to ask right now"; 1F is "what home opens to". A user
/// who types one question should not find their orb gone tomorrow.
///
/// v2 had no equivalent decision to make: home was the orb for everybody, and
/// the typed path was a field underneath it. Somebody who answered "typing"
/// on 1F got a voice screen with a text box on it.
class HomePage extends StatefulWidget {
  const HomePage({this.startListening = false, super.key});

  static const routeName = 'home';
  static const routePath = '/';

  /// Open the microphone as soon as home is up. Forwarded to the orb face.
  final bool startListening;

  /// Which face to show, given the session and any choice made on-screen.
  ///
  /// Pulled out of `build` and made static so the decision can be tested as
  /// the decision it is: everything around it — the orb, the ask field, the
  /// greeting's memory count — needs half the injector to render, and none
  /// of that has any bearing on which of the two faces is correct.
  ///
  /// The on-screen choice wins while it exists, and a session that has not
  /// resolved yet falls through to voice rather than pinning that default:
  /// see [_HomePageState._mode].
  @visibleForTesting
  static InputPreference faceFor(AuthStatus status, [InputPreference? chosen]) {
    if (chosen != null) return chosen;
    return switch (status) {
      AuthAuthenticated(:final user) => user.inputPreference,
      AuthOnboarding(:final user) => user.inputPreference,
      _ => InputPreference.voice,
    };
  }

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  /// The face being shown, once the user has chosen one on this screen.
  ///
  /// Null means "whatever the account said", which is deliberately not the
  /// same as defaulting to voice: the session arrives asynchronously, and
  /// seeding this in `initState` would pin the first value the session
  /// happened to have — `AuthUnknown` on a cold start — and leave a typing
  /// user on the orb until they switched manually.
  InputPreference? _mode;

  final _ask = TextEditingController();

  /// Whether the on-screen keyboard was up at the last build.
  ///
  /// Read from the view rather than `MediaQuery`, because home cannot see
  /// the keyboard through `MediaQuery`: the tab shell's Scaffold absorbs the
  /// inset — it shrinks its body, home included — and strips it from the
  /// `MediaQuery` it hands down. So nothing here rebuilds when the keyboard
  /// moves unless it listens for it, which [didChangeMetrics] does.
  bool _typing = false;

  bool get _keyboardUp => View.of(context).viewInsets.bottom > 0;

  /// The conversation on the chat face, owned here rather than by a
  /// provider this widget builds.
  ///
  /// **[_submit] could not reach it before.** The cubit was created by a
  /// `BlocProvider` inside [build], and [_submit] looked it up with this
  /// state's own `context` — which sits *above* everything [build] returns.
  /// `context.read` walks up, never down, so every typed question and every
  /// START WITH row threw `ProviderNotFoundException` and nothing was asked.
  /// Owning the cubit makes the reference direct; the provider below still
  /// hands the same instance to the thread.
  ///
  /// Empty: the thread starts idle and takes its first question from the
  /// field. Shared by both faces rather than only the typing one, so
  /// switching tabs mid-conversation does not discard it — the tabs are a
  /// view of home, not two screens.
  late final AnswerCubit _answers = getIt<AnswerCubit>(param1: '');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeMetrics() {
    // Fires on every frame of the keyboard's slide; only the flip matters.
    if (_keyboardUp != _typing) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ask.dispose();
    unawaited(_answers.close());
    super.dispose();
  }

  Future<void> _submit(String value) async {
    final question = value.trim();
    if (question.isEmpty) return;

    // Refused here rather than at the server, so the user is told before the
    // orb spins up and before a question is spent. The server still enforces
    // it — this is the courtesy, not the control.
    //
    // Screen 1W, not the paywall. Both used to push straight to pricing,
    // which answers a question the user has not asked yet: the first thing
    // somebody who has run out needs to know is that their library is fine
    // and when asking comes back. The sheet says that, and *then* offers the
    // upgrade — and only where an upgrade would actually change anything.
    final plan = context.read<SubscriptionCubit>().state;
    final lock = plan.askLock;
    if (lock != null) {
      unawaited(AskLimitSheet.showFor(context, plan));
      return;
    }

    _ask.clear();
    FocusScope.of(context).unfocus();
    // **Answered here, not on a pushed screen.** Typing a question used to
    // navigate to screen 1P, which made asking feel like leaving — you were
    // on home, and then you were somewhere else reading. The thread now
    // opens underneath the field you typed in, and 1P remains only as the
    // destination for a conversation resumed from elsewhere.
    unawaited(_answers.followUp(question));
  }

  @override
  Widget build(BuildContext context) {
    final user = switch (context.watch<SessionCubit>().state) {
      AuthAuthenticated(:final user) => user,
      AuthOnboarding(:final user) => user,
      _ => null,
    };
    final mode = HomePage.faceFor(context.watch<SessionCubit>().state, _mode);
    final speaks = mode == InputPreference.voice;

    // **Typing, the conversation gets the screen.** The greeting, the tabs
    // and the plan banner are a fixed stack above the thread, and with the
    // keyboard up there was not room for them: the chat face overflowed on
    // every phone once the asks-low banner showed, and on small phones
    // without it. While the keyboard is up they step aside — the field's own
    // microphone still switches to voice, and all three are back the moment
    // the keyboard is down. Instant rather than animated: an animated
    // header still at full height while the keyboard is already half up is
    // the same overflow, one frame at a time.
    // Read here as well as on the metrics callback: home can be built with
    // the keyboard already up, and then no metrics change ever arrives.
    _typing = _keyboardUp;
    final compact = _typing && !speaks;

    return MultiBlocProvider(
      providers: [
        // Created here rather than registered in the injector: it has one
        // call site and registering it would mean regenerating
        // `injector.config.dart`. See [VaultReadyCubit].
        BlocProvider(
          create: (_) => VaultReadyCubit(getIt<AccountRepository>()),
        ),
        // Owned by this state — see [_answers] for why it cannot be created
        // here.
        BlocProvider.value(value: _answers),
        // Both faces offer the same three things to ask (1Y chips, 1Z list),
        // built from this user's recent memories.
        BlocProvider(create: (_) => getIt<SuggestionsCubit>()),
        // The header camera's shoot-and-index.
        BlocProvider(create: (_) => getIt<QuickShotCubit>()),
      ],
      child: Stack(
        children: [
          AppScreen(
            ambientOpacity: 0,
            scrollable: false,
            // Home is a tab root, so the shell's nav pill floats over the bottom
            // of it. Reserved in the padding rather than as a trailing box,
            // because this screen does not scroll and its middle is centred in
            // whatever is left.
            //
            // Both faces end in something docked — the chat face in its ask
            // bar, the voice face in 1Y's row of chips — so both take the wider
            // [dockedClearance]. The voice face used to take the bare
            // [navClearance], from before it had chips: they then sat flush on
            // the pill and read as a banner hanging off the Home button. The
            // design keeps 14px between them.
            //
            // With the keyboard up the pill is underneath it — the shell pins
            // its bottom bar to the bottom of the screen, not above the keyboard
            // — so the clearance would only hold 106px of empty space between the
            // field and the keys.
            padding: EdgeInsets.fromLTRB(
              AppSpacing.screenSide,
              AppSpacing.screenTop,
              AppSpacing.screenSide,
              compact ? AppSpacing.md : dockedClearance,
            ),
            footer: speaks
                ? null
                : AskField(
                    controller: _ask,
                    hint: 'Ask anything…',
                    onSubmit: (value) => unawaited(_submit(value)),
                    // The microphone hands you to the orb rather than opening a
                    // recording you did not aim at: it flips the tabs, and the
                    // hold is still yours to make.
                    onMic: () {
                      // Drop the keyboard first. Switching faces with it still up
                      // gave the voice face a sliver of the screen and it
                      // overflowed by 142px while the keyboard animated away.
                      FocusScope.of(context).unfocus();
                      setState(() => _mode = InputPreference.voice);
                    },
                  ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!compact) ...[
                  HomeGreeting(name: user?.displayName ?? ''),
                  const SizedBox(height: AppSpacing.inset),
                  ModeTabs(
                    mode: mode,
                    onChanged: (next) => setState(() => _mode = next),
                  ),
                  // Screen 1X's home-header banner — one at a time, and only
                  // when there is something to act on. Placed under the tabs so
                  // it belongs to home rather than to either face.
                  if (homeAlert(context.plan) case final alert?) ...[
                    const SizedBox(height: AppSpacing.md),
                    PlanAlertCard(
                      alert: alert,
                      onAction: () => onPlanAlert(context, alert),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.group),
                ],
                Expanded(
                  child: speaks
                      ? VoiceHomeFace(
                          autoStart: widget.startListening,
                          recent: getIt<RecentFinds>(),
                          rowEndInset: CameraFab.size + AppSpacing.md,
                          rowBottomInset: _cameraOverhang,
                        )
                      : _TypeFace(
                          onAsk: (q) => unawaited(_submit(q)),
                          // Room for the camera at the end of the thread —
                          // none while typing, when the camera is hidden and
                          // the thread has the least room of all.
                          bottomInset: compact ? 0 : _threadClearance,
                        ),
                ),
              ],
            ),
          ),
          // Bottom-right, where the thumb is. Hidden while typing — the
          // keyboard owns the bottom of the screen — and while the eye is
          // listening, when the screen is about one thing.
          if (!compact)
            Positioned(
              right: AppSpacing.screenSide,
              // Voice: on the chip row's centre line, so the camera reads as
              // the end of that row rather than a button hovering over it.
              // The face lifts the row by the camera's overhang, so the
              // camera's bottom lands exactly on the band's top edge — any
              // lower and the band, painted over the page, cuts it off.
              // Chat: above the ask bar, which is taller.
              bottom: speaks ? dockedClearance : dockedClearance + _fabLift,
              child: speaks
                  ? BlocSelector<VoiceCubit, VoiceState, bool>(
                      selector: (s) => s.phase == VoicePhase.listening,
                      builder: (context, listening) =>
                          listening ? const SizedBox.shrink() : const _Camera(),
                    )
                  : const _Camera(),
            ),
        ],
      ),
    );
  }

  /// How far above the nav band the camera floats on the chat face: clear
  /// of the ask bar docked above the nav.
  static const _fabLift = 86.0;

  /// How far the camera, centred on the voice face's chip row, reaches past
  /// the row at top and bottom — 8px, a 56px circle on a 40px row.
  static const _cameraOverhang = (CameraFab.size - homeChipRowHeight) / 2;

  /// What the chat face's list ends in, so its last bubble or file card
  /// scrolls clear of the camera rather than under it.
  ///
  /// The camera floats over the bottom-right corner of the thread — the
  /// corner where a user's own bubble and a file card's Open chip both sit —
  /// so without this the newest turn arrived under it. Derived from the same
  /// numbers that place the camera: its top, measured from the screen's
  /// bottom, less the thread's own bottom edge (the ask bar and the gap above
  /// it), plus the thread's usual gap between items.
  static const _threadClearance =
      (_fabLift + CameraFab.size) -
      (AppSize.button + AppScreen.footerGap) +
      AppSpacing.md;
}

/// The chat face's middle — the invitation, then the conversation.
///
/// **The thread is here now.** Typing a question used to push screen 1P: you
/// were on home, and then you were somewhere else reading the answer. That
/// made asking feel like leaving, for the half of users who chose typing on
/// 1F and therefore see this face every time they open the app. The reply now
/// arrives under the field it was typed into.
///
/// Before anything is asked, the orb sits here at rest with the design's
/// invitation under it. It is the product's mark, and a home screen that
/// dropped it for a typing user would be a different app depending on a
/// preference.
class _TypeFace extends StatefulWidget {
  const _TypeFace({required this.onAsk, this.bottomInset = 0});

  /// Submits a question as if it had been typed — the START WITH rows.
  final ValueChanged<String> onAsk;

  /// Space the list ends in, for whatever home floats over its end.
  final double bottomInset;

  @override
  State<_TypeFace> createState() => _TypeFaceState();
}

class _TypeFaceState extends State<_TypeFace> {
  final _thread = ScrollController();

  @override
  void dispose() {
    _thread.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<AnswerCubit, AnswerState>(
      listenWhen: (a, b) =>
          a.question != b.question ||
          a.answer != b.answer ||
          a.matches.length != b.matches.length,
      listener: (context, state) => scrollThreadToEnd(_thread),
      builder: (context, state) {
        final padding = EdgeInsets.only(bottom: widget.bottomInset);
        if (context.read<AnswerCubit>().isIdle) {
          return _AskYourLibrary(onAsk: widget.onAsk, padding: padding);
        }

        return ChatThread(state: state, controller: _thread, padding: padding);
      },
    );
  }
}

/// Screen 1Z's resting state — the chat face before anything is asked.
///
/// **No eye.** The first cut centred the orb over "Ask anything you have
/// kept"; 1Z has no orb on it at all. The eye is the voice face's object —
/// it listens — and on a keyboard-first screen it was decoration standing
/// where the design puts a heading and three questions to start from.
///
/// Scrolls rather than centres, so the keyboard coming up cannot push the
/// START WITH list off a short screen.
class _AskYourLibrary extends StatelessWidget {
  const _AskYourLibrary({required this.onAsk, this.padding = EdgeInsets.zero});

  final ValueChanged<String> onAsk;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return ListView(
      padding: padding,
      children: [
        const SizedBox(height: AppSpacing.sm),
        const Headline('Ask your library', size: 32),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Answers come back with the file they came from.',
          style: AppTypography.bodyMedium.copyWith(
            height: 1.6,
            color: p.textTertiary,
          ),
        ),
        BlocBuilder<SuggestionsCubit, List<Suggestion>>(
          builder: (context, suggestions) {
            // An empty library gets the heading alone — a list of questions
            // about files it does not have would be the screen inventing a
            // library.
            if (suggestions.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: AppSpacing.card),
                const MetaText('START WITH'),
                const SizedBox(height: 10),
                RowGroup(
                  children: [
                    for (final s in suggestions)
                      HawkRow(
                        title: s.question,
                        trailing: AppIcon(
                          HawkIcons.arrowRight,
                          size: 18,
                          color: p.textMuted,
                        ),
                        onTap: () => onAsk(s.question),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// The floating camera and what its taps say: shoot, index, and report.
class _Camera extends StatelessWidget {
  const _Camera();

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<QuickShotCubit, QuickShotState>(
        listenWhen: (a, b) => a.saved != b.saved || a.exception != b.exception,
        listener: (context, shot) {
          final error = shot.exception;
          if (error != null) {
            getIt<SnackController>().show(
              Snack.detail(
                title: 'Could not save that photo',
                subtitle: error.displayMessage,
                mark: SnackMark.failure,
              ),
            );
            context.read<QuickShotCubit>().dismissError();
            return;
          }
          getIt<SnackController>().show(
            savedSnack(
              context.read<SubscriptionCubit>().state,
              count: 1,
              onKeep: () => context.pushNamed(PaywallPage.routeName),
            ),
          );
        },
        builder: (context, shot) => CameraFab(
          isBusy: shot.busy,
          // A full index goes to the plans instead, as the library's
          // capture tiles do: a photo that cannot be embedded is not worth
          // taking here.
          //
          // `read`, not `context.plan`: that is a `watch`, and a watch in a
          // tap handler throws "tried to listen to a value exposed with
          // provider, from outside of the widget tree" — which is what the
          // first tap on this button did.
          onPressed: () =>
              context.read<SubscriptionCubit>().state.indexLock != null
              ? context.pushNamed(PaywallPage.routeName)
              : context.read<QuickShotCubit>().shoot(),
        ),
      );
}
