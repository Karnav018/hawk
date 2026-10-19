import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../../../core/widgets/eye/eye_orb.dart';
import '../../../../core/widgets/hawk_kit.dart';
import '../../../billing/presentation/bloc/subscription_cubit.dart';
import '../../../billing/presentation/widgets/ask_limit_sheet.dart';
import '../../../chat/data/recent_finds.dart';
import '../../../chat/domain/entities/recent_find.dart';
import '../../../chat/presentation/widgets/result_file.dart';
import '../bloc/suggestions_cubit.dart';
import '../bloc/voice_cubit.dart';
import '../widgets/voice_orb.dart';
import '../widgets/voice_orb_state.dart';
import 'home_page.dart';
import 'result_stack_page.dart';

/// The orb face of home — `Hawk Logo v3.dc.html`, final block.
///
/// **Listening happens here, not on a screen of its own.** The design draws
/// 1N as a separate frame, and building it as a pushed route was a literal
/// reading of that drawing: the orb you pressed slid away and a second,
/// identical orb faded in somewhere else. Holding a button should not
/// navigate. The orb stays exactly where your thumb already is and the copy
/// underneath it changes — which is what 1N actually depicts, one screen in
/// two states rather than two screens.
///
/// **Both gestures work, and they are different gestures.**
///
/// * **Hold** — press, speak, let go. The design's own copy, and the one that
///   cannot leave a microphone open by accident.
/// * **Tap** — starts listening and *latches*; tap again to send. For anyone
///   who cannot hold a phone steady through a sentence, and for a long
///   question. A latched microphone is a real risk, so the screen says it is
///   open in three places at once: the pill, the meter and the instruction.
///
/// Which gesture is running is tracked, so letting go of a long press cannot
/// stop a session a tap started.
class VoiceHomeFace extends StatefulWidget {
  const VoiceHomeFace({
    this.autoStart = false,
    this.recent,
    this.rowEndInset = 0,
    this.rowBottomInset = 0,
    super.key,
  });

  /// Open the microphone as soon as the face is up.
  ///
  /// Set when a microphone somewhere else was tapped, so the permission
  /// prompt — if it appears — belongs to a tap the user just made rather than
  /// arriving unexplained.
  final bool autoStart;

  /// The last questions that found something, for the LAST FOUND row. Null
  /// shows the suggestions alone — the face does not need a store to work.
  final RecentFinds? recent;

  /// Width kept clear at the end of the chip row, for something home floats
  /// there — the camera, which sits on the row's centre line (see
  /// [homeChipRowHeight]). Chips stop short of it instead of sliding under.
  final double rowEndInset;

  /// Space under the chip row, so something taller centred on it still ends
  /// above the nav band. The shell paints the band over the page, so
  /// whatever reaches into it is cut off — the camera's lower edge was.
  final double rowBottomInset;

  @override
  State<VoiceHomeFace> createState() => _VoiceHomeFaceState();
}

class _VoiceHomeFaceState extends State<VoiceHomeFace>
    with WidgetsBindingObserver {
  /// True while the microphone is open because a finger is still down.
  ///
  /// The whole reason to track it: `onLongPressEnd` fires for whichever
  /// gesture began, and without this someone who tapped to latch and then
  /// rested a finger on the orb would have their sentence cut off by letting
  /// go of it.
  bool _holding = false;

  /// Owned by the route, not this face, so it outlives a switch to typing —
  /// read up front because [dispose] may not look up the tree.
  late final VoiceCubit _voice;

  /// Whether the eye was in front of the user at the last check.
  bool _onScreen = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _voice = context.read<VoiceCubit>();
    unawaited(widget.recent?.load());
    if (!widget.autoStart) return;
    // After the first frame: `_start` reads cubits, and reading one during
    // `initState` builds a widget that is still building.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_start(held: false));
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The shell keeps home mounted behind other tabs, and a pushed screen
    // leaves it mounted underneath — so the microphone stayed open after the
    // user had gone somewhere else. Both turn TickerMode off (the shell's
    // stack for a hidden tab, the overlay for a covered route): one signal
    // for "the eye is no longer in front of the user".
    final onScreen = TickerMode.valuesOf(context).enabled;
    if (_onScreen && !onScreen) _abandon();
    _onScreen = onScreen;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Sent to the background mid-sentence: nobody is listening any more.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _abandon();
    }
  }

  /// Close the microphone and forget the half-heard words. A no-op when the
  /// eye is not listening.
  void _abandon() {
    if (_holding && mounted) setState(() => _holding = false);
    unawaited(_voice.abandonDictation());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // The face switched to typing, or home went away: same rule.
    unawaited(_voice.abandonDictation());
    super.dispose();
  }

  Future<void> _start({required bool held}) async {
    final cubit = context.read<VoiceCubit>();
    if (cubit.state.phase == VoicePhase.listening) return;

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

    setState(() => _holding = held);
    await cubit.toggleDictation();
  }

  /// Send what was heard. Safe to call twice — [VoiceCubit.release] no-ops
  /// once the microphone is already closed.
  Future<void> _send() async {
    if (mounted) setState(() => _holding = false);
    await context.read<VoiceCubit>().release();
  }

  /// A tap means start, or — if this face is already listening — send.
  void _tapped(VoiceState state) {
    if (state.phase == VoicePhase.listening) {
      unawaited(_send());
    } else {
      unawaited(_start(held: false));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return BlocConsumer<VoiceCubit, VoiceState>(
      listenWhen: (a, b) => a.finished != b.finished && b.finished != null,
      listener: (context, state) {
        final question = state.finished!;
        final voice = context.read<VoiceCubit>();
        // With the files already found for these exact words, the result
        // screen opens with them and fetches only the answer; otherwise it
        // searches for itself. See [VoiceCubit.seedFor].
        final Object extra = voice.seedFor(question) ?? question;
        // Cleared immediately, so one held orb cannot open two result screens
        // if this rebuilds before the push completes.
        voice.handedOff();
        // The question travels as `extra` rather than in the path: it is free
        // text somebody just spoke, and a URL would mean escaping it, capping
        // its length, and leaving it in navigation history.
        unawaited(context.pushNamed(ResultStackPage.routeName, extra: extra));
      },
      builder: (context, state) {
        final listening = state.phase == VoicePhase.listening;

        // The face gets whatever height the screen has left, and on a short
        // phone — or with the keyboard still animating away after the chat
        // field's mic button — that can be far less than the eye plus its
        // copy. It overflowed by 48px, then 142px. Two defences, in order:
        //
        //  1. The eye shrinks to fit, but never below the handoff's 190px
        //     floor, under which the brow and the notch stop reading.
        //  2. Past that, the face scrolls. A scroll is recoverable; a
        //     striped overflow is content the user cannot reach at all.
        final face = LayoutBuilder(
          builder: (context, box) {
            final orb = (box.maxHeight - _chrome)
                .clamp(EyeOrb.minSize, _orbFull)
                .toDouble();

            return SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: ConstrainedBox(
                // At least the full height, so a face that fits is still
                // centred exactly as before; taller only when it has to be.
                constraints: BoxConstraints(minHeight: box.maxHeight),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // The live indicator sits above the orb rather than in the
                    // header, which on this screen belongs to the greeting. It is the
                    // first of the three things that say the microphone is open.
                    //
                    // It keeps its space when hidden, because a pill that appeared
                    // out of nowhere would shove the eye down at the exact moment
                    // the user is watching it. That reservation is paid for by
                    // [_pillMirror] at the bottom of this column — see there.
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 180),
                      opacity: listening ? 1 : 0,
                      child: const StatusPill(
                        label: 'Listening',
                        showDot: true,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.inset),

                    GestureDetector(
                      // A long press does not also fire `onTap`, so the two gestures
                      // cannot both act on one press.
                      onTap: () => _tapped(state),
                      onLongPressStart: (_) => unawaited(_start(held: true)),
                      onLongPressEnd: (_) {
                        if (_holding) unawaited(_send());
                      },
                      // A press cancelled by a drag off the orb, or by a call
                      // arriving, must not leave the microphone open with nobody
                      // watching it.
                      onLongPressCancel: () {
                        if (_holding) unawaited(_send());
                      },
                      child: EyeOrb(
                        // 224px on the logo doc's home block.
                        //
                        // The box stays 224 through listening, although the design
                        // draws that screen at 236. The design has two screens; we
                        // have one, because the user asked to listen in place. A box
                        // that grew on the first syllable would shove the headline
                        // below it down every time. The eye's own `scale` knob does
                        // the pop instead, inside a box that never moves.
                        size: orb,
                        state: state.phase.orbState,
                        level: state.level,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.blockWide),

                    // The copy grows when the microphone opens — the transcript and
                    // the meter are taller than two lines of instruction. Animating
                    // the size turns what was a jump into a glide that runs with the
                    // eye's own pop, so the two read as one movement.
                    AnimatedSize(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                      alignment: Alignment.topCenter,
                      child: listening
                          ? _Listening(state: state, holding: _holding)
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Headline(
                                  'Hold to ask',
                                  size: 30,
                                  align: TextAlign.center,
                                ),
                                const SizedBox(height: AppSpacing.gap + 1),
                                Text(
                                  state.speechNote ??
                                      // 1Y's line. Tapping still latches the
                                      // microphone; the design chose to
                                      // spend this line on what an answer
                                      // *is* rather than on the gesture.
                                      'Answers open the actual file.',
                                  textAlign: TextAlign.center,
                                  style: AppTypography.bodyMedium.copyWith(
                                    height: 1.4,
                                    color: state.speechNote != null
                                        ? p.danger
                                        : p.textTertiary,
                                  ),
                                ),
                              ],
                            ),
                    ),

                    // Balances the pill's reserved slot at the top.
                    //
                    // Without it, `MainAxisAlignment.center` centres the pill's empty
                    // 50pt along with everything else, so the *visible* middle — the
                    // eye and the copy — sits half a pill low and the gap above the
                    // eye is a whole pill larger than the gap below it. That is
                    // exactly how it looked on device. The design's home block
                    // centres the orb and the copy and has no pill at all; this
                    // mirror is how we keep the pill's reservation without paying
                    // for it twice.
                    const SizedBox(height: _pillSlot),
                  ],
                ),
              ),
            );
          },
        );

        // 1Y's chips sit under the face, just above the nav. Hidden while
        // listening: the screen is then about one thing, and a row of other
        // questions under a live microphone is a second screen competing
        // with the first.
        return Column(
          children: [
            Expanded(child: face),
            if (!listening)
              Padding(
                padding: EdgeInsets.only(bottom: widget.rowBottomInset),
                child: _BottomRow(
                  recent: widget.recent,
                  endInset: widget.rowEndInset,
                  onAsk: _ask,
                  // A replay, not a question: no ask is spent reopening what
                  // was already found. See [AnswerCubit.replay].
                  onOpen: (find) => unawaited(
                    context.pushNamed(ResultStackPage.routeName, extra: find),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// A chip tapped: the same question-asking path a release takes, and the
  /// same allowance gate first — a chip is not a way round 1W.
  Future<void> _ask(String question) async {
    final plan = context.read<SubscriptionCubit>().state;
    final lock = plan.askLock;
    if (lock != null) {
      unawaited(AskLimitSheet.showFor(context, plan));
      return;
    }
    unawaited(context.pushNamed(ResultStackPage.routeName, extra: question));
  }
}

/// The row above the nav: LAST FOUND once there is anything to reopen, the
/// suggestions until then.
///
/// **Reopening is free.** These chips used to be questions — tapping one
/// asked the server again and spent an ask, even when it was the thing the
/// user had just found. Now the last two finds are kept on this phone and a
/// chip replays one, answer and files, without a call.
class _BottomRow extends StatelessWidget {
  const _BottomRow({
    required this.recent,
    required this.endInset,
    required this.onAsk,
    required this.onOpen,
  });

  final RecentFinds? recent;
  final double endInset;
  final ValueChanged<String> onAsk;
  final ValueChanged<RecentFind> onOpen;

  @override
  Widget build(BuildContext context) {
    final store = recent;
    if (store == null) return _Suggestions(onAsk: onAsk, endInset: endInset);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => store.items.isEmpty
          ? _Suggestions(onAsk: onAsk, endInset: endInset)
          : _LastFound(finds: store.items, onOpen: onOpen, endInset: endInset),
    );
  }
}

/// The chip row's height, under both labels — LAST FOUND and ASK ABOUT A
/// RECENT FILE. Home centres its camera on this row, so the two must not
/// drift apart.
const double homeChipRowHeight = 40;

/// The last two finds, newest first — each reopens as it was answered.
class _LastFound extends StatelessWidget {
  const _LastFound({
    required this.finds,
    required this.onOpen,
    this.endInset = 0,
  });

  final List<RecentFind> finds;
  final ValueChanged<RecentFind> onOpen;
  final double endInset;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const MetaText('Last found'),
          const SizedBox(height: AppSpacing.sm),
          Container(
            height: homeChipRowHeight,
            padding: EdgeInsets.only(right: endInset),
            child: Row(
              // Full height: a chip is the row's 40px, not its text's.
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, find)
                    in finds.take(RecentFinds.keep).indexed) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Flexible(
                    child: Semantics(
                      button: true,
                      label: 'Open what you found for: ${find.question}',
                      excludeSemantics: true,
                      child: Material(
                        color: p.card,
                        shape: const StadiumBorder(),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => onOpen(find),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 15),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                AppIcon(
                                  hawkIconForMemory(find.leadType),
                                  size: 15,
                                  color: p.textSecondary,
                                ),
                                const SizedBox(width: 7),
                                Flexible(
                                  child: Text(
                                    find.question,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTypography.bodySmall.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: p.textPrimary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Screen 1Y's chips — three things to ask, from this user's own library.
///
/// **Labelled, which the design is not.** 1Y's chips are "Pricing we
/// agreed", "Lease PDF", "Standup" — topics that explain themselves. Real
/// ones are built from real files, and a bare row of file names parked on
/// the nav read as a banner about something found, not an offer to ask. The
/// label says what the row is; the icon says what each file is.
class _Suggestions extends StatelessWidget {
  const _Suggestions({required this.onAsk, this.endInset = 0});

  final ValueChanged<String> onAsk;
  final double endInset;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return BlocBuilder<SuggestionsCubit, List<Suggestion>>(
      builder: (context, suggestions) {
        if (suggestions.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const MetaText('Ask about a recent file'),
              const SizedBox(height: AppSpacing.sm),
              // Inset outside the list, not as its padding: padding would
              // still let chips scroll under whatever sits at the end.
              Container(
                height: homeChipRowHeight,
                padding: EdgeInsets.only(right: endInset),
                // The last 20px fade out, so a chip cut by the row's end
                // reads as "more this way" rather than as broken — the
                // screen's edge used to say that on its own.
                child: ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (bounds) => LinearGradient(
                    colors: const [Colors.white, Colors.transparent],
                    stops: [1 - 20 / bounds.width, 1],
                  ).createShader(bounds),
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: suggestions.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, i) {
                      final s = suggestions[i];
                      return Semantics(
                        button: true,
                        label: s.question,
                        excludeSemantics: true,
                        child: Material(
                          color: p.card,
                          shape: const StadiumBorder(),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => onAsk(s.question),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 15,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  AppIcon(
                                    hawkIconForMemory(s.type),
                                    size: 15,
                                    color: p.textSecondary,
                                  ),
                                  const SizedBox(width: 7),
                                  Text(
                                    s.chip,
                                    style: AppTypography.bodySmall.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: p.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The height the listening pill reserves above the eye: the pill itself and
/// the gap under it.
const double _pillSlot = AppSize.statusPill + AppSpacing.inset;

/// The eye at the design's own size, when there is room for it.
const double _orbFull = 224;

/// Everything on the face that is not the eye: the pill slot, its mirror,
/// the gap, and the copy **at its tallest** — the listening transcript and
/// meter, not the two resting lines. Sized for the tallest state on purpose,
/// so the eye does not change size the moment somebody presses it.
const double _chrome = _pillSlot * 2 + AppSpacing.blockWide + 140;

/// Screen 1N's middle, rendered in place: the words, the meter, the way out.
class _Listening extends StatelessWidget {
  const _Listening({required this.state, required this.holding});

  final VoiceState state;

  /// A finger is still down, so the instruction is "let go" rather than "tap
  /// again". Getting this backwards leaves somebody holding an orb waiting
  /// for something to happen.
  final bool holding;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final heard = state.transcript.trim();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Quoted, because these are *reported speech* — what the phone
        // believes it heard, which the user is checking rather than reading.
        Text(
          heard.isEmpty ? 'Listening…' : '\u201C$heard\u201D',
          textAlign: TextAlign.center,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.display28.copyWith(
            color: heard.isEmpty ? p.textTertiary : p.textPrimary,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        VoiceBars(active: true, level: state.level),
        const SizedBox(height: AppSpacing.md),
        Text(
          holding ? 'Release to search' : 'Tap the orb to search',
          textAlign: TextAlign.center,
          style: AppTypography.bodyMedium.copyWith(color: p.textMuted),
        ),
      ],
    );
  }
}

/// The root route's old name, kept so nothing outside lane C has to move yet.
///
/// `/` belongs to [HomePage] now, which opens the orb face or the chat face
/// depending on what the account chose on screen 1F. This shim keeps the
/// symbol the router and `test/app/route_paths_test.dart` name, and forwards
/// to it — so wiring the router to [HomePage] is a rename rather than a
/// migration, and forgetting to do it still lands on the right screen.
///
/// Not marked `@Deprecated`: the router and two test files still name it, and
/// an annotation here would turn lanes that have not moved yet into analyzer
/// noise. Delete the class once `/` builds [HomePage] directly.
class VoiceHomePage extends StatelessWidget {
  const VoiceHomePage({this.startListening = false, super.key});

  static const routeName = HomePage.routeName;
  static const routePath = HomePage.routePath;

  final bool startListening;

  @override
  Widget build(BuildContext context) =>
      HomePage(startListening: startListening);
}
