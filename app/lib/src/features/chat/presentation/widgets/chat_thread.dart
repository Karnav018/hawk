import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/error/app_exception.dart';
import '../../../../core/widgets/hawk_kit.dart';
import '../../../billing/presentation/pages/paywall_page.dart';
import '../../domain/entities/answer.dart';
import '../bloc/answer_cubit.dart';
import 'chat_bubble.dart';
import 'result_file.dart';

/// The conversation itself — bubbles, then the files that back the answer.
///
/// Extracted because it is now on **two** screens and they are not variants
/// of each other: the chat face of home renders it in place, under the
/// Speak / Type tabs, and [AnswerPage] renders it as a pushed route with a
/// header. One list, two frames. Before this, typing a question on home
/// pushed a screen to show the reply — which made asking feel like leaving,
/// and is the thing this change removes.
class ChatThread extends StatelessWidget {
  const ChatThread({
    required this.state,
    required this.controller,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  final AnswerState state;
  final ScrollController controller;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final answer = state.answer;
    final files = resultFilesFor(
      citations: answer?.citations ?? const [],
      answered: answer != null,
    );

    return ListView(
      controller: controller,
      padding: padding,
      children: [
        // Earlier exchanges, oldest first and set quiet. A follow-up read
        // without what it followed is half a conversation; read at the same
        // weight as the current turn it buries it.
        for (final turn in state.turns) ...[
          ChatBubble(text: turn.question, isUser: true, isQuiet: true),
          const SizedBox(height: AppSpacing.md),
          if (turn.answer != null) ...[
            ChatBubble(
              text: prose(turn.answer!.blocks),
              isUser: false,
              isQuiet: true,
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ],

        ChatBubble(text: state.question, isUser: true),
        const SizedBox(height: AppSpacing.md),

        if (state.exception != null)
          ChatTrouble(exception: state.exception!)
        else if (answer != null)
          ChatBubble(text: prose(answer.blocks), isUser: false)
        else
          // The files land about a second after the question and the prose
          // several seconds after that, so this line holds the assistant's
          // place rather than a spinner holding the whole screen's.
          const ChatBubble(
            text: 'Reading your files…',
            isUser: false,
            isQuiet: true,
          ),

        // The files, under the answer they back.
        //
        // The first one is the white card. Which one is "first" is the
        // server's ordering, not a re-rank here: the screen must not decide
        // which file answered the question.
        for (var i = 0; i < files.length; i++) ...[
          const SizedBox(height: AppSpacing.md),
          FileRow(file: files[i], isPrimary: i == 0),
        ],
      ],
    );
  }
}

/// The whole answer, as one body of text.
///
/// Paragraphs joined rather than rendered as separate bubbles: a reply split
/// into three bubbles reads as three replies. Screen 1O takes only the lead
/// paragraph because a spoken question wants a spoken-length answer; the
/// thread is where the long form belongs.
String prose(List<AnswerBlock> blocks) =>
    blocks.isEmpty ? 'Nothing to add.' : blocks.map((b) => b.text).join('\n\n');

/// Keeps the newest turn in view.
///
/// A thread that grows off the bottom of the screen while the user watches is
/// the one way a chat can lose an answer it successfully produced. Deferred a
/// frame because the list has not been laid out with the new bubble in it at
/// the moment the state changes.
void scrollThreadToEnd(ScrollController controller) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!controller.hasClients) return;
    controller.animateTo(
      controller.position.maxScrollExtent,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  });
}

/// A failed turn, in the thread where the reply would have been.
///
/// A card rather than a snack: the question is still on screen above it, and
/// an error that floats away leaves a bubble with nothing under it.
class ChatTrouble extends StatelessWidget {
  const ChatTrouble({required this.exception, super.key});

  final AppException exception;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final upgradeable = _offersUpgrade(exception);

    return HawkCard(
      radius: AppRadius.bubble,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            exception.displayMessage,
            style: AppTypography.bodyLarge.copyWith(color: p.danger),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              PillButton.secondary(
                label: 'Try again',
                height: AppSize.chipAction,
                onPressed: context.read<AnswerCubit>().ask,
              ),
              if (upgradeable) ...[
                const SizedBox(width: AppSpacing.gap),
                InlineChip(
                  label: 'See plans',
                  height: AppSize.chipAction,
                  isAccent: true,
                  onPressed: () => context.pushNamed(PaywallPage.routeName),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Whether this failure is one an upgrade would actually solve.
///
/// The free tier's four a day is a product boundary — the answer is a bigger
/// plan. A paid tier's fair-use ceiling is abuse protection, and telling a
/// paying subscriber to upgrade because a script drained their day would be
/// both useless and insulting.
bool _offersUpgrade(AppException error) {
  final message = error.displayMessage;
  return message.contains('questions') && !message.contains('unusually high');
}
