import '../entities/account_overview.dart';

/// Everything that can happen to an account after it exists.
///
/// [deactivate] and [delete] are separate methods rather than one with a
/// flag, on purpose. A boolean parameter is the kind of thing that gets
/// passed the wrong way round, and one of these two is not recoverable.
abstract interface class AccountRepository {
  Future<AccountOverview> overview();

  /// The last summary [overview] returned, from this device's cache — or
  /// null when there is none. For drawing a screen at once while [overview]
  /// fetches the current one; never for a decision, because it can be stale.
  Future<AccountOverview?> cachedOverview();

  /// Reversible. Disconnects storage and stops indexing; keeps everything.
  Future<void> deactivate();

  Future<void> reactivate();

  /// Turns offers and news by email on or off. Recorded on the server with
  /// the time, because consent has to be provable later.
  Future<void> setMarketingConsent({required bool optIn});

  /// Final. [confirmation] must be the exact phrase the server demands —
  /// it is checked there too, so a client that skips the typing still
  /// cannot delete anything.
  Future<void> delete({required String confirmation});

  /// The phrase [delete] requires. Lives here so the screen and the server
  /// cannot drift apart.
  static const deletePhrase = 'DELETE';
}
