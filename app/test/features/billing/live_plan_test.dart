import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/features/billing/data/live_plan.dart';
import 'package:knowra/src/features/billing/domain/entities/subscription.dart';

final _morning = DateTime.utc(2026, 9, 24, 10);

/// `get_subscription` for a free user who has used [used] of two answers in
/// the window (and as many this week).
Snapshot _free(int used, {int indexUsed = 0, DateTime? nextAt}) => {
  'tier': 'free',
  'limits': {
    'windowQueries': 2,
    'windowHours': 2,
    'weeklyQueries': 20,
    'memoryDays': 30,
    'indexBytes': 2147483648,
  },
  'answers': {
    'window': {
      'limit': 2,
      'used': used,
      'remaining': 2 - used,
      'hours': 2,
      'nextAt': nextAt?.toIso8601String(),
    },
    'week': {
      'limit': 20,
      'used': used,
      'remaining': 20 - used,
      'resetsAt': '2026-09-28T00:00:00.000Z',
    },
  },
  'index': {
    'limit': 2147483648,
    'used': indexUsed,
    'remaining': 2147483648 - indexUsed,
  },
};

/// The Firestore side, driven by hand: the documents the plan listens to,
/// and a `get_subscription` whose answer the test sets.
class _Backend {
  final plan = StreamController<Snapshot>();
  final account = StreamController<Object?>();
  final usage = StreamController<Object?>();
  Snapshot? answer = _free(0);
  var calls = 0;

  /// Replies land in the order the test releases them, not the order they
  /// were asked — so a slow early answer can be made to arrive late.
  final held = <Completer<Snapshot?>>[];
  bool hold = false;

  Future<Snapshot?> allowances() {
    calls++;
    if (!hold) return Future.value(answer);
    final reply = Completer<Snapshot?>();
    held.add(reply);
    return reply.future;
  }

  /// A snapshot listener's first event: the state it found on attaching.
  void attach() {
    usage.add(null);
    account.add(null);
  }
}

void main() {
  ({
    List<Subscription> seen,
    _Backend backend,
    StreamSubscription<Subscription> sub,
  })
  start(FakeAsync async, {Snapshot? first}) {
    final backend = _Backend();
    if (first != null) backend.answer = first;
    final seen = <Subscription>[];
    final sub = LivePlan(
      plan: backend.plan.stream,
      account: backend.account.stream,
      usage: backend.usage.stream,
      allowances: backend.allowances,
      now: () => _morning.add(async.elapsed),
    ).watch().listen(seen.add);

    backend
      ..attach()
      ..plan.add(const {});
    async.flushMicrotasks();
    return (seen: seen, backend: backend, sub: sub);
  }

  test('reads the plan once on open, not once per listener', () {
    fakeAsync((async) {
      final (:seen, :backend, :sub) = start(async);
      async.elapse(const Duration(seconds: 1));

      expect(backend.calls, 1);
      expect(seen.single.window.remaining, 2);
      expect(seen.single.week.remaining, 20);
      unawaited(sub.cancel());
    });
  });

  test('an answer updates both counts', () {
    fakeAsync((async) {
      final (:seen, :backend, :sub) = start(async);

      backend.answer = _free(1);
      backend.usage.add(null); // the server's reservation
      async.elapse(const Duration(milliseconds: 400));

      expect(seen.last.window.used, 1);
      expect(seen.last.window.remaining, 1);
      expect(seen.last.week.used, 1);
      unawaited(sub.cancel());
    });
  });

  test('the second answer locks the gate, before a third is tried', () {
    fakeAsync((async) {
      final (:seen, :backend, :sub) = start(async);

      backend.answer = _free(2, nextAt: _morning.add(const Duration(hours: 2)));
      backend.usage.add(null);
      async.elapse(const Duration(milliseconds: 400));

      expect(seen.last.canAsk, isFalse);
      expect(seen.last.askLock, isNotNull);
      expect(seen.last.askAvailableAt, _morning.add(const Duration(hours: 2)));
      unawaited(sub.cancel());
    });
  });

  test('an answer coming back unlocks it — with nothing written to hear', () {
    // Nothing changes in Firestore when an answer ages out of the window, so
    // no listener fires. The plan schedules its own re-read for that moment.
    fakeAsync((async) {
      final back = _morning.add(const Duration(minutes: 30));
      final (:seen, :backend, :sub) = start(
        async,
        first: _free(2, nextAt: back),
      );
      expect(seen.last.canAsk, isFalse);
      final before = backend.calls;

      backend.answer = _free(1, nextAt: _morning.add(const Duration(hours: 2)));
      async.elapse(const Duration(minutes: 30, seconds: 2));

      expect(backend.calls, before + 1);
      expect(seen.last.canAsk, isTrue, reason: 'no restart, no tap needed');
      expect(seen.last.window.remaining, 1);
      unawaited(sub.cancel());
    });
  });

  test('indexing moves the index meter', () {
    fakeAsync((async) {
      final (:seen, :backend, :sub) = start(async);

      backend.answer = _free(0, indexUsed: 52428800);
      backend.account.add(null); // indexedBytes changed
      async.elapse(const Duration(milliseconds: 400));

      expect(seen.last.index.used, 52428800);
      unawaited(sub.cancel());
    });
  });

  test('a batch of forty indexed files is one re-read, not forty', () {
    fakeAsync((async) {
      final (:backend, :sub, seen: _) = start(async);

      for (var i = 0; i < 40; i++) {
        backend.account.add(null);
        async.elapse(const Duration(milliseconds: 50));
      }
      async.elapse(const Duration(milliseconds: 400));

      expect(backend.calls, 2, reason: 'the open, then one settled re-read');
      unawaited(sub.cancel());
    });
  });

  test('an upgrade shows at once', () {
    fakeAsync((async) {
      final (:seen, :backend, :sub) = start(async);

      backend.answer = {
        'tier': 'premium',
        'limits': {'windowQueries': 25, 'weeklyQueries': 400},
        'answers': {
          'window': {'remaining': 25},
          'week': {'remaining': 400},
        },
      };
      backend.plan.add({'tier': 'premium', 'status': 'active'});
      async.flushMicrotasks();

      expect(seen.last.tier, Tier.premium);
      expect(seen.last.isPaid, isTrue);
      expect(seen.last.window.limit, 25);
      unawaited(sub.cancel());
    });
  });

  test('a failed re-read keeps the last numbers, then retries', () {
    fakeAsync((async) {
      final (:seen, :backend, :sub) = start(async);
      backend.answer = _free(1);
      backend.usage.add(null);
      async.elapse(const Duration(milliseconds: 400));
      expect(seen.last.window.remaining, 1);

      backend.answer = null; // the network blinks
      backend.usage.add(null);
      async.elapse(const Duration(milliseconds: 400));
      expect(
        seen.last.window.remaining,
        1,
        reason: 'not "unlimited" — that is what an empty answer parses as',
      );

      backend.answer = _free(2);
      async.elapse(LivePlan.retries.first);
      expect(seen.last.window.remaining, 0);
      unawaited(sub.cancel());
    });
  });

  test('retries stop when the phone stays offline', () {
    fakeAsync((async) {
      final (:backend, :sub, seen: _) = start(async);
      backend.answer = null;
      backend.account.add(null);
      async.elapse(const Duration(hours: 1));

      // The settled re-read, then the three bounded retries.
      expect(backend.calls, 1 + 1 + LivePlan.retries.length);
      unawaited(sub.cancel());
    });
  });

  test('a slow old answer never overwrites a newer one', () {
    fakeAsync((async) {
      final (:seen, :backend, :sub) = start(async);
      backend.hold = true;

      backend.usage.add(null);
      async.elapse(const Duration(milliseconds: 400)); // re-read A
      backend.usage.add(null);
      async.elapse(const Duration(milliseconds: 400)); // re-read B

      backend.held[1].complete(_free(2)); // B lands first
      async.flushMicrotasks();
      backend.held[0].complete(_free(1)); // A, late and stale
      async.flushMicrotasks();

      expect(seen.last.window.used, 2);
      unawaited(sub.cancel());
    });
  });

  test('cancelling leaves nothing running — the return timer included', () {
    fakeAsync((async) {
      final (:backend, :sub, seen: _) = start(
        async,
        first: _free(1, nextAt: _morning.add(const Duration(hours: 2))),
      );
      backend.account.add(null);
      unawaited(sub.cancel());
      async
        ..flushMicrotasks()
        ..elapse(const Duration(days: 8));

      expect(backend.calls, 1);
      expect(async.pendingTimers, isEmpty);
    });
  });

  group('reading get_subscription', () {
    test('a missing count is unknown use, not a full meter', () {
      final plan = subscriptionFrom(const {}, {
        'limits': {'windowQueries': 2, 'weeklyQueries': 20},
      });
      expect(plan.window.used, 0);
      expect(plan.canAsk, isTrue);
    });

    test('the next turn is the earliest future return or reset', () {
      final live = _free(2, nextAt: _morning.add(const Duration(minutes: 40)));
      expect(
        nextTurn(live, _morning),
        _morning.add(const Duration(minutes: 40)),
      );
      // Once the answer is back, the week's reset is next.
      expect(
        nextTurn(live, _morning.add(const Duration(hours: 1))),
        DateTime.utc(2026, 9, 28),
      );
      expect(nextTurn(const {}, _morning), isNull);
    });
  });

  group('the last plan, on open', () {
    test('shows before the live answer, which then replaces it', () {
      fakeAsync((async) {
        final backend = _Backend()..hold = true;
        final seen = <Subscription>[];
        final sub = LivePlan(
          plan: backend.plan.stream,
          account: backend.account.stream,
          usage: backend.usage.stream,
          allowances: backend.allowances,
          cached: () async => {
            'tier': 'premium',
            'limits': {'windowQueries': 25, 'weeklyQueries': 400},
            'answers': {
              'window': {'remaining': 24},
              'week': {'remaining': 390},
            },
          },
          now: () => _morning.add(async.elapsed),
        ).watch().listen(seen.add);

        backend.plan.add(const {});
        async.flushMicrotasks();
        expect(
          seen.single.tier,
          Tier.premium,
          reason: 'not the free tier while the call is in flight',
        );

        backend.held.single.complete({
          'tier': 'premium',
          'limits': {'windowQueries': 25, 'weeklyQueries': 400},
          'answers': {
            'window': {'remaining': 20},
            'week': {'remaining': 385},
          },
        });
        async.flushMicrotasks();
        expect(seen.last.window.remaining, 20);
        unawaited(sub.cancel());
      });
    });

    test('a cached answer arriving late never overwrites the live one', () {
      fakeAsync((async) {
        final backend = _Backend()..answer = _free(1);
        final late = Completer<Snapshot?>();
        final seen = <Subscription>[];
        final sub = LivePlan(
          plan: backend.plan.stream,
          account: backend.account.stream,
          usage: backend.usage.stream,
          allowances: backend.allowances,
          cached: () => late.future,
          now: () => _morning.add(async.elapsed),
        ).watch().listen(seen.add);

        backend.plan.add(const {});
        async.flushMicrotasks();
        late.complete(_free(0));
        async.flushMicrotasks();

        expect(seen.last.window.used, 1);
        unawaited(sub.cancel());
      });
    });

    test(
      'counts from before an answer came back are dropped, the plan kept',
      () {
        final stale = usableNow(
          _free(2, nextAt: _morning.subtract(const Duration(minutes: 5))),
          _morning,
        );
        expect(stale.containsKey('answers'), isFalse);
        expect(stale['limits'], isNotNull);
        expect(subscriptionFrom(const {}, stale).canAsk, isTrue);

        final current = usableNow(
          _free(1, nextAt: _morning.add(const Duration(minutes: 5))),
          _morning,
        );
        expect(current.containsKey('answers'), isTrue);
      },
    );
  });
}
