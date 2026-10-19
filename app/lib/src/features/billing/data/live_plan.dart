import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../domain/entities/subscription.dart';

typedef Snapshot = Map<String, dynamic>;

/// Keeps the plan on screen current with what the user has actually used.
///
/// **The plan used to refresh only when the subscription document changed**
/// — a purchase, a renewal, a refund. But the numbers people watch live
/// somewhere else: every answer is written to `users/{uid}/usage/answers`,
/// and every indexed file adds to `indexedBytes` on `users/{uid}`. Neither
/// touches the subscription document, so for a free user — whose
/// subscription document never changes at all — the counts were read once
/// at sign-in and then frozen.
///
/// So the plan listens to all of it, and re-reads the allowances when any of
/// them moves:
///
/// * the subscription document — immediately, since a tier change is news;
/// * the answer ledger and the account's byte counters — after a short
///   [settle], so indexing a batch of forty files is one re-read, not forty;
/// * **the moment the next answer comes back, or the week resets.** Nothing
///   is written when an answer ages out of the two-hour window, so no
///   listener would fire; without this the meter would sit at "0 left"
///   after one had returned.
///
/// Every re-read is still `get_subscription`, never arithmetic done here on
/// the raw ledger: the server owns what a plan permits, and a client that
/// computed its own remaining answers would drift from the one that
/// enforces them. The listeners and the timer only decide *when* to ask.
class LivePlan {
  LivePlan({
    required this.plan,
    required this.account,
    required this.usage,
    required this.allowances,
    this.cached,
    this.now = DateTime.now,
    this.settle = const Duration(milliseconds: 300),
  });

  /// The subscription document's data — `{}` when there is none, as for a
  /// user who has never paid.
  final Stream<Snapshot> plan;

  /// The account document, whose byte counters move as files are indexed
  /// and deleted. Only *that* it changed matters, not what it says.
  final Stream<Object?> account;

  /// The answer ledger (`usage/answers`), written on every answer taken or
  /// handed back.
  final Stream<Object?> usage;

  /// `get_subscription`'s answer, or null when it could not be reached.
  final Future<Snapshot?> Function() allowances;

  /// The last answer [allowances] gave on this device, for drawing the plan
  /// the moment the app opens. Before it, every launch showed the free tier
  /// until the call returned. The live answer always replaces it.
  final Future<Snapshot?> Function()? cached;

  final DateTime Function() now;
  final Duration settle;

  /// Waits after a failed re-read before trying again. Bounded: a phone
  /// that is offline for an hour should not spend it calling a server it
  /// cannot reach. The next change retries anyway.
  static const retries = [
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(seconds: 45),
  ];

  Stream<Subscription> watch() {
    late final StreamController<Subscription> out;
    StreamSubscription<Snapshot>? planSub;
    StreamSubscription<Object?>? accountSub;
    StreamSubscription<Object?>? usageSub;
    Timer? pending;
    Timer? turn;

    Snapshot? doc;
    // Whether a live answer has arrived yet. Until then, [live] may hold the
    // cached one.
    var fresh = false;
    // The last allowances that arrived. A failed re-read keeps these rather
    // than falling back to nothing — which parses as *unlimited*, and would
    // flash an unmetered plan at a metered user every time the network
    // blinked.
    Snapshot live = const {};
    var generation = 0;
    var failures = 0;

    void schedule(Duration after, Future<void> Function() run) {
      pending?.cancel();
      pending = Timer(after, () => unawaited(run()));
    }

    late Future<void> Function() refresh;

    // The next moment the allowance changes on its own: an answer coming
    // back, or the week resetting. A second past it, so the server's clock
    // is past it too.
    void scheduleTurn() {
      turn?.cancel();
      final at = nextTurn(live, now());
      if (at == null || out.isClosed) return;
      turn = Timer(
        at.difference(now()) + const Duration(seconds: 1),
        () => unawaited(refresh()),
      );
    }

    refresh = () async {
      pending?.cancel();
      final mine = ++generation;
      final fetched = await allowances();
      // A newer re-read started while this one was in flight — a second ask,
      // a tier change. Its answer is the current one; this one is history.
      if (mine != generation || out.isClosed) return;
      final current = doc;
      if (current == null) return;

      if (fetched == null) {
        if (failures < retries.length) {
          schedule(retries[failures], refresh);
        }
        failures++;
      } else {
        failures = 0;
        fresh = true;
        live = fetched;
      }
      out.add(subscriptionFrom(current, live));
      scheduleTurn();
    };

    void soon() => schedule(settle, refresh);

    void showCached(Snapshot? head) {
      if (head == null || fresh || out.isClosed) return;
      live = usableNow(head, now());
      final current = doc;
      if (current != null) out.add(subscriptionFrom(current, live));
    }

    out = StreamController<Subscription>(
      onListen: () {
        final read = cached;
        if (read != null) {
          unawaited(read().then(showCached, onError: (Object _) {}));
        }
        // `skip(1)`: a listener's first event is the state it found, not a
        // change — and the plan's own first read already has it.
        usageSub = usage.skip(1).listen((_) => soon(), onError: (Object _) {});
        accountSub = account
            .skip(1)
            .listen((_) => soon(), onError: (Object _) {});
        planSub = plan.listen((data) {
          doc = data;
          // With a cached answer in hand, draw it now rather than after the
          // call — the refresh below replaces it.
          if (!fresh && live.isNotEmpty) {
            out.add(subscriptionFrom(data, live));
          }
          unawaited(refresh());
        }, onError: out.addError);
      },
      onCancel: () async {
        pending?.cancel();
        turn?.cancel();
        generation++;
        await Future.wait([
          ?planSub?.cancel(),
          ?accountSub?.cancel(),
          ?usageSub?.cancel(),
        ]);
      },
    );
    return out.stream;
  }
}

Map<String, dynamic> _map(Object? value) =>
    value is Map ? value.cast<String, dynamic>() : const {};

DateTime? _at(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

/// When the answer allowance next changes on its own — the oldest answer in
/// the window coming back, or the week resetting — if that is after [now].
@visibleForTesting
DateTime? nextTurn(Snapshot live, DateTime now) {
  final answers = _map(live['answers']);
  final moments = [
    _at(_map(answers['window'])['nextAt']),
    _at(_map(answers['week'])['resetsAt']),
  ].whereType<DateTime>().where((at) => at.isAfter(now)).toList()..sort();
  return moments.isEmpty ? null : moments.first;
}

/// A cached `get_subscription` answer, safe to draw [now].
///
/// Everything in it describes the plan and stays true — except the answer
/// counts, which change on their own as answers come back and weeks reset.
/// Counts from before such a moment are dropped rather than shown: a stale
/// "none left" would lock the ask gate for the second it takes the live
/// answer to arrive, exactly when the user has one back. Unknown is not
/// locked; the server still enforces.
@visibleForTesting
Snapshot usableNow(Snapshot cached, DateTime now) {
  final answers = _map(cached['answers']);
  final turned = [
    _at(_map(answers['window'])['nextAt']),
    _at(_map(answers['week'])['resetsAt']),
  ].whereType<DateTime>().any((at) => !at.isAfter(now));
  return turned ? ({...cached}..remove('answers')) : cached;
}

Allowance _allowance(Map<String, dynamic> part, int? limit) {
  final remaining = (part['remaining'] as num?)?.toInt();
  return Allowance(
    limit: limit,
    // Unknown remaining is unknown use, not all of it. The old reading took
    // a missing count as zero left, and showed a full meter.
    used: limit == null || remaining == null
        ? 0
        : (limit - remaining).clamp(0, limit),
    remaining: remaining,
  );
}

/// The plan, from the subscription document and `get_subscription`.
Subscription subscriptionFrom(Snapshot doc, Snapshot live) {
  final limits = _map(live['limits']);
  final index = _map(live['index']);
  final answers = _map(live['answers']);
  final window = _map(answers['window']);
  final week = _map(answers['week']);

  return Subscription(
    tier: Tier.parse((live['tier'] ?? doc['tier']) as String?),
    status: SubscriptionStatus.parse(doc['status'] as String?),
    window: _allowance(window, (limits['windowQueries'] as num?)?.toInt()),
    week: _allowance(week, (limits['weeklyQueries'] as num?)?.toInt()),
    windowHours: (limits['windowHours'] as num?)?.toInt() ?? 2,
    windowNextAt: _at(window['nextAt']),
    weekResetsAt: _at(week['resetsAt']),
    index: Allowance(
      limit: (index['limit'] as num?)?.toInt(),
      used: (index['used'] as num?)?.toInt() ?? 0,
      remaining: (index['remaining'] as num?)?.toInt(),
    ),
    memoryWindowDays: (limits['memoryDays'] as num?)?.toInt(),
    connectedAccounts: (limits['connectedAccounts'] as num?)?.toInt(),
    currentPeriodEnd: _moment(doc['currentPeriodEnd']),
    autoRenewing: doc['autoRenewing'] as bool? ?? false,
    productId: doc['productId'] as String?,
    store: doc['store'] as String?,
    memoriesDormant: (live['memoriesDormant'] as num?)?.toInt() ?? 0,
  );
}

DateTime? _moment(Object? value) => switch (value) {
  Timestamp() => value.toDate(),
  String() => DateTime.tryParse(value),
  _ => null,
};
