/// Icons lifted verbatim from `Hawk App v3.dc.html`.
///
/// Same contract as [AppIcons]: the design's own path data, with `{c}`
/// substituted for the stroke colour so one definition serves every colour it
/// appears in. Redrawing these by hand is how an icon set drifts from the
/// design one weight at a time.
///
/// v3 draws at **three stroke weights** and they carry meaning:
///
/// * **1.7–1.9** — content. A file type, a provider, a thing being described.
/// * **2.1–2.3** — chrome. Navigation, headers, anything you tap.
/// * **3.0** — a tick inside a filled dot, where the shape is tiny and the
///   surface behind it is solid accent.
///
/// Using the wrong weight is the most visible way a ported screen looks
/// almost right, so the weight lives in the path data rather than being a
/// parameter somebody has to remember.
library;

abstract final class HawkIcons {
  // ------------------------------------------------------------- chrome ---

  /// Back. Header buttons everywhere.
  static const chevronLeft =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="2.3" '
      'stroke-linecap="round" stroke-linejoin="round">'
      '<path d="M14 5l-7 7 7 7"/></svg>';

  /// Forward — a row that leads somewhere.
  static const chevronRight =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="2.2" '
      'stroke-linecap="round" stroke-linejoin="round">'
      '<path d="M10 5l7 7-7 7"/></svg>';

  /// Drag the stack open.
  static const chevronDown =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="2.4" '
      'stroke-linecap="round" stroke-linejoin="round">'
      '<path d="M12 8.5v10M8 14.5l4 4 4-4"/></svg>';

  /// Dismiss — closes listening, not a screen.
  static const close =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="2.3" '
      'stroke-linecap="round"><path d="M6 6l12 12M18 6L6 18"/></svg>';

  static const search =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="2.2" '
      'stroke-linecap="round" stroke-linejoin="round">'
      '<circle cx="11" cy="11" r="6.5"/><path d="M16 16l4.5 4.5"/></svg>';

  static const plus =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="2.2" '
      'stroke-linecap="round"><path d="M12 5.5v13M5.5 12h13"/></svg>';

  /// The arrow that rides inside a primary button.
  static const arrowRight =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="2.4" '
      'stroke-linecap="round" stroke-linejoin="round">'
      '<path d="M5 12h13M13 7l5 5-5 5"/></svg>';

  /// Leaves the app — opening a file in its own viewer.
  static const arrowUpRight =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="2.4" '
      'stroke-linecap="round" stroke-linejoin="round">'
      '<path d="M7 17L17 7M9 7h8v8"/></svg>';

  /// Inside a filled accent dot, so it is drawn heavy.
  static const check =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="3" '
      'stroke-linecap="round" stroke-linejoin="round">'
      '<path d="M5 12.5l4.5 4.5L19 7.5"/></svg>';

  // ----------------------------------------------------------------- nav ---

  static const navHome =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="2.1" '
      'stroke-linecap="round" stroke-linejoin="round">'
      '<path d="M4 11l8-6.5 8 6.5v8.5H4z"/></svg>';

  static const navLibrary =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="2.1" '
      'stroke-linecap="round"><path d="M4 7h11M4 12h16M4 17h8"/></svg>';

  static const navYou =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="2.1" '
      'stroke-linecap="round" stroke-linejoin="round">'
      '<circle cx="12" cy="8.5" r="3.6"/>'
      '<path d="M5 19.5c1.4-3 4-4.5 7-4.5s5.6 1.5 7 4.5"/></svg>';

  // ------------------------------------------------------------- sources ---

  /// Drive's own trefoil, as the design draws it — outline, not the brand
  /// colours. On 1G and 1R it is a source in a list, not a logo lockup.
  static const googleDrive =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="1.7" '
      'stroke-linejoin="round">'
      '<path d="M9 3.5h6l6 10.5h-6zM9 3.5 3 14l3 5 6-10.5zM6 19h12l3-5H9z"/></svg>';

  /// The phone vault: this device, as a source.
  static const phoneVault =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="1.7" '
      'stroke-linecap="round" stroke-linejoin="round">'
      '<rect x="6" y="2.5" width="12" height="19" rx="3.5"/>'
      '<path d="M10 18.5h4"/></svg>';

  /// Google's mark, in its own colours. The one icon that keeps brand colour,
  /// because a monochrome Google button is not a Google button.
  static const google =
      '<svg viewBox="0 0 24 24">'
      '<path fill="#0c0c0d" d="M21.6 12.2c0-.7-.1-1.2-.2-1.8H12v3.4h5.4c-.1.9-.7 2.2-1.9 3.1l2.8 2.2c1.7-1.6 2.7-3.9 2.7-6.9z"/>'
      '<path fill="#22333b" d="M12 21.5c2.5 0 4.5-.8 6-2.2l-2.8-2.2c-.8.5-1.9.9-3.2.9-2.5 0-4.6-1.6-5.3-3.9l-2.9 2.2C5.1 19.4 8.3 21.5 12 21.5z"/>'
      '<path fill="#3d5560" d="M6.7 14.1c-.2-.6-.3-1.2-.3-1.9s.1-1.3.3-1.9L3.7 8.1C3 9.4 2.6 10.9 2.6 12.2s.4 2.8 1.1 4.1l3-2.2z"/>'
      '<path fill="#5b7885" d="M12 6.4c1.8 0 3 .8 3.7 1.4l2.6-2.5C16.5 3.8 14.5 3 12 3 8.3 3 5.1 5.1 3.7 8.1l3 2.2c.7-2.2 2.8-3.9 5.3-3.9z"/></svg>';

  static const mail =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="1.8" '
      'stroke-linecap="round" stroke-linejoin="round">'
      '<rect x="3" y="5.5" width="18" height="13" rx="3"/>'
      '<path d="M3.5 7l8.5 6 8.5-6"/></svg>';

  // --------------------------------------------------------- file kinds ---

  /// A document — the folded corner is the whole idea.
  static const file =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="{w}" '
      'stroke-linecap="round" stroke-linejoin="round">'
      '<path d="M14 3H7a1 1 0 0 0-1 1v16a1 1 0 0 0 1 1h10a1 1 0 0 0 1-1V7z"/>'
      '<path d="M14 3v4h4"/></svg>';

  /// The home header's capture button: a body, a lens, the shutter bump.
  static const camera =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="{w}" '
      'stroke-linecap="round" stroke-linejoin="round">'
      '<path d="M3.5 9A2.5 2.5 0 0 1 6 6.5h1.9l1.5-2.2h5.2l1.5 2.2H18A2.5 2.5 '
      '0 0 1 20.5 9v8.2a2.5 2.5 0 0 1-2.5 2.5H6a2.5 2.5 0 0 1-2.5-2.5z"/>'
      '<circle cx="12" cy="13" r="3.6"/></svg>';

  static const image =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="{w}" '
      'stroke-linecap="round" stroke-linejoin="round">'
      '<rect x="3.5" y="5" width="17" height="14" rx="3"/>'
      '<circle cx="9" cy="10" r="1.7"/>'
      '<path d="M4 16.5 8.5 13l3.5 2.5L15.5 12l5 4.5"/></svg>';

  static const link =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="{w}" '
      'stroke-linecap="round" stroke-linejoin="round">'
      '<path d="M10 13.5a3.5 3.5 0 0 0 5 0l3-3a3.5 3.5 0 0 0-5-5l-1 1"/>'
      '<path d="M14 10.5a3.5 3.5 0 0 0-5 0l-3 3a3.5 3.5 0 0 0 5 5l1-1"/></svg>';

  static const scan =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="{w}" '
      'stroke-linecap="round" stroke-linejoin="round">'
      '<path d="M3.5 8h3L8 5.5h8L17.5 8h3v11h-17z"/>'
      '<circle cx="12" cy="13.5" r="3.4"/></svg>';

  /// Audio, as a level meter rather than a speaker — it is a recording, not
  /// playback.
  static const audio =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="{w}" '
      'stroke-linecap="round">'
      '<path d="M4 12v3M8 8.5v10M12 5.5v14M16 9v8M20 12v3"/></svg>';

  /// The product indexes video; no v3 screen happens to draw a video row, so
  /// the design never had to name this one. Drawn in the same stroke
  /// language as its siblings rather than borrowed from Material, which
  /// would be the one icon in the set that came from somewhere else.
  static const video =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="{w}" '
      'stroke-linecap="round" stroke-linejoin="round">'
      '<rect x="3" y="6" width="12" height="12" rx="3"/>'
      '<path d="M15 10.5 20.5 7v10L15 13.5z"/></svg>';

  static const mic =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="{w}" '
      'stroke-linecap="round" stroke-linejoin="round">'
      '<rect x="9" y="3" width="6" height="11" rx="3"/>'
      '<path d="M5.5 11.5a6.5 6.5 0 0 0 13 0M12 18v3"/></svg>';

  /// Typing — a thread, not a keyboard.
  static const type =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="2" '
      'stroke-linecap="round" stroke-linejoin="round">'
      '<rect x="4" y="4" width="16" height="16" rx="5"/>'
      '<path d="M9 9.5h6M12 9.5V16"/></svg>';

  // -------------------------------------------------------------- states ---

  static const shieldCheck =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="1.9" '
      'stroke-linecap="round" stroke-linejoin="round">'
      '<path d="M12 3.5l7 3v5.5c0 4-3 7-7 8.5-4-1.5-7-4.5-7-8.5V6.5z"/>'
      '<path d="M9 12l2 2 4-4"/></svg>';

  static const shield =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="1.9" '
      'stroke-linecap="round" stroke-linejoin="round">'
      '<path d="M12 3.5l7 3v5.5c0 4-3 7-7 8.5-4-1.5-7-4.5-7-8.5V6.5z"/></svg>';

  static const eye =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="1.9" '
      'stroke-linecap="round" stroke-linejoin="round">'
      '<path d="M2.5 12s3.5-6 9.5-6 9.5 6 9.5 6-3.5 6-9.5 6-9.5-6-9.5-6z"/>'
      '<circle cx="12" cy="12" r="2.6"/></svg>';

  /// Destructive. The only icon that is ever drawn in [AppPalette.danger].
  static const trash =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="{w}" '
      'stroke-linecap="round" stroke-linejoin="round">'
      '<path d="M5.5 7h13l-1 12.5h-11z"/><path d="M9 7V4.5h6V7"/></svg>';

  static const info =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="1.9" '
      'stroke-linecap="round"><circle cx="12" cy="12" r="8.5"/>'
      '<path d="M12 11v5.5M12 7.8v.6"/></svg>';

  /// Save a copy out of the app.
  static const download =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="2" '
      'stroke-linecap="round" stroke-linejoin="round">'
      '<path d="M4 12v6.5h16V12"/><path d="M12 3.5v11m0 0 4-4m-4 4-4-4"/></svg>';

  /// Share out.
  static const share =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="2" '
      'stroke-linecap="round" stroke-linejoin="round">'
      '<path d="M12 16V4m0 0-4 4m4-4 4 4"/>'
      '<path d="M5 14v4.5A1.5 1.5 0 0 0 6.5 20h11a1.5 1.5 0 0 0 1.5-1.5V14"/></svg>';

  static const vault =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="1.9" '
      'stroke-linecap="round" stroke-linejoin="round">'
      '<path d="M4 7.5 12 3.5l8 4v9L12 20.5l-8-4z"/>'
      '<path d="M12 12v8.5M4 7.5l8 4.5 8-4.5"/></svg>';
}
