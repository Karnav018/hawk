import 'package:flutter/material.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../../../core/widgets/hawk_icons.dart';

/// The ask bar: a card-filled field and one accent circle.
///
/// The design's chat footer, used unchanged on the chat home and on screen
/// 1P. Two things, and the accent is on the circle — which is the screen's
/// one accented element, because asking is the only thing this bar does.
///
/// **The circle changes glyph, and that is deliberate.** The design draws a
/// microphone, which is right for an empty field: the fastest way to ask a
/// long question is to say it. Once there are words in the field a microphone
/// is the wrong promise — pressing it would either discard what was typed or
/// do nothing — so it becomes the send arrow. One control, two states, and
/// never a dead tap target.
///
/// A screen with no microphone available at all (screen 1P, whose route sits
/// outside the branch that owns [VoiceCubit]) passes no [onMic] and gets the
/// arrow throughout.
///
/// **A tap anywhere else puts the keyboard away.** Flutter's own rule for a
/// text field is to drop focus on a tap outside only on desktop and the
/// web; on a phone the keyboard stays up until something else takes focus,
/// which on this screen was nothing — so once opened, the keyboard sat over
/// the thread until a question was sent. The bar's own circle is grouped
/// *with* the field: a tap on Send or the microphone is not a tap outside,
/// and each of those decides for itself what happens to the keyboard.
class AskField extends StatelessWidget {
  const AskField({
    required this.controller,
    required this.onSubmit,
    this.onMic,
    this.hint = 'Ask a follow-up…',
    this.enabled = true,
    super.key,
  });

  final TextEditingController controller;
  final ValueChanged<String> onSubmit;

  /// Null where dictation cannot be reached from this screen.
  final VoidCallback? onMic;

  final String hint;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Container(
            height: AppSize.button,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.cardWide,
            ),
            decoration: BoxDecoration(
              color: p.card,
              borderRadius: BorderRadius.circular(AppRadius.round),
            ),
            alignment: Alignment.center,
            child: TextField(
              controller: controller,
              enabled: enabled,
              textInputAction: TextInputAction.send,
              onSubmitted: onSubmit,
              groupId: AskField,
              // Only ever called while this field has the focus, so the
              // primary focus is this field.
              onTapOutside: (_) =>
                  FocusManager.instance.primaryFocus?.unfocus(),
              style: AppTypography.bodyLarge.copyWith(
                height: 1.2,
                color: p.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: AppTypography.bodyLarge.copyWith(
                  height: 1.2,
                  color: p.textFaint,
                ),
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                isDense: true,
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.gap),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) {
            final hasText = value.text.trim().isNotEmpty;
            final speaks = onMic != null && !hasText;

            return TapRegion(
              groupId: AskField,
              child: Semantics(
                button: true,
                label: speaks ? 'Ask out loud' : 'Send',
                child: Material(
                  color: p.accent,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: !enabled
                        ? null
                        : speaks
                        ? onMic
                        : hasText
                        ? () => onSubmit(value.text)
                        : null,
                    child: SizedBox(
                      width: AppSize.button,
                      height: AppSize.button,
                      child: Center(
                        child: AppIcon(
                          speaks ? HawkIcons.mic : HawkIcons.arrowRight,
                          size: 22,
                          color: p.onAccent,
                          strokeWidth: 2.1,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
