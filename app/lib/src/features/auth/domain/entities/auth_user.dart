import 'package:freezed_annotation/freezed_annotation.dart';

part 'auth_user.freezed.dart';

/// Screen 3J — "how you'll mostly ask". Voice is the product's default.
@JsonEnum(fieldRename: FieldRename.snake)
enum InputPreference {
  voice,
  typing;

  static InputPreference parse(String? raw) => raw == 'typing' ? typing : voice;
}

/// How someone proved who they are.
enum SocialProvider {
  apple,
  google;

  /// The wire value the backend expects.
  String get wireName => name;
}

@freezed
abstract class AuthUser with _$AuthUser {
  const factory AuthUser({
    required String id,
    required String email,
    String? name,
    @Default(InputPreference.voice) InputPreference inputPreference,
    DateTime? onboardedAt,

    /// Screens 3F–3L. Set when storage is connected *or* explicitly skipped —
    /// skipping is a real choice, and a device-only vault is a usable
    /// product, so "not yet decided" and "decided against" have to be
    /// different states or the user is parked on 3F forever.
    DateTime? storageSetupAt,
    @Default(0) int quotaBytes,
    @Default(0) int usedBytes,
  }) = _AuthUser;

  const AuthUser._();

  /// Screen 1F — "how will you mostly ask" — has not been answered yet.
  ///
  /// Named for the step rather than for the field it used to collect: v2
  /// asked for a name here and v3 does not, but `onboardedAt` is still what
  /// marks the step done, so the storage did not change when the question
  /// did.
  bool get needsAskStep => onboardedAt == null;

  /// Screens 3F–3L have not been completed or skipped yet.
  bool get needsStorageStep => storageSetupAt == null;

  /// Anywhere in the onboarding run. The router asks this; which *step* is
  /// outstanding is a separate question, answered by the two above, so adding
  /// a step later does not mean revisiting every caller.
  bool get needsOnboarding => needsAskStep || needsStorageStep;

  String get displayName {
    final trimmed = name?.trim();
    if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    return email.split('@').first;
  }
}
