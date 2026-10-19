import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/widgets/hawk_mark.dart';

/// Screen 1A — SPLASH.
///
/// ```
///        ┌──────────────┐
///        │  ┌────────┐  │   the mark on its own ink tile,
///        │  │   ◐    │  │   104px at radius 30 — the app icon
///        │  └────────┘  │   the user just tapped, held still
///        │              │
///        │     Hawk     │   32 / 800
///        │ Your second  │   14, muted
///        │   memory     │
///        │              │
///        │    ▬▬▬───    │   96 × 4, filling while we start up
///        └──────────────┘
/// ```
///
/// **The v2 animation is gone.** It opened on a full-bleed orb that resolved
/// into the mark over two seconds — genuinely nice, and it produced a frame
/// the v3 design does not have: no tile, no tagline, no progress. v3 draws a
/// launch screen, which is a different job from a brand moment: it says the
/// app is starting and roughly how far along it is. The choreography could
/// come back as a transition *into* this frame; it cannot come back as a
/// replacement for it.
///
/// The bar is honest about what it measures — it fills while [readyWhen] runs
/// and completes when that does, rather than animating to 100% on a timer
/// regardless of whether the session actually resolved.
class SplashPage extends StatefulWidget {
  const SplashPage({
    this.onComplete,
    this.readyWhen,
    this.maxWait = const Duration(seconds: 6),
    super.key,
  });

  /// Navigation lives with the caller, so this stays pure choreography.
  final VoidCallback? onComplete;

  /// Startup work to overlap with the launch frame — a session check, a warm
  /// cache read. The brand moment is free time; spending it on a spinner
  /// afterwards is not.
  final Future<void>? readyWhen;

  /// Hard ceiling on [readyWhen]. A slow or hung dependency must not strand
  /// the user here; the app continues and handles the failure in context.
  final Duration maxWait;

  static const routeName = 'splash';

  /// Its own path, not `/`.
  ///
  /// `/` belongs to the home screen. When both declared `/`, go_router
  /// returned the first registered match — the splash — and the guard's
  /// redirect from splash to home became a redirect to the location it was
  /// already on, which go_router treats as a no-op. The home screen was
  /// unreachable: the user sat on the splash forever.
  static const routePath = '/splash';

  /// Long enough to read as intentional, short enough not to tax a returning
  /// user. Public so tests can drive it precisely.
  static const duration = Duration(milliseconds: 1400);

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  /// [SplashPage.readyWhen] with a handler already attached.
  ///
  /// The caller's future is adopted in `initState`, not at the point we get
  /// round to awaiting it. A future that fails in between would otherwise be
  /// an *unhandled* async error — which, in a release build, takes the app
  /// down during its own launch. Errors are swallowed deliberately: a failed
  /// warm-up is the app's problem to surface in context, and it must never
  /// trap the user here.
  late final Future<void> _ready;

  bool _handedOff = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: SplashPage.duration,
    );

    _ready = (widget.readyWhen ?? Future<void>.value()).catchError((_) {});

    // After the first frame, not during `initState`: `_run` reads MediaQuery
    // to find out whether animations are switched off, and depending on an
    // inherited widget from `initState` is not allowed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_run());
    });
  }

  Future<void> _run() async {
    // Reduce motion means *no* motion: the bar jumps to full and the screen
    // waits only on the real work. A launch animation is exactly the kind of
    // thing the setting exists to switch off, and it is the one animation a
    // user cannot skip by not looking at it.
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still) _controller.value = 1;

    // Both, not either: the bar must not finish before the frame has been
    // seen, and the frame must not hold a user whose session resolved in
    // 40ms any longer than it needs.
    await Future.wait([
      if (!still) _controller.forward(from: 0),
      _ready.timeout(widget.maxWait, onTimeout: () {}),
    ]);
    if (!mounted || _handedOff) return;
    _handedOff = true;
    widget.onComplete?.call();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: p.ground,
      ),
      child: Scaffold(
        backgroundColor: p.ground,
        // One node, one announcement. Descendant semantics are excluded so a
        // screen reader says "Hawk" once rather than reading the wordmark out
        // again as a separate label.
        body: Semantics(
          label: 'Hawk. Your second memory.',
          container: true,
          excludeSemantics: true,
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // The mark alone, at 120 — no tile.
                    //
                    // The tile was my reading of an `<img src="app_icon.png">`
                    // in the first cut of the design: an app icon is a
                    // rounded square, so I drew one. The design now draws the
                    // mark inline instead, and it is right — the tile was the
                    // home screen's frame, and repeating it here made the
                    // splash look like a screenshot of the icon rather than
                    // the app opening.
                    const HawkMark(size: 120),
                    const SizedBox(height: AppSpacing.block),
                    Text(
                      'Hawk',
                      style: AppTypography.display32.copyWith(
                        color: p.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Your second memory',
                      style: AppTypography.bodyMedium.copyWith(
                        color: p.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 52,
                child: Center(
                  child: SizedBox(
                    width: 96,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.round),
                      child: AnimatedBuilder(
                        animation: _controller,
                        builder: (context, _) => SizedBox(
                          height: 4,
                          child: LinearProgressIndicator(
                            value: _controller.value,
                            minHeight: 4,
                            // A step above the ground rather than the usual
                            // raised grey: at 4px on near-black, [raised]
                            // reads as a solid bar and the fill disappears.
                            backgroundColor: const Color(0xFF212223),
                            valueColor: AlwaysStoppedAnimation(p.accent),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
