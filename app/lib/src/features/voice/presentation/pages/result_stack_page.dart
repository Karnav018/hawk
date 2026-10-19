import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/pop_or.dart';
import '../../../../app/router/tab_shell.dart';
import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/di/injector.dart';
import '../../../../core/widgets/app_screen.dart';
import '../../../../core/widgets/hawk_icons.dart';
import '../../../../core/widgets/hawk_kit.dart';
import '../../../../core/widgets/vault_dock.dart';
import '../../../capture/presentation/pages/capture_page.dart';
import '../../../chat/presentation/bloc/answer_cubit.dart';
import '../../../chat/presentation/widgets/result_file.dart';
import '../../../connectors/presentation/pages/choose_folders_page.dart';
import '../../../memory/presentation/bloc/drive_files_cubit.dart';
import '../widgets/result_stack.dart';
import 'home_page.dart';

/// Screen 1O — VOICE, RESULT STACK.
///
/// Where a spoken question lands. Three things and no fourth: **the short
/// answer** on a white card, **the file** on the accent card under it, and
/// **where that file lives** in the two mono lines on the same card.
///
/// v2's answer screen is the instructive comparison. It showed the same
/// retrieval as inline superscripts, a four-bar confidence meter, a relevance
/// score per row, a provenance line per source and a filter summary — six
/// readouts about how the search had gone, wrapped around the one sentence
/// somebody asked for. v3 deletes all six. The claim it makes instead is
/// stronger and much harder to fake: here is the answer, here is the file it
/// came out of, open it and check.
///
/// **Still inside the tab shell.** The design draws the nav pill at the
/// bottom of 1O, unlike the chat screen — a result is somewhere you arrive,
/// not a mode you are trapped in — so this is registered as a child route of
/// the home branch and reserves [navClearance] rather than covering the nav.
class ResultStackPage extends StatelessWidget {
  const ResultStackPage({super.key});

  static const routeName = 'found';

  /// Relative, because it is registered **under** the home branch's route so
  /// the tab nav survives. The full location is `/found`.
  static const routePath = 'found';

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return BlocBuilder<AnswerCubit, AnswerState>(
      builder: (context, state) {
        final answer = state.answer;
        final files = resultFilesFor(
          citations: answer?.citations ?? const [],
          answered: answer != null,
        );

        // Screen 2A. Only once retrieval *and* generation have finished —
        // there are no files at all until the answer lands, and telling
        // somebody their library has nothing while it is still looking is
        // worse than saying nothing at all.
        final noMatch =
            !state.isBusy && files.isEmpty && state.exception == null;

        return AppScreen(
          ambientOpacity: 0,
          scrollable: false,
          // The nav pill floats over the body; the stack must stop above it.
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenSide,
            AppSpacing.screenTop,
            AppSpacing.screenSide,
            navClearance,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CircleButton(
                    icon: HawkIcons.chevronLeft,
                    semanticLabel: 'Back',
                    // Registered inside the home branch, so back is home
                    // whether or not the question was asked from there.
                    onPressed: () => context.popOrGo(HomePage.routeName),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      // Not the question: repeating back what somebody just
                      // said out loud spends the whole header on the one
                      // thing they have not forgotten. 2A retitles it,
                      // because "Found" over an empty screen is the app
                      // contradicting itself in its own header.
                      noMatch ? 'No match' : 'Found',
                      style: AppTypography.display18.copyWith(
                        color: p.textPrimary,
                      ),
                    ),
                  ),
                  if (files.isNotEmpty)
                    StatusPill(
                      label:
                          '${files.length} '
                          'file${files.length == 1 ? '' : 's'}',
                      // The count is accent because it is the screen's live
                      // fact. No dot: a count does not pulse.
                      color: p.accent,
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.inset),

              if (state.exception != null) ...[
                _Failed(
                  message: state.exception!.displayMessage,
                  onRetry: context.read<AnswerCubit>().ask,
                ),
                const Spacer(),
              ] else if (noMatch)
                Expanded(child: _NoMatch(question: state.question))
              else ...[
                _AnswerCard(
                  text: _shortAnswer(state),
                  isWaiting: answer == null,
                ),
                const SizedBox(height: AppSpacing.inset),
                Expanded(
                  // Nothing at all while the answer is being read: the card
                  // above already says "Reading your files…".
                  child: answer == null
                      ? const SizedBox.shrink()
                      : files.isEmpty
                      ? _NoFiles(isSearching: state.isSearching)
                      : ResultStack(files: files),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  /// The one sentence the white card carries.
  ///
  /// The **lead paragraph only**, which is a real editorial decision and not
  /// a truncation bug. The design gives 1O a fixed-height card with a single
  /// sentence in it because a spoken question deserves a spoken-length reply
  /// — and because the card cannot grow without eating the file stack, which
  /// is the half of the screen that can be verified. A model that writes four
  /// paragraphs is answering the typed screen's question, not this one.
  static String _shortAnswer(AnswerState state) {
    final answer = state.answer;
    if (answer == null) return 'Reading your files…';
    if (answer.blocks.isEmpty) {
      return answer.answered
          ? 'Nothing to add.'
          : 'Your vault does not answer that yet.';
    }
    final lead = answer.blocks.firstWhere(
      (b) => b.isLead,
      orElse: () => answer.blocks.first,
    );
    return lead.text;
  }
}

/// Screen 2A — NOTHING FOUND.
///
/// A dead end is where an app is most tempted to apologise and least able to
/// afford it. The design spends the screen on *why* instead: the question is
/// quoted back on the white card — here, uniquely, it earns the space,
/// because the user is about to be told it failed and needs to see what was
/// actually heard — and under it the three things that could be wrong, each
/// one a route rather than advice.
///
/// The first route is the one that matters. "Nothing matched" and "nothing
/// matched *in the tenth of your Drive you chose to index*" are completely
/// different facts, and only one of them is the user's problem to fix. So the
/// count is read live, and the row is **omitted entirely when it is zero or
/// unknown** — a row offering to index nothing, or an invented number, would
/// be worse than three routes becoming two.
class _NoMatch extends StatelessWidget {
  const _NoMatch({required this.question});

  final String question;

  @override
  Widget build(BuildContext context) {
    final paper = AppPalette.onPaper;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HawkCard(
          tone: CardTone.paper,
          padding: const EdgeInsets.all(AppSpacing.cardWide),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MetaText('YOU ASKED', color: paper.muted, wide: true),
              const SizedBox(height: AppSpacing.gap + 1),
              Text(
                // Quoted, as the design draws it: the marks are what make it
                // read as something said rather than as a heading.
                '"$question"',
                style: AppTypography.display22.copyWith(color: paper.ink),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Nothing in your library matches. It may not be indexed yet.',
                style: AppTypography.bodyMedium.copyWith(
                  height: 1.6,
                  color: paper.body,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.inset),

        const MetaText('TRY THIS'),
        const SizedBox(height: AppSpacing.gap + 1),

        // Scoped to this state, not to the screen: the Drive listing is a
        // network round trip, and it is only worth making once a search has
        // actually come back empty.
        BlocProvider<DriveFilesCubit>(
          create: (_) => getIt<DriveFilesCubit>(),
          child: BlocBuilder<DriveFilesCubit, DriveFilesState>(
            builder: (context, drive) =>
                NoMatchRoutes(unindexed: drive.totalCount - drive.indexedCount),
          ),
        ),

        const Spacer(),
        PillButton(
          label: 'Ask again',
          leadingIcon: HawkIcons.mic,
          height: AppSize.button,
          onPressed: () => context.goNamed(
            HomePage.routeName,
            extra: const StartDictation(),
          ),
        ),
      ],
    );
  }
}

/// The three ways out, in the design's order: widen the net, add the thing,
/// or look for it by name instead of by meaning.
class NoMatchRoutes extends StatelessWidget {
  @visibleForTesting
  const NoMatchRoutes({required this.unindexed, super.key});

  /// Drive files this account holds but has never indexed. Zero, or unknown
  /// because the listing has not come back, both mean the first row does not
  /// appear at all.
  final int unindexed;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return RowGroup(
      children: [
        if (unindexed > 0)
          HawkRow(
            icon: HawkIcons.googleDrive,
            // The only accent on this screen's rows. Accent means *this row
            // is offering you something*, and this is the one that can
            // actually turn a no into a yes.
            iconColor: p.accent,
            title: 'Index ${grouped(unindexed)} more Drive files',
            subtitle: 'Not searched yet',
            onTap: () => context.pushNamed(ChooseFoldersPage.routeName),
          ),
        HawkRow(
          icon: HawkIcons.plus,
          title: 'Add it now',
          subtitle: 'Scan, upload or paste a link',
          onTap: () => context.pushNamed(CapturePage.routeName),
        ),
      ],
    );
  }

  /// 9570 -> 9,570. The design groups it, and an ungrouped five-figure count
  /// reads as a file size.
  @visibleForTesting
  static String grouped(int n) => n.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (m) => '${m[1]},',
  );
}

/// The answer, on the one white card the screen is allowed.
class _AnswerCard extends StatelessWidget {
  const _AnswerCard({required this.text, required this.isWaiting});

  final String text;
  final bool isWaiting;

  @override
  Widget build(BuildContext context) {
    final paper = AppPalette.onPaper;

    return HawkCard(
      tone: CardTone.paper,
      padding: const EdgeInsets.all(AppSpacing.cardWide),
      child: Text(
        text,
        // Clamped rather than scrolled. A white card with its own scrollbar
        // stops being the one object on the screen that matters and becomes
        // a panel, and the files underneath are where a longer answer is
        // checked anyway.
        maxLines: 6,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.display24.copyWith(
          // The waiting line is set in the same size and place as the answer
          // it will become, so the card does not resize under the reader at
          // the moment they start reading.
          color: isWaiting ? paper.muted : paper.ink,
        ),
      ),
    );
  }
}

/// Generation failed. Deliberately *not* the white card.
///
/// The paper surface is the product saying "this is the thing that matters";
/// putting an error on it would make a failure the most important object on
/// the screen, when the files underneath may well still answer the question.
class _Failed extends StatelessWidget {
  const _Failed({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return HawkCard(
      padding: const EdgeInsets.all(AppSpacing.cardWide),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const MetaText('Could not answer'),
          const SizedBox(height: AppSpacing.sm),
          Text(
            message,
            style: AppTypography.bodyLarge.copyWith(color: p.textBright),
          ),
          const SizedBox(height: AppSpacing.inset),
          PillButton.secondary(
            label: 'Try again',
            height: AppSize.buttonSmall,
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}

/// Retrieval came back with nothing.
class _NoFiles extends StatelessWidget {
  const _NoFiles({required this.isSearching});

  final bool isSearching;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return Align(
      alignment: Alignment.topCenter,
      child: InfoNote(
        isSearching
            ? 'Looking through your vault…'
            // Said plainly. An empty vault is an ordinary outcome and the
            // next step belongs to the user, not to a retry button.
            : 'Nothing in your vault matches that yet. Capture more, or '
                  'connect storage, and ask again.',
        icon: isSearching ? null : HawkIcons.info,
        iconColor: p.textMuted,
      ),
    );
  }
}
