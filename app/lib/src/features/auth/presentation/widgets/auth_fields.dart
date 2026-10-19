import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/widgets/hawk_icons.dart';
import '../../../../core/widgets/hawk_kit.dart';

/// The v3 input: a 60px pill, card-filled, with a 1.5px accent ring on focus.
///
/// No border at rest. v2 drew a hairline around every field; v3 lets the fill
/// do that job, so an unfocused field is a shape rather than an outline, and
/// the only ring on the screen belongs to the field you are typing in.
class VaultTextField extends StatelessWidget {
  const VaultTextField({
    required this.controller,
    this.hintText,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.autofillHints,
    this.autofocus = false,
    this.hasError = false,
    this.onChanged,
    this.onSubmitted,
    this.onBlur,
    super.key,
  });

  final TextEditingController controller;
  final String? hintText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final Iterable<String>? autofillHints;
  final bool autofocus;
  final bool hasError;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// Fired when focus leaves — when a validation message should appear.
  final VoidCallback? onBlur;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return Focus(
      onFocusChange: (hasFocus) {
        if (!hasFocus) onBlur?.call();
      },
      child: SizedBox(
        height: AppSize.input,
        child: TextField(
          controller: controller,
          autofocus: autofocus,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          textCapitalization: textCapitalization,
          autofillHints: autofillHints,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          cursorColor: p.accent,
          cursorWidth: 2,
          style: AppTypography.bodyLarge.copyWith(
            fontSize: 16,
            color: p.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: hintText,
            // The error ring replaces the focus ring rather than stacking
            // with it; the theme already draws both at the same width.
            enabledBorder: hasError ? _ring(p.danger) : null,
            focusedBorder: hasError ? _ring(p.danger) : null,
          ),
        ),
      ),
    );
  }

  static OutlineInputBorder _ring(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadius.round),
    borderSide: BorderSide(color: color, width: 1.5),
  );
}

/// The six-digit code field — screen 1E.
///
/// One real [TextField], held off-screen, with the boxes drawn over it. Six
/// separate fields look the same but fight the platform: autofill delivers the
/// whole code to one field, and moving focus per keystroke breaks backspace
/// and paste.
class CodeField extends StatefulWidget {
  const CodeField({
    required this.length,
    required this.value,
    required this.onChanged,
    this.onCompleted,
    this.hasError = false,
    this.autofocus = true,
    super.key,
  });

  final int length;
  final String value;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onCompleted;
  final bool hasError;
  final bool autofocus;

  @override
  State<CodeField> createState() => _CodeFieldState();
}

class _CodeFieldState extends State<CodeField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(CodeField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The cubit clears the code after a wrong attempt; mirror that here
    // without disturbing the field while someone is mid-type.
    if (widget.value != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Present to the platform, invisible to the eye.
        Opacity(
          opacity: 0,
          child: SizedBox(
            height: AppSize.codeBox,
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              autofocus: widget.autofocus,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              maxLength: widget.length,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (value) {
                widget.onChanged(value);
                if (value.length == widget.length) {
                  widget.onCompleted?.call(value);
                }
              },
            ),
          ),
        ),
        GestureDetector(
          onTap: () => _focusNode.requestFocus(),
          behavior: HitTestBehavior.opaque,
          child: Row(
            children: [
              for (var i = 0; i < widget.length; i++) ...[
                if (i > 0) const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _CodeBox(
                    digit: i < widget.value.length ? widget.value[i] : null,
                    isActive: i == widget.value.length,
                    hasError: widget.hasError,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _CodeBox extends StatelessWidget {
  const _CodeBox({
    required this.digit,
    required this.isActive,
    required this.hasError,
  });

  final String? digit;
  final bool isActive;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final filled = digit != null;

    return Container(
      height: AppSize.codeBox,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        // A box you have reached is [card]; one you have not is [cardDim].
        // The design uses that step rather than an outline to show progress
        // through the code, so an untyped box reads as *not yet* rather than
        // as empty.
        color: filled || isActive ? p.card : p.cardDim,
        borderRadius: BorderRadius.circular(AppRadius.code),
        border: hasError
            ? Border.all(color: p.danger, width: 1.5)
            : isActive
            ? Border.all(color: p.accent, width: 1.5)
            : null,
      ),
      child: filled
          ? Text(
              digit!,
              style: AppTypography.numeralCode.copyWith(color: p.textPrimary),
            )
          : isActive
          ? Container(width: 2, height: 24, color: p.accent)
          : null,
    );
  }
}

/// A message under a field: the validation error, or an advisory suggestion.
///
/// One widget for both so they can never both be shown at once — a field that
/// is simultaneously wrong and nearly-right is a confusing thing to look at.
class FieldNote extends StatelessWidget {
  const FieldNote({this.error, this.suggestion, this.onAccept, super.key});

  final String? error;

  /// "Did you mean sam@gmail.com?" — advisory, and never blocking.
  final String? suggestion;
  final VoidCallback? onAccept;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    if (error != null) {
      return Padding(
        padding: const EdgeInsets.only(
          top: AppSpacing.md,
          left: AppSpacing.cardWide,
        ),
        child: Text(
          error!,
          style: AppTypography.footnote.copyWith(color: p.danger),
        ),
      );
    }

    if (suggestion == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(
        top: AppSpacing.md,
        left: AppSpacing.cardWide,
      ),
      child: GestureDetector(
        onTap: onAccept,
        behavior: HitTestBehavior.opaque,
        child: Text.rich(
          TextSpan(
            style: AppTypography.footnote.copyWith(color: p.textTertiary),
            children: [
              const TextSpan(text: 'Did you mean '),
              TextSpan(
                text: suggestion,
                style: TextStyle(color: p.accent, fontWeight: FontWeight.w600),
              ),
              const TextSpan(text: '?'),
            ],
          ),
        ),
      ),
    );
  }
}

/// The primary action.
///
/// Kept as a name because half the product already calls it that; it is now
/// just a [PillButton] with the design's trailing arrow. Screens ported to v3
/// use [PillButton] directly, since not every primary action advances a run
/// and the arrow should only appear on the ones that do.
class PrimaryActionButton extends StatelessWidget {
  const PrimaryActionButton({
    required this.label,
    required this.onPressed,
    this.isBusy = false,
    this.showArrow = true,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isBusy;
  final bool showArrow;

  @override
  Widget build(BuildContext context) => PillButton(
    label: label,
    onPressed: onPressed,
    isBusy: isBusy,
    icon: showArrow ? HawkIcons.arrowRight : null,
  );
}
