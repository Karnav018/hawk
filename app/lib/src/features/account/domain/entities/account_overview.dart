import 'package:freezed_annotation/freezed_annotation.dart';

part 'account_overview.freezed.dart';

/// What the profile screen knows about the signed-in account.
///
/// One object from one call. The alternative — the screen reading its own
/// counts from Firestore — would be a document read per memory just to print
/// "214 memories", every time the screen opened.
@freezed
abstract class AccountOverview with _$AccountOverview {
  const factory AccountOverview({
    String? email,
    String? name,
    DateTime? createdAt,
    @Default(AccountStatus.active) AccountStatus status,

    /// Total memories, indexed and dormant.
    @Default(0) int memories,
    @Default(0) int indexed,

    /// Memories whose source went away — a disconnected account, usually.
    @Default(0) int dormant,
    @Default(0) int accounts,

    /// What the vault holds, grouped the way a person names it — documents,
    /// recordings, images. Screen 1R prints these as chips under the total.
    ///
    /// Grouped server-side rather than here: the counts come from Firestore
    /// aggregations over the pipeline's eleven memory types, and mapping
    /// eleven types to three words in the client would put that taxonomy in
    /// two places. Empty when the server is older than the field.
    @Default(<String, int>{}) Map<String, int> byKind,

    /// True when this address is on the server's test-account list and is
    /// being granted the top tier without paying for it. Shown, loudly: a
    /// privileged path nobody can see is one nobody remembers to remove.
    @Default(false) bool isTestAccount,

    /// Whether offers and news by email reach this user. On by default until
    /// they turn it off; only the server changes it (`set_marketing_consent`,
    /// or the unsubscribe link).
    @Default(true) bool marketingOptIn,
  }) = _AccountOverview;

  const AccountOverview._();

  /// A count the server could not produce comes back as -1 rather than 0,
  /// because "we do not know" and "none" are different facts and only one of
  /// them should read as an empty vault.
  static String count(int value) => value < 0 ? '—' : '$value';

  bool get isDeactivated => status == AccountStatus.deactivated;
}

enum AccountStatus {
  active,
  deactivated;

  static AccountStatus parse(String? raw) =>
      raw == 'deactivated' ? deactivated : active;
}
