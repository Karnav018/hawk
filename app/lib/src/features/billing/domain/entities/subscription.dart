import 'package:freezed_annotation/freezed_annotation.dart';

part 'subscription.freezed.dart';

/// The three plans. Mirrors `firebase/functions/billing.py`.
enum Tier {
  free,
  standard,
  premium;

  static Tier parse(String? raw) => switch (raw) {
    'standard' => standard,
    'premium' => premium,
    _ => free,
  };

  String get label => switch (this) {
    free => 'Free',
    standard => 'Standard',
    premium => 'Premium',
  };

  bool get isPaid => this != free;
}

/// Where a subscription stands with the store.
///
/// `inGrace` exists because a declined card must not read as data loss while
/// the store is still retrying the payment — the user keeps everything, and
/// the app asks them to fix the card rather than telling them their memories
/// are gone.
enum SubscriptionStatus {
  active,
  inTrial,
  inGrace,
  expired,
  refunded;

  static SubscriptionStatus parse(String? raw) => switch (raw) {
    'active' => active,
    'in_trial' => inTrial,
    'in_grace' => inGrace,
    'refunded' => refunded,
    _ => expired,
  };

  bool get isEntitled => this == active || this == inTrial || this == inGrace;

  bool get needsAttention => this == inGrace;
}

/// A consumable allowance, as the server reports it. Null limit = no ceiling.
@freezed
abstract class Allowance with _$Allowance {
  const factory Allowance({int? limit, @Default(0) int used, int? remaining}) =
      _Allowance;

  const Allowance._();

  bool get isUnlimited => limit == null;

  /// 0–1, for a meter. Zero when unlimited, because a full bar would imply a
  /// ceiling that does not exist.
  double get fraction {
    final cap = limit;
    if (cap == null || cap == 0) return 0;
    return (used / cap).clamp(0.0, 1.0);
  }

  bool get isExhausted => remaining != null && remaining! <= 0;
}

@freezed
abstract class Subscription with _$Subscription {
  const factory Subscription({
    @Default(Tier.free) Tier tier,
    @Default(SubscriptionStatus.active) SubscriptionStatus status,

    /// Answers in the rolling window. Each comes back [windowHours] after it
    /// was used, on its own — nothing resets all at once (`usage.py`).
    @Default(Allowance()) Allowance window,

    /// Answers this week — the cost cap, reset Monday 00:00 in the user's
    /// own zone.
    @Default(Allowance()) Allowance week,
    @Default(Allowance()) Allowance index,

    /// Days a memory stays searchable. Null = forever.
    int? memoryWindowDays,
    int? connectedAccounts,
    DateTime? currentPeriodEnd,
    @Default(2) int windowHours,

    /// When the oldest answer in the window comes back. Null when none is
    /// out.
    DateTime? windowNextAt,
    DateTime? weekResetsAt,
    @Default(false) bool autoRenewing,

    /// The store product this plan was bought as, and which store sold it.
    /// Screen 2J needs both: the product to price the next charge, and the
    /// store to send "Change" to the right place. Null on free.
    String? productId,
    String? store,

    /// How many memories have fallen outside the memory window.
    ///
    /// The single most persuasive number on a paywall, and the reason
    /// retention demotes rather than deletes (§36): "1,204 memories are
    /// waiting" is an offer to restore something, not a threat.
    @Default(0) int memoriesDormant,
  }) = _Subscription;

  const Subscription._();

  bool get isPaid => tier.isPaid && status.isEntitled;

  /// Whether an upgrade would actually change anything for this user.
  bool get canUpgrade => tier != Tier.premium;

  // ---------------------------------------------------------------------
  // What is unlocked. These are the questions the UI actually asks, phrased
  // as the UI asks them — so a screen never has to reason about limits, and
  // two screens can never disagree about what the same plan permits.
  // ---------------------------------------------------------------------

  /// Can another question be answered right now. Searching is never
  /// limited — it runs on the phone — so this is only about answers.
  bool get canAsk => !window.isExhausted && !week.isExhausted;

  /// Whether the week, rather than the window, is what stops the next
  /// answer: the one that frees *later* is when asking really comes back.
  bool get askBlockedForWeek {
    if (!week.isExhausted) return false;
    if (!window.isExhausted) return true;
    final weekAt = weekResetsAt;
    final windowAt = windowNextAt;
    return weekAt == null || windowAt == null || !weekAt.isBefore(windowAt);
  }

  /// The allowance that is spent, for the limit sheet's meter.
  Allowance get blockingAnswers => askBlockedForWeek ? week : window;

  /// When an answer can next be had, or null when one can now.
  DateTime? get askAvailableAt =>
      canAsk ? null : (askBlockedForWeek ? weekResetsAt : windowNextAt);

  /// Can anything more be indexed.
  bool get canIndex => !index.isExhausted;

  /// Can another storage account be connected.
  ///
  /// Takes the current count rather than holding it: the connector screen
  /// already streams the live account list, and a second copy here would be
  /// a second source of truth about the same number.
  bool canConnect(int connected) =>
      connectedAccounts == null || connected < connectedAccounts!;

  /// Why an answer is unavailable, in the user's terms — or null if it is.
  ///
  /// Says which limit and when it frees, because that is what turns a wall
  /// into a wait. Premium has nothing above it, so its lock never offers an
  /// upgrade: a button there would sell nothing.
  PlanLock? get askLock {
    if (canAsk) return null;
    if (askBlockedForWeek) {
      return PlanLock(
        reason:
            "That's all ${week.limit} answers this week. They reset on Monday.",
        upgradeable: canUpgrade,
      );
    }
    final at = windowNextAt;
    return PlanLock(
      reason:
          "That's your ${window.limit} answers for now."
          '${at == null ? '' : ' The next one is back at ${answerClock(at)}.'}',
      upgradeable: canUpgrade,
    );
  }

  /// Why indexing is unavailable, or null if it is not.
  PlanLock? get indexLock => canIndex
      ? null
      : PlanLock(
          reason: tier == Tier.premium
              ? 'Your index is full. Free up space to add more.'
              : 'Your plan\'s index is full.',
          upgradeable: tier != Tier.premium,
        );

  PlanLock? connectLock(int connected) => canConnect(connected)
      ? null
      : PlanLock(
          reason: connectedAccounts == 1
              ? 'Your plan connects one account.'
              : 'Your plan connects $connectedAccounts accounts.',
          upgradeable: tier != Tier.premium,
        );
}

/// Why something is unavailable, and whether paying would change that.
///
/// [upgradeable] is the field that matters. A locked thing that an upgrade
/// unlocks deserves an upgrade button; one that it does not — a fair-use
/// ceiling, a full index on the top tier — must not have one, or the app is
/// selling something it cannot deliver.
class PlanLock {
  const PlanLock({required this.reason, required this.upgradeable});

  final String reason;
  final bool upgradeable;
}

/// "3:12 pm", in the phone's own time — how the app names the moment an
/// answer comes back.
String answerClock(DateTime at) {
  final local = at.toLocal();
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${local.hour < 12 ? 'am' : 'pm'}';
}
