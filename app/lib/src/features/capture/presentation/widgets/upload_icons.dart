/// Glyphs the Upload flow adds, lifted verbatim from `Hawk Library.dc.html`.
///
/// Same contract as `HawkIcons` — the design's own path data, `{c}` for the
/// colour, `{w}` where one glyph is drawn at two weights. Kept beside the
/// flow rather than in the shared set while nothing else draws them; they
/// move across the day a second screen needs one.
library;

abstract final class UploadIcons {
  /// The Upload button's arrow into a tray.
  static const upload =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="2.3" '
      'stroke-linecap="round" stroke-linejoin="round">'
      '<path d="M12 15V4.5M7.5 9 12 4.5 16.5 9"/>'
      '<path d="M4.5 14.5v4a1.5 1.5 0 0 0 1.5 1.5h12a1.5 1.5 0 0 0 1.5-1.5v-4"/>'
      '</svg>';

  /// Storage full — the locked Upload button and E10's sheet.
  static const lock =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="{w}" '
      'stroke-linecap="round" stroke-linejoin="round">'
      '<rect x="5" y="11" width="14" height="9" rx="2.5"/>'
      '<path d="M8 11V8a4 4 0 0 1 8 0v3"/></svg>';

  /// No connection — a queued row, the waiting step, the offline island.
  static const offline =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="{w}" '
      'stroke-linecap="round" stroke-linejoin="round">'
      '<path d="M3 3l18 18M8.5 16.5a5 5 0 0 1 7 0M5 12.5a10 10 0 0 1 4-2.4'
      'M19 12.5a10 10 0 0 0-3.2-2.1"/>'
      '<circle cx="12" cy="20" r=".7"/></svg>';

  /// The "!" inside a red dot — a failed step.
  static const bang =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="{w}" '
      'stroke-linecap="round"><path d="M12 6.5v7M12 17.4v.1"/></svg>';

  /// "!" in a ring — too large (E2), and the link sheet's inline error (E8).
  static const alert =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="2.2" '
      'stroke-linecap="round" stroke-linejoin="round">'
      '<circle cx="12" cy="12" r="9"/><path d="M12 7.5v6M12 16.6v.3"/></svg>';

  /// Two sheets, one behind the other — already in your Library (E4).
  static const copy =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="2.2" '
      'stroke-linecap="round" stroke-linejoin="round">'
      '<rect x="8" y="8" width="12" height="12" rx="2.5"/>'
      '<path d="M16 8V5.5A1.5 1.5 0 0 0 14.5 4h-9A1.5 1.5 0 0 0 4 5.5v9'
      'A1.5 1.5 0 0 0 5.5 16H8"/></svg>';
}
