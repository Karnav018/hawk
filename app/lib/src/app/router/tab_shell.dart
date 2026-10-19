import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/hawk_nav.dart';
import '../../features/connectors/presentation/sync_news.dart';
import '../theme/app_palette.dart';
import '../theme/app_spacing.dart';

/// The frame the three tabs live in.
///
/// Holds the nav pill and nothing else: each tab's screen draws its own
/// content edge to edge, exactly as the design does, and the nav floats over
/// the bottom of it.
///
/// **The nav is here rather than on each screen** because v2 put a dock on
/// each screen and they drifted — the same microphone button started dictation
/// on one screen and navigated on another, and two of the four screens that
/// should have had a dock did not. One description of the nav, in one place,
/// cannot disagree with itself.
///
/// A [StatefulNavigationShell] rather than an index in a cubit: go_router owns
/// which branch is active and each branch keeps its own stack, so the back
/// button inside Library pops within Library instead of falling out of the
/// tab.
class TabShell extends StatelessWidget {
  const TabShell({required this.shell, super.key});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return Scaffold(
      backgroundColor: p.ground,
      // The body still runs the full height, so each screen's layout maths
      // is unchanged — but the band below paints over the bottom of it, so
      // nothing is ever *seen* passing behind the pill. See [navBand].
      extendBody: true,
      // Listening for what the Drive sync added on its own, for as long as
      // somebody is signed in — which is exactly as long as this shell exists.
      body: SyncNewsScope(child: shell),
      // **No SafeArea.** The design's 28px bottom inset is measured inside a
      // 402x874 frame that already contains the home indicator, so 28 is the
      // whole distance from the screen edge — not 28 on top of whatever the
      // device reserves. Wrapping this in a `SafeArea` added the inset twice:
      // the pill floated ~34px above where it was drawn, and [navClearance]
      // under-reserved by the same amount, so a docked footer collided with
      // the nav on exactly the devices that have an indicator.
      //
      // **An opaque band, not a floating pill.** The pill used to float over
      // the body, so on the tabs that scroll — Library, Profile — rows slid
      // underneath it: the same card grey as the pill, visible in the gaps
      // either side and below. Home, with nothing behind it, showed a clean
      // pill on the ground. One nav looked like two depending on the screen.
      // The design draws it one way everywhere — the pill on plain ground,
      // the list cut off above it — so the band is ground, full width, and
      // the pill sits in it at the design's inset.
      bottomNavigationBar: ColoredBox(
        color: p.ground,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenSide,
            AppSpacing.group,
            AppSpacing.screenSide,
            AppSpacing.screenBottom,
          ),
          child: HawkNav(
            current: HawkTab.values[shell.currentIndex],
            // `goBranch` rather than `context.go`: it switches branch while
            // preserving that branch's stack, which is the entire reason the
            // shell is stateful. `initialLocation: true` when re-tapping the
            // current tab would pop it to its root — deliberately not wired,
            // because [HawkNav] makes the current tab a no-op instead.
            onSelect: (tab) => shell.goBranch(tab.index),
          ),
        ),
      ),
    );
  }
}

/// The height of the ground band the shell paints at the bottom of every
/// tab: the design's 14px gap, the pill, and its 28px inset.
const double navBand = AppSpacing.group + AppSize.nav + AppSpacing.screenBottom;

/// How much room a tab screen must leave at the bottom for the nav.
///
/// The shell sets `extendBody: true`, so the body runs the full height and
/// the band is painted over its last [navBand] pixels. A scrolling body ends
/// in this much padding so its last row can scroll clear of the band rather
/// than stay under it.
const double navClearance = navBand;

/// Clearance for a tab screen whose last element is a docked control — the
/// chat face's ask bar, the voice face's chips.
///
/// The same as [navClearance] now that the band carries the gap itself: a
/// control ending at the band's top edge sits the design's 14px above the
/// pill, which is what this used to add by hand. Kept as its own name
/// because the two say different things about the screen using them.
const double dockedClearance = navBand;
