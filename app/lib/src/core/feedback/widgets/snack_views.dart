import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_typography.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/hawk_mark.dart';
import '../snack.dart';
import 'snack_surface.dart';

/// Picks the presentation for a snack. One place, so a new case cannot be
/// added to the union without being drawn.
///
/// Every treatment is `Hawk Snackbars.dc.html` section 2 — "Top island":
/// black capsules on a hairline, a 32px lead circle, 14/700 white text, one
/// cyan accent, and red only where something failed.
class SnackView extends StatelessWidget {
  const SnackView({required this.snack, required this.onDismiss, super.key});

  final Snack snack;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: snack.semanticLabel,
      child: switch (snack) {
        ConfirmationSnack() => _Confirmation(
          snack as ConfirmationSnack,
          onDismiss,
        ),
        DetailSnack() => _Detail(snack as DetailSnack, onDismiss),
        ProgressSnack() => _Progress(snack as ProgressSnack, onDismiss),
        AssistantSnack() => _Assistant(snack as AssistantSnack, onDismiss),
        UndoSnack() => _Undo(snack as UndoSnack, onDismiss),
      },
    );
  }
}

/// How much of a snack's *content* is showing.
///
/// 1 except while a snack grows out of the Dynamic Island: then the black
/// shape stretches first and the words arrive once it has mostly formed, so
/// nobody sees text squashed inside a half-grown capsule. Provided by the
/// host's transition; absent everywhere else, where content simply shows.
class SnackReveal extends InheritedWidget {
  const SnackReveal({required this.reveal, required super.child, super.key});

  final Animation<double> reveal;

  static Animation<double> of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SnackReveal>()?.reveal ??
      kAlwaysCompleteAnimation;

  @override
  bool updateShouldNotify(SnackReveal old) => old.reveal != reveal;
}

/// Content that fades with [SnackReveal].
class _Revealed extends StatelessWidget {
  const _Revealed({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: SnackReveal.of(context), child: child);
}

/// Runs an action, then clears the snack — one tap, one outcome.
VoidCallback _andDismiss(VoidCallback action, VoidCallback dismiss) => () {
  action();
  dismiss();
};

// ===========================================================================
// 2A — confirmation
// ===========================================================================

/// "Saved — reading it now." Hugs its text, one line, 4s.
class _Confirmation extends StatelessWidget {
  const _Confirmation(this.snack, this.onDismiss);

  final ConfirmationSnack snack;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final action = snack.action;

    return SnackSurface(
      // 18 after bare text; 10 when an action ends the row (the design's
      // "Ready to ask · Ask").
      padding: EdgeInsets.only(left: 8, right: action == null ? 18 : 10),
      child: _Revealed(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _LeadCircle(
              color: p.accent,
              child: AppIcon(_Glyph.check, size: 16, color: p.onAccent),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                snack.message,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: snackTitleStyle(context),
              ),
            ),
            if (action != null) ...[
              const SizedBox(width: 10),
              _ActionFor(action: action, onDismiss: onDismiss),
            ],
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// 2B — detail
// ===========================================================================

/// A name and a state — "Could not connect / Google Drive didn't respond."
/// Grows to two lines in the same radius family, 4s.
class _Detail extends StatelessWidget {
  const _Detail(this.snack, this.onDismiss);

  final DetailSnack snack;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final action = snack.action;

    return SizedBox(
      width: double.infinity,
      child: SnackSurface(
        radius: 26,
        padding: const EdgeInsets.fromLTRB(10, 10, 14, 12),
        child: _Revealed(
          // Intrinsic so the action can centre on the card's full height —
          // the design's `align-self: center` — while the mark and the text
          // stay top-aligned. A subtitle that wraps to two lines moves the
          // action down with the middle, not with the first line.
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.topCenter,
                  child: _MarkCircle(mark: snack.mark),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          snack.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: snackTitleStyle(context),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          snack.subtitle,
                          style: snackSubtitleStyle(context),
                        ),
                      ],
                    ),
                  ),
                ),
                if (action != null) ...[
                  const SizedBox(width: 10),
                  Center(
                    child: _ActionFor(action: action, onDismiss: onDismiss),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The detail's lead circle, by [SnackMark]. Red only for a failure.
class _MarkCircle extends StatelessWidget {
  const _MarkCircle({required this.mark});

  final SnackMark mark;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return switch (mark) {
      SnackMark.failure => _LeadCircle(
        color: p.danger,
        child: AppIcon(_Glyph.exclaim, size: 16, color: p.onAccent),
      ),
      SnackMark.info => _LeadCircle(
        color: p.raised,
        child: AppIcon(_Glyph.info, size: 16, color: p.textPrimary),
      ),
      SnackMark.clock => _LeadCircle(
        color: p.raised,
        child: AppIcon(_Glyph.clock, size: 16, color: p.accent),
      ),
      SnackMark.file => _LeadCircle(
        color: p.raised,
        child: AppIcon(_Glyph.file, size: 15, color: p.textPrimary),
      ),
      SnackMark.busy => _LeadCircle(
        color: p.raised,
        child: _Spinner(color: p.accent),
      ),
      SnackMark.offline => _LeadCircle(
        color: p.raised,
        child: AppIcon(_Glyph.offline, size: 16, color: p.textPrimary),
      ),
    };
  }
}

// ===========================================================================
// 2C — progress
// ===========================================================================

/// Persistent status: ring, numeral, and the only × in the system.
class _Progress extends StatelessWidget {
  const _Progress(this.snack, this.onDismiss);

  final ProgressSnack snack;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final fraction = snack.fraction.clamp(0.0, 1.0);

    return SnackSurface(
      // No right padding of its own: the × carries it, inside a 32px target
      // — 10 from the percentage and 8 from the edge, as drawn.
      padding: const EdgeInsets.only(left: 8),
      child: _Revealed(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Ring(
              value: fraction,
              color: p.accent,
              track: const Color(0xFF26272A),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                snack.message,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: snackTitleStyle(context),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${(fraction * 100).round()}%',
              style: AppTypography.meta.copyWith(
                fontSize: 12,
                letterSpacing: 0,
                color: p.textMuted,
              ),
            ),
            const SizedBox(width: 2),
            Semantics(
              button: true,
              label: 'Dismiss',
              child: GestureDetector(
                onTap: () {
                  snack.onCancel?.call();
                  onDismiss();
                },
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: AppIcon(_Glyph.close, size: 16, color: p.textMuted),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// 2D — assistant
// ===========================================================================

/// Only for things Hawk did on its own. The mark is the glyph.
class _Assistant extends StatelessWidget {
  const _Assistant(this.snack, this.onDismiss);

  final AssistantSnack snack;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final open = snack.onOpen;

    return GestureDetector(
      onTap: open == null ? null : _andDismiss(open, onDismiss),
      behavior: HitTestBehavior.opaque,
      child: SnackSurface(
        padding: EdgeInsets.only(left: 8, right: open == null ? 18 : 8),
        child: _Revealed(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const HawkMark.onInk(size: 32),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  snack.message,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: snackTitleStyle(context),
                ),
              ),
              if (open != null) ...[
                const SizedBox(width: 10),
                AppIcon(_Glyph.chevron, size: 15, color: p.textMuted),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// 2E — undo
// ===========================================================================

/// The one destructive path. The ring drains across the hold.
class _Undo extends StatefulWidget {
  const _Undo(this.snack, this.onDismiss);

  final UndoSnack snack;
  final VoidCallback onDismiss;

  @override
  State<_Undo> createState() => _UndoState();
}

class _UndoState extends State<_Undo> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.snack.hold,
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return SnackSurface(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: _Revealed(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final left = 1 - _controller.value;
                final seconds = math.max(
                  1,
                  (widget.snack.hold.inMilliseconds * left / 1000).ceil(),
                );
                return _Ring(
                  value: left,
                  color: p.danger,
                  track: const Color(0xFF3A2422),
                  child: Text(
                    '$seconds',
                    style: AppTypography.meta.copyWith(
                      fontSize: 11,
                      letterSpacing: 0,
                      fontWeight: FontWeight.w600,
                      fontVariations: const [FontVariation('wght', 600)],
                      color: p.textPrimary,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                widget.snack.message,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: snackTitleStyle(context),
              ),
            ),
            const SizedBox(width: 10),
            // White, not red: this is the action that *prevents* the
            // destruction, so it must not wear the colour of the thing it
            // is undoing.
            SnackFilledAction(
              label: 'Undo',
              onPressed: _andDismiss(widget.snack.onUndo, widget.onDismiss),
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// Pieces
// ===========================================================================

/// The 32px circle every snack leads with.
class _LeadCircle extends StatelessWidget {
  const _LeadCircle({required this.color, required this.child});

  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: 32,
    height: 32,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    alignment: Alignment.center,
    child: child,
  );
}

/// The busy mark: a quarter arc of accent turning on a grey ring, 16px,
/// 2.4 stroke — the design's CSS spinner rather than Material's, which grows
/// and shrinks its arc and reads as a different kind of wait.
class _Spinner extends StatefulWidget {
  const _Spinner({required this.color});

  final Color color;

  @override
  State<_Spinner> createState() => _SpinnerState();
}

class _SpinnerState extends State<_Spinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _turn = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  )..repeat();

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RotationTransition(
    turns: _turn,
    child: SizedBox.square(
      dimension: 16,
      child: CustomPaint(painter: _SpinnerPainter(color: widget.color)),
    ),
  );
}

class _SpinnerPainter extends CustomPainter {
  const _SpinnerPainter({required this.color});

  final Color color;

  static const _track = Color(0xFF45474A);
  static const _stroke = 2.4;

  @override
  void paint(Canvas canvas, Size size) {
    // A CSS border sits inside the box, so the stroke's centre line is half
    // a stroke in from the edge.
    final rect = (Offset.zero & size).deflate(_stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke;
    canvas
      ..drawArc(rect, 0, 2 * math.pi, false, paint..color = _track)
      // `border-top-color`: the top quarter, centred on twelve o'clock.
      ..drawArc(
        rect,
        -3 * math.pi / 4,
        math.pi / 2,
        false,
        paint..color = color,
      );
  }

  @override
  bool shouldRepaint(_SpinnerPainter old) => old.color != color;
}

/// A snack's single action. Filled for the primary path, accent text for
/// the soft one — never two.
class _ActionFor extends StatelessWidget {
  const _ActionFor({required this.action, required this.onDismiss});

  final SnackAction action;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final run = _andDismiss(action.onPressed, onDismiss);
    return switch (action.style) {
      SnackActionStyle.filled => SnackFilledAction(
        label: action.label,
        onPressed: run,
      ),
      SnackActionStyle.text => SnackTextAction(
        label: action.label,
        onPressed: run,
      ),
    };
  }
}

/// A 32px ring — progress filling, or an undo window draining.
///
/// The design's 36-unit drawing (radius 14, stroke 4, round cap from twelve
/// o'clock), scaled to 32.
class _Ring extends StatelessWidget {
  const _Ring({
    required this.value,
    required this.color,
    required this.track,
    this.child,
  });

  final double value;
  final Color color;
  final Color track;
  final Widget? child;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 32,
    child: CustomPaint(
      painter: _RingPainter(value: value, color: color, track: track),
      child: child == null ? null : Center(child: child),
    ),
  );
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.value,
    required this.color,
    required this.track,
  });

  final double value;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.width / 36;
    final stroke = 4 * unit;
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: 14 * unit,
    );

    canvas.drawArc(
      rect,
      0,
      2 * math.pi,
      false,
      Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    if (value > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * value.clamp(0.0, 1.0),
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.color != color || old.track != track;
}

/// The design's own glyphs, at its stroke weights — the snack circles are
/// 32px and a glyph drawn at the app's usual 1.9 would disappear inside one.
abstract final class _Glyph {
  static const check =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="2.8" '
      'stroke-linecap="round" stroke-linejoin="round">'
      '<path d="M5 12.5l4.5 4.5L19 7.5"/></svg>';

  static const exclaim =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="2.8" '
      'stroke-linecap="round"><path d="M12 6.5v7M12 17.4v.1"/></svg>';

  static const info =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="2.4" '
      'stroke-linecap="round"><path d="M12 10.5v6.5M12 7v.1"/></svg>';

  static const clock =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="2.3" '
      'stroke-linecap="round"><circle cx="12" cy="12" r="8"/>'
      '<path d="M12 7.5V12l3 2"/></svg>';

  static const file =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="2" '
      'stroke-linejoin="round"><path d="M6 3.5h8l4 4v13H6z"/>'
      '<path d="M14 3.5v4h4"/></svg>';

  static const close =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="2.4" '
      'stroke-linecap="round"><path d="M6 6l12 12M18 6L6 18"/></svg>';

  static const offline =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="2.2" '
      'stroke-linecap="round" stroke-linejoin="round">'
      '<path d="M3 3l18 18M8.5 16.5a5 5 0 0 1 7 0M5 12.5a10 10 0 0 1 4-2.4'
      'M19 12.5a10 10 0 0 0-3.2-2.1"/>'
      '<circle cx="12" cy="20" r=".7"/></svg>';

  static const chevron =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="2.4" '
      'stroke-linecap="round" stroke-linejoin="round">'
      '<path d="M9 5l7 7-7 7"/></svg>';
}
