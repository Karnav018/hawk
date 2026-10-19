/// The v3 spacing scale.
///
/// Not a 4px grid — the design isn't one. It works in a small set of
/// deliberate gaps (9 between siblings in a list, 14 between groups, 18–26
/// between blocks) and naming them is what stops those becoming "16, or maybe
/// 18, whatever looked right on the screen I was on".
abstract final class AppSpacing {
  static const xxs = 2.0;
  static const xs = 4.0;
  static const sm = 8.0;

  /// The gap between siblings in a list or a grid. The most common value in
  /// the whole design.
  static const gap = 9.0;

  static const md = 12.0;

  /// Between a group and the next thing down.
  static const group = 14.0;

  /// Inside a row or a compact card.
  static const inset = 16.0;

  static const lg = 18.0;

  /// Inside a full card — the 28px-radius ones are padded 20–22.
  static const card = 20.0;
  static const cardWide = 22.0;

  /// Between blocks on a screen.
  static const block = 24.0;
  static const blockWide = 26.0;

  static const xl = 30.0;
  static const xxl = 34.0;

  /// Screen chrome, straight from the design: `padding: 56px 16px 28px`.
  static const screenTop = 56.0;
  static const screenSide = 16.0;
  static const screenBottom = 28.0;

  // ----------------------------------------------------- v2 compatibility ---
  // Deleted as each lane lands; see app_palette.dart for why these exist.

  @Deprecated('Use AppSpacing.inset.')
  static const panel = inset;

  @Deprecated('Use a concrete row height; v3 rows are sized by their content.')
  static const row = 64.0;
}

/// Corner radii.
///
/// v3 is built almost entirely from two shapes: the **pill** ([round]) for
/// anything you touch, and the **28px card** for anything you read. Everything
/// else is a variation for a smaller surface.
abstract final class AppRadius {
  /// A progress bar's own ends.
  static const bar = 4.0;

  /// The tail corner of a chat bubble — the one corner that isn't round.
  static const tail = 8.0;

  /// A small icon tile inside a row.
  static const tileSmall = 12.0;

  /// The standard icon tile beside a file name.
  static const tile = 14.0;

  /// A larger icon tile, on a card rather than a row.
  static const tileLarge = 16.0;

  /// An OTP box.
  static const code = 20.0;

  /// A row, an inline chip, a quick-add tile. The workhorse.
  static const row = 22.0;

  /// A chat bubble.
  static const bubble = 24.0;

  /// A card — the thing you read. The signature radius of v3.
  static const card = 28.0;

  /// The top corners of a modal sheet.
  static const sheet = 30.0;

  /// Anything you touch: buttons, inputs, nav, avatars, chips.
  static const round = 999.0;

  // ----------------------------------------------------- v2 compatibility ---
  // Deleted as each lane lands; see app_palette.dart for why these exist.

  @Deprecated('Use AppRadius.row, or AppRadius.round for anything touchable.')
  static const panel = row;

  @Deprecated('Use AppRadius.round.')
  static const pill = round;

  @Deprecated('Use AppRadius.tileSmall.')
  static const chip = tileSmall;

  @Deprecated('Use AppRadius.round — v3 header buttons are circles.')
  static const iconButton = tile;
}

/// Fixed control heights, so a button is never 57 on one screen and 58 on the
/// next.
abstract final class AppSize {
  /// The bar at the bottom of a chat bubble stack, and a small inline chip.
  static const chipSmall = 30.0;
  static const chip = 32.0;

  /// A status pill in a header ("LISTENING", "3 FILES").
  static const statusPill = 34.0;

  /// An inline action chip inside a row ("Open").
  static const chipAction = 38.0;

  /// The upgrade button on the plan card.
  static const chipLarge = 40.0;

  /// A circular header button, and the small avatar.
  static const headerButton = 44.0;

  /// A button inside the nav bar.
  static const navItem = 46.0;

  /// A tertiary / paired action.
  static const buttonSmall = 54.0;

  /// A secondary action, and the sheet's own buttons.
  static const buttonMedium = 56.0;

  /// The primary action. Every "Continue" in the product.
  static const button = 58.0;

  /// A text input.
  static const input = 60.0;

  /// The bottom navigation bar.
  static const nav = 62.0;

  /// A settings row inside a [RowGroup]. Taller than a file row because its
  /// glyph is a bare stroke rather than a tiled icon.
  static const settingRow = 62.0;

  /// An OTP box.
  static const codeBox = 64.0;

  /// The segmented control, and the height of its selected inner pill.
  static const tabs = 52.0;
  static const tabsInner = 42.0;

  /// The large avatar on the profile screen.
  static const avatarLarge = 54.0;

  /// Icon tiles, smallest to largest.
  static const tileSmall = 38.0;
  static const tile = 42.0;
  static const tileLarge = 46.0;
  static const tileHero = 50.0;

  // ----------------------------------------------------- v2 compatibility ---
  // Deleted as each lane lands; see app_palette.dart for why these exist.

  @Deprecated('Use AppSize.button.')
  static const primaryButton = button;

  @Deprecated('Use AppSize.button.')
  static const authButton = buttonMedium;
}
