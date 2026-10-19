import 'package:flutter/material.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/widgets/app_icons.dart';
import 'upload_icons.dart';

/// The one blue thing on the Library (F1·1).
///
/// It replaces the six quick-add tiles, so the screen reads as your things
/// rather than as a set of filters. Four states from the design's parts
/// sheet: idle, pressed, busy while files are going up, and locked when the
/// vault is full (E10).
///
/// **Busy is not disabled.** Somebody watching three photos go up can still
/// add a PDF; the queue takes it behind them. The spinner is information,
/// not a lock.
///
/// **Locked still answers.** A full vault greys the button and rewrites its
/// label so it explains itself, but a tap opens the storage sheet with the
/// two ways out — a button that did nothing at all would be the one dead end
/// on the screen.
class UploadButton extends StatefulWidget {
  const UploadButton({
    required this.onPressed,
    this.uploading = 0,
    this.locked = false,
    super.key,
  });

  final VoidCallback onPressed;

  /// Files still going up. Zero is idle.
  final int uploading;

  final bool locked;

  @override
  State<UploadButton> createState() => _UploadButtonState();
}

class _UploadButtonState extends State<UploadButton> {
  bool _pressed = false;

  /// The design's pressed fill — the accent a shade down, not a ripple.
  static const _pressedFill = Color(0xFF3FB9E8);

  void _press(bool down) {
    if (_pressed != down) setState(() => _pressed = down);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final locked = widget.locked;
    final busy = !locked && widget.uploading > 0;

    final fill = locked
        ? p.cardDim
        : _pressed
        ? _pressedFill
        : p.accent;
    final ink = locked ? p.textFaint : p.onAccent;

    final label = locked
        ? 'Upload — storage full'
        : busy
        ? 'Uploading ${widget.uploading} '
              'file${widget.uploading == 1 ? '' : 's'}…'
        : 'Upload';

    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTapDown: (_) => _press(true),
        onTapUp: (_) => _press(false),
        onTapCancel: () => _press(false),
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _pressed && !locked ? 0.97 : 1,
          duration: const Duration(milliseconds: 90),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 90),
            height: AppSize.button,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(AppRadius.round),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (busy)
                  SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(ink),
                      backgroundColor: ink.withValues(alpha: 0.25),
                    ),
                  )
                else
                  AppIcon(
                    locked ? UploadIcons.lock : UploadIcons.upload,
                    size: locked ? 18 : 19,
                    color: ink,
                    strokeWidth: 2.1,
                  ),
                const SizedBox(width: 10),
                Text(label, style: AppTypography.button.copyWith(color: ink)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
