import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/router/pop_or.dart';
import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/widgets/app_screen.dart';
import '../../../../core/widgets/hawk_icons.dart';
import '../../../../core/widgets/hawk_kit.dart';
import '../../../voice/presentation/pages/home_page.dart';
import '../bloc/answer_cubit.dart';
import '../widgets/ask_field.dart';
import '../widgets/chat_thread.dart';

/// Screen 1P — CHAT, ANSWER + FILE.
///
/// The typed half of search, and the answer to a question a voice user asked
/// a follow-up to. A thread of bubbles, the files underneath, and an ask bar.
///
/// **Citations are rows now, not superscripts.** v2 rendered a numbered
/// superscript inline at each claim and listed the sources at the bottom with
/// a relevance score and a provenance line each. The promise behind that —
/// architecture §28, every answer traceable to the file it came from — is
/// unchanged and is still the difference between this and a chatbot. What
/// changed is how it is kept: the file sits directly under the answer, on a
/// **white card**, one tap from opening. A superscript tells you a source
/// exists; a card you can press is the source. The scores, the excerpts and
/// the confidence meter are gone with them, because none of them were the
/// evidence — they were commentary on the retrieval.
///
/// **No nav.** Unlike screen 1O, the design draws no nav pill here: a thread
/// is a conversation you are inside, and the way out is the back circle. So
/// this stays a route pushed above the tab shell.
class AnswerPage extends StatefulWidget {
  const AnswerPage({super.key});

  static const routeName = 'answer';
  static const routePath = '/answer';

  @override
  State<AnswerPage> createState() => _AnswerPageState();
}

class _AnswerPageState extends State<AnswerPage> {
  final _followUp = TextEditingController();
  final _thread = ScrollController();

  @override
  void dispose() {
    _followUp.dispose();
    _thread.dispose();
    super.dispose();
  }

  void _submit(BuildContext context, String value) {
    final text = value.trim();
    if (text.isEmpty) return;
    _followUp.clear();
    FocusScope.of(context).unfocus();
    context.read<AnswerCubit>().followUp(text);
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
        return AppScreen(
          ambientOpacity: 0,
          scrollable: false,
          footer: AskField(
            controller: _followUp,
            enabled: !state.isBusy,
            onSubmit: (value) => _submit(context, value),
            // No microphone here. [VoiceCubit] belongs to the home branch and
            // this route sits above the shell, so the circle is the send
            // arrow throughout — see [AskField].
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _Header(),
              const SizedBox(height: AppSpacing.lg),
              Expanded(
                child: ChatThread(state: state, controller: _thread),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Back, "Ask", and a plus that starts a fresh thread.
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return Row(
      children: [
        CircleButton(
          icon: HawkIcons.chevronLeft,
          semanticLabel: 'Back',
          onPressed: () => context.popOrGo(HomePage.routeName),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(
            // "Ask", not the question. The question is the first bubble in
            // the thread, two centimetres below — printing it twice would
            // make the header a duplicate of the content it introduces.
            'Ask',
            style: AppTypography.display18.copyWith(color: p.textPrimary),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        CircleButton(
          icon: HawkIcons.plus,
          semanticLabel: 'Ask something new',
          // A new thread, not a new bubble. [AnswerCubit] holds one
          // conversation and is scoped to this route, so leaving the route is
          // what starts a fresh one — and home is where a new question is
          // asked from.
          onPressed: () => context.popOrGo(HomePage.routeName),
        ),
      ],
    );
  }
}
