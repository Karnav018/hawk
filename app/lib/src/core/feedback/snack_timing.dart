import 'package:flutter/animation.dart';

/// Motion and placement from `Hawk Snackbars.dc.html` section 2:
///
/// > ENTER 500MS · DROPS 14PX FROM THE NOTCH · EXIT 250MS · RISES BACK IN ·
/// > HOLD 4S · UNDO 5S · PROGRESS ∞ · DISMISS · SWIPE UP ·
/// > TOP = SAFE AREA + 8PX · 20PX SIDE INSET
///
/// Gathered here rather than scattered through the widgets so the whole
/// system's rhythm can be read — and changed — in one place.
abstract final class SnackTiming {
  /// In over 500ms, dropping 14px.
  static const enter = Duration(milliseconds: 500);
  static const enterCurve = Curves.easeOutCubic;
  static const dropDistance = 14.0;

  /// Out over 250ms, rising back where it came from.
  static const exit = Duration(milliseconds: 250);
  static const exitCurve = Curves.easeInCubic;

  /// Below the status bar — or the Dynamic Island — by 8px, 20px in from
  /// each side. At the top, a snack can never cover the field somebody is
  /// typing into or the button they are about to press.
  static const topGap = 8.0;
  static const sideInset = 20.0;

  /// Past this fraction of its height, an upward swipe dismisses.
  static const dismissThreshold = 0.35;
}

/// The Dynamic Island, as the snack grows out of it.
///
/// Apple publishes no API for the island's frame, so these are its measured
/// geometry on the 14 Pro through 17 Pro: 126 by 37 points, 11 from the top.
/// The morph only needs to *start* over the hardware — black on black — for
/// the snack to read as the island stretching down, so a point either way is
/// invisible.
abstract final class SnackIsland {
  static const width = 126.0;
  static const height = 37.0;
  static const top = 11.0;

  /// The status-bar inset that means a Dynamic Island rather than a notch.
  /// Notched iPhones report 44–50; island iPhones report 59 and up.
  static const minInset = 54.0;

  /// When the text starts to appear — once the shape has mostly grown, so
  /// words are never seen squashed inside a half-formed capsule.
  static const revealFrom = 0.45;
}
