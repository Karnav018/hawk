import 'package:flutter/material.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';

/// One turn in the thread — screen 1P.
///
/// **The square corner is the whole device.** A user bubble is round except
/// at the bottom right, an assistant bubble except at the bottom left, so the
/// corner points back at whoever is speaking. That is why the design gets
/// away with no avatars, no names and no timestamps: the shape already says
/// who said it, and a thread of six bubbles reads without a single label.
///
/// The user's bubble is the accented one. It is the only accent in the
/// thread, and it is spent on what *you* said rather than on what the product
/// replied — v2 accented the answer, which made the machine the loudest voice
/// in its own transcript.
class ChatBubble extends StatelessWidget {
  const ChatBubble({
    required this.text,
    required this.isUser,
    this.isQuiet = false,
    super.key,
  });

  final String text;
  final bool isUser;

  /// A bubble that is present but not being read — an earlier turn, or the
  /// line that says the answer is still being written.
  final bool isQuiet;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    final radius = BorderRadius.only(
      topLeft: const Radius.circular(AppRadius.bubble),
      topRight: const Radius.circular(AppRadius.bubble),
      bottomLeft: Radius.circular(isUser ? AppRadius.bubble : AppRadius.tail),
      bottomRight: Radius.circular(isUser ? AppRadius.tail : AppRadius.bubble),
    );

    return LayoutBuilder(
      builder: (context, constraints) => Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          // 84% for the question, 90% for the answer. The answer is allowed
          // to be wider because it is the longer text and because a reply
          // that indents as far as the question looks like a quotation.
          constraints: BoxConstraints(
            maxWidth: constraints.maxWidth * (isUser ? 0.84 : 0.90),
          ),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: isUser ? AppSpacing.group : AppSpacing.inset,
            ),
            decoration: BoxDecoration(
              color: isUser
                  ? (isQuiet ? p.raised : p.accent)
                  : (isQuiet ? p.cardDim : p.card),
              borderRadius: radius,
            ),
            child: Text(
              text,
              style: AppTypography.bodyLarge.copyWith(
                color: isUser
                    ? (isQuiet ? p.textSecondary : p.onAccent)
                    : (isQuiet ? p.textMuted : p.textBright),
                // The question is set heavier than the answer: it is short,
                // it is the anchor the reply hangs off, and at the same
                // weight the two bubbles read as one paragraph split in half.
                fontWeight: isUser ? FontWeight.w600 : FontWeight.w400,
                fontVariations: [FontVariation('wght', isUser ? 600 : 400)],
                height: isUser ? 1.45 : 1.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
