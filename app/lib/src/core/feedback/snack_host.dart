import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../di/injector.dart';
import 'snack.dart';
import 'snack_controller.dart';
import 'snack_timing.dart';
import 'widgets/snack_views.dart';

/// Puts the current snack on screen, above every route — **at the top**.
///
/// `Hawk Snackbars.dc.html` section 2, "Top island": snacks drop from under
/// the Dynamic Island, 8px below the safe area and 20px in from each side.
/// They used to sit above the bottom dock, where they covered the ask field
/// and the nav on exactly the screens people type on; at the top they
/// "never cover input".
///
/// * **iPhone with a Dynamic Island** — the snack grows out of the island.
///   Its black shape starts at the island's size and position and stretches
///   down to the snack's own, black over black, so it reads as the island
///   itself opening; the words arrive once the shape has formed. On the way
///   out it shrinks back into the island.
/// * **Everything else** (Android, notched iPhones) — it drops 14px from the
///   top edge and fades in, and rises back out.
///
/// Wrapped around the router's output rather than living per-screen: a snack
/// confirming a save must survive the navigation that follows it, and a
/// per-screen host would be torn down mid-animation.
class SnackHost extends StatefulWidget {
  const SnackHost({
    required this.child,
    this.controller,
    this.island,
    super.key,
  });

  final Widget child;

  /// Injected in tests; resolved from the locator otherwise.
  final SnackController? controller;

  /// Forces the island morph on or off, for tests. Detected otherwise.
  @visibleForTesting
  final bool? island;

  /// Whether this device has a Dynamic Island to grow out of.
  ///
  /// There is no API for it. An island iPhone reports a status-bar inset of
  /// 59 or more; notched iPhones report 44–50, and Android is never one.
  static bool hasIsland(MediaQueryData media) =>
      defaultTargetPlatform == TargetPlatform.iOS &&
      media.padding.top >= SnackIsland.minInset;

  @override
  State<SnackHost> createState() => _SnackHostState();
}

class _SnackHostState extends State<SnackHost> {
  late final SnackController _controller =
      widget.controller ?? getIt<SnackController>();

  /// A rebuild is already waiting for the end of this frame.
  bool _rebuildPending = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_changed);
  }

  @override
  void dispose() {
    _controller.removeListener(_changed);
    super.dispose();
  }

  /// Listened to by hand rather than through a `ListenableBuilder`, because
  /// snacks are shown from anywhere — including a screen's `initState` (the
  /// Indexing screen attaching to the upload centre) and its `dispose`
  /// (leaving it hands the upload to the island). Both run inside a frame,
  /// while the tree is locked, where `setState` is an assertion: "setState()
  /// or markNeedsBuild() called when widget tree was locked". A change that
  /// arrives mid-frame is shown when the frame ends instead.
  void _changed() {
    final phase = SchedulerBinding.instance.schedulerPhase;
    final midFrame =
        phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks;
    if (!midFrame) {
      setState(() {});
      return;
    }
    if (_rebuildPending) return;
    _rebuildPending = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _rebuildPending = false;
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final island = widget.island ?? SnackHost.hasIsland(media);
    final top = media.padding.top + SnackTiming.topGap;
    final snack = _controller.current;

    return Stack(
      children: [
        // The same widget handed back, so a snack coming or going never
        // rebuilds the screens underneath.
        widget.child,
        Positioned(
          top: top,
          left: SnackTiming.sideInset,
          right: SnackTiming.sideInset,
          // A transparent Material, because this layer sits *above* the
          // navigator — outside every route's Scaffold — and text there has
          // no default style to inherit: Flutter draws it with its debug
          // double yellow underline, which is what snacks looked like. It
          // also gives the Undo pill's ink somewhere to splash.
          child: Material(
            type: MaterialType.transparency,
            child: AnimatedSwitcher(
              duration: SnackTiming.enter,
              reverseDuration: SnackTiming.exit,
              switchInCurve: SnackTiming.enterCurve,
              switchOutCurve: SnackTiming.exitCurve,
              // Stacked from the top, so a taller detail card never pushes
              // the capsule it replaces downwards mid-swap.
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.topCenter,
                children: [...previous, ?current],
              ),
              transitionBuilder: (child, animation) => island
                  ? _IslandMorph(
                      animation: animation,
                      // From the snack's resting top back up to the
                      // island's — negative, it starts above.
                      rise: SnackIsland.top - top,
                      child: child,
                    )
                  : _Drop(animation: animation, child: child),
              child: snack == null
                  ? const SizedBox.shrink()
                  : Align(
                      // A progress bar keeps one key across its updates,
                      // so a new fraction repaints the ring in place
                      // instead of re-running the island's entrance
                      // for every percent.
                      key: snack is ProgressSnack
                          ? const ValueKey('progress')
                          : ValueKey(identityHashCode(snack)),
                      alignment: Alignment.topCenter,
                      child: _Dismissible(
                        snack: snack,
                        onDismiss: _controller.dismiss,
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Grows out of the Dynamic Island, and shrinks back into it.
///
/// The shape does the travelling: it starts at the island's width, height
/// and position — directly over the hardware, so the join is invisible —
/// and stretches to the snack's own. The content is revealed only in the
/// last part of the motion (see [SnackReveal]).
class _IslandMorph extends StatelessWidget {
  const _IslandMorph({
    required this.animation,
    required this.rise,
    required this.child,
  });

  final Animation<double> animation;
  final double rise;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reveal = CurvedAnimation(
      parent: animation,
      curve: const Interval(SnackIsland.revealFrom, 1),
    );

    return AnimatedBuilder(
      animation: animation,
      child: SnackReveal(reveal: reveal, child: child),
      builder: (context, child) => LayoutBuilder(
        builder: (context, box) {
          final t = animation.value;
          // Scaled from the island's size to the snack's. The snack's own
          // width is at most the space between the insets; a capsule that
          // hugs short text is narrower, so this starts a little wider than
          // the island for it — still over the black hardware at t = 0,
          // because the hardware is where it begins.
          final sx = lerpDouble(SnackIsland.width / box.maxWidth, 1, t)!;
          final sy = lerpDouble(SnackIsland.height / 48, 1, t)!;
          return Transform.translate(
            offset: Offset(0, lerpDouble(rise, 0, t)!),
            child: Transform(
              alignment: Alignment.topCenter,
              transform: Matrix4.diagonal3Values(sx, sy, 1),
              child: child,
            ),
          );
        },
      ),
    );
  }
}

/// Drops 14px from the top edge and fades in; rises back out.
class _Drop extends StatelessWidget {
  const _Drop({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: animation,
    child: AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) => Transform.translate(
        offset: Offset(
          0,
          lerpDouble(-SnackTiming.dropDistance, 0, animation.value)!,
        ),
        child: child,
      ),
    ),
  );
}

/// Swipe up to dismiss — the design's only dismissal for timed snacks.
class _Dismissible extends StatelessWidget {
  const _Dismissible({required this.snack, required this.onDismiss});

  final Snack snack;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final view = SnackView(snack: snack, onDismiss: onDismiss);

    // A progress snack is status, not news: swiping it away would hide work
    // that is still happening. It carries an × instead.
    if (snack.isPersistent) return view;

    return Dismissible(
      key: ValueKey('snack-${identityHashCode(snack)}'),
      direction: DismissDirection.up,
      dismissThresholds: const {
        DismissDirection.up: SnackTiming.dismissThreshold,
      },
      onDismissed: (_) => onDismiss(),
      child: view,
    );
  }
}
