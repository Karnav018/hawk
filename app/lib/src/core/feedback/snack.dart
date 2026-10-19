import 'package:flutter/foundation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'snack.freezed.dart';

/// One action, never two.
///
/// The design is explicit about this, so it is a single nullable field rather
/// than a list — there is no way to express two actions, which means nobody
/// can add one later without changing the type.
@freezed
abstract class SnackAction with _$SnackAction {
  const factory SnackAction({
    required String label,
    required VoidCallback onPressed,

    /// Filled white pill for the primary path; accent text for the soft one.
    @Default(SnackActionStyle.filled) SnackActionStyle style,
  }) = _SnackAction;
}

enum SnackActionStyle { filled, text }

/// Hold 4s — the design's default. Top-level rather than a static on [Snack]
/// because `@Default` is emitted verbatim into the generated part, where a
/// class member would not be in scope.
const _defaultHold = Duration(seconds: 4);

/// Undo holds a second longer, and the ring drains across it.
const _undoHold = Duration(seconds: 5);

/// What sits in a detail snack's 32px circle — from `Hawk Snackbars.dc.html`,
/// "Every snack in the app".
///
/// The circle is how a detail says what kind of news it is before a word is
/// read, so the colour is a rule, not a choice: **red only on failures**.
/// Everything else is the raised grey, with the glyph saying which thing it
/// is.
enum SnackMark {
  /// Neutral information — "Nothing here can open it". Grey, white "i".
  info,

  /// Something the user asked for did not happen. Red, ink "!".
  failure,

  /// A deadline — "goes dormant in 14 days". Grey, accent clock.
  clock,

  /// About one file by name — "Tax_Return_2023.pdf". Grey, white page.
  file,

  /// Work under way — "Fetching …". Grey, accent spinner.
  busy,

  /// No network — "You're offline". Grey, white Wi-Fi-off glyph. From the
  /// Library flow's islands (E5): waiting, not failing, so it is not red.
  offline,
}

/// The five treatments from `Hawk Snackbars.dc.html` section 2, "Top island":
/// black capsules that drop from under the Dynamic Island.
///
/// A sealed union rather than one class with flags: a progress snack has a
/// fraction and no auto-dismiss, an undo snack has a countdown, and
/// expressing all of that on one type means every field is optional and every
/// combination is representable — including the nonsensical ones.
@freezed
sealed class Snack with _$Snack {
  const Snack._();

  /// 2A — the everyday result. Hugs its text, one line, cyan check.
  const factory Snack.confirmation({
    required String message,
    SnackAction? action,
    @Default(_defaultHold) Duration hold,
  }) = ConfirmationSnack;

  /// 2B — an event that needs a name *and* a state, where one line would
  /// truncate. [mark] says which kind; failures must pass
  /// [SnackMark.failure], because the red is the only thing that tells a
  /// failure from information at a glance.
  const factory Snack.detail({
    required String title,
    required String subtitle,
    SnackAction? action,
    @Default(SnackMark.info) SnackMark mark,
    @Default(_defaultHold) Duration hold,
  }) = DetailSnack;

  /// 2C — persistent status. Ring and numeral, and the only × in the system.
  const factory Snack.progress({
    required String message,
    required double fraction,
    VoidCallback? onCancel,
  }) = ProgressSnack;

  /// 2D — the mark itself as the glyph, reserved strictly for things Hawk
  /// did on its own. Users learn that an orb means the assistant, not the
  /// system.
  const factory Snack.assistant({
    required String message,
    VoidCallback? onOpen,
    @Default(_defaultHold) Duration hold,
  }) = AssistantSnack;

  /// 2E — the one destructive path. The ring drains as the window closes, so
  /// "nothing goes without your confirmation" is visible rather than promised.
  const factory Snack.undo({
    required String message,
    required VoidCallback onUndo,
    @Default(_undoHold) Duration hold,
  }) = UndoSnack;

  /// Persistent snacks are dismissed by the app, not by a timer.
  bool get isPersistent => this is ProgressSnack;

  Duration? get autoDismissAfter => switch (this) {
    ConfirmationSnack(:final hold) => hold,
    DetailSnack(:final hold) => hold,
    AssistantSnack(:final hold) => hold,
    UndoSnack(:final hold) => hold,
    ProgressSnack() => null,
  };

  /// Only persistent bars get a close button; everything else is a swipe.
  bool get hasCloseButton => this is ProgressSnack;

  String get semanticLabel => switch (this) {
    ConfirmationSnack(:final message) => message,
    DetailSnack(:final title, :final subtitle) => '$title. $subtitle',
    ProgressSnack(:final message, :final fraction) =>
      '$message, ${(fraction * 100).round()} percent',
    AssistantSnack(:final message) => message,
    UndoSnack(:final message) => message,
  };
}
