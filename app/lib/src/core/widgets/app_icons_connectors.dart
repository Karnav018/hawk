/// Provider marks and the connector-flow glyphs, traced from the design.
///
/// Kept out of [AppIcons] because these are brand marks with different rules:
/// they are recognisable shapes rather than a consistent 1.5px stroke set, and
/// mixing them into the general icon scale invites someone to restyle a logo
/// to match the UI.
abstract final class ConnectorIcons {
  static const googleDrive =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="1.5" '
      'stroke-linejoin="round"><path d="M9 3.5h6l6 10.5h-6zM9 3.5 3 14l3 5 6-10.5zM6 19h12l3-5H9z"/></svg>';

  static const device =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="1.5">'
      '<rect x="3.5" y="5" width="17" height="14" rx="2.5"/><path d="M3.5 10h17"/></svg>';

  /// 3G — "Read and index".
  static const eye =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="1.7">'
      '<path d="M2.5 12s3.5-6 9.5-6 9.5 6 9.5 6-3.5 6-9.5 6-9.5-6-9.5-6z"/>'
      '<circle cx="12" cy="12" r="2.6"/></svg>';

  /// 3G — "Manage storage".
  static const trash =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="1.7">'
      '<path d="M5.5 7h13l-1 12.5h-11z"/><path d="M9 7V4.5h6V7M10 11v5M14 11v5"/></svg>';

  /// 3L — a kind that is still working.
  static const clock =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="1.8">'
      '<circle cx="12" cy="12" r="8"/><path d="M12 7.5V12l3 2"/></svg>';

  /// 3M — a suggested question. A speech bubble, not a magnifying glass:
  /// asking is the gesture the screen is teaching, searching is not.
  static const ask =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="1.7" '
      'stroke-linejoin="round"><path d="M4 12a8 8 0 1 1 3 6.2L4 19z"/></svg>';

  static const folder =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="1.6" '
      'stroke-linejoin="round"><path d="M3.5 7a2 2 0 0 1 2-2h3.2l2 2.4H18.5a2 2 0 0 1 2 2v8.6a2 2 0 0 1-2 2h-13a2 2 0 0 1-2-2z"/></svg>';
}
