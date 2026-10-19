import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/core/cache/cache_policy.dart';
import 'package:knowra/src/core/cache/cache_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_logger.dart';

void main() {
  late PrefsCacheStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = PrefsCacheStore(FakeLogger());
    store.bindUser('user-a');
  });

  test('round-trips a value', () async {
    await store.write('k', {'hello': 'world'});
    final entry = await store.read('k');
    expect(entry!.value, {'hello': 'world'});
    expect(entry.isFresh(const Duration(minutes: 5)), isTrue);
  });

  test('an unbound store misses every read', () async {
    // Sign-out calls bindUser(null). Anything left on disk from a crash must
    // stay unreadable rather than leaking to the next person to sign in.
    await store.write('k', {'hello': 'world'});
    store.bindUser(null);
    expect(await store.read('k'), isNull);
  });

  test('one user cannot read another user\'s entries', () async {
    await store.write('k', {'secret': 'folder names'});
    store.bindUser('user-b');
    expect(await store.read('k'), isNull);
  });

  test('clear only removes the bound user\'s entries', () async {
    await store.write('k', {'a': 1});
    store.bindUser('user-b');
    await store.write('k', {'b': 2});

    await store.clear();
    expect(await store.read('k'), isNull);

    store.bindUser('user-a');
    expect((await store.read('k'))!.value, {'a': 1});
  });

  test('a corrupt entry degrades to a miss, not an exception', () async {
    // A cache is an optimisation. A shape change between builds must never
    // become an error the user sees.
    SharedPreferences.setMockInitialValues({
      'cache:user-a:k': 'not json at all',
    });
    store = PrefsCacheStore(FakeLogger())..bindUser('user-a');
    expect(await store.read('k'), isNull);
  });

  test(
    'anything past the hard ceiling is dropped rather than served',
    () async {
      final ancient = DateTime.now().subtract(CachePolicy.hardExpiry * 2);
      SharedPreferences.setMockInitialValues({
        'cache:user-a:k': '{"v":{"a":1},"t":${ancient.millisecondsSinceEpoch}}',
      });
      store = PrefsCacheStore(FakeLogger())..bindUser('user-a');
      expect(await store.read('k'), isNull);
    },
  );

  test('isFresh is measured against the stored moment', () {
    final entry = CacheEntry(const {'a': 1}, DateTime(2026, 8, 29, 10));
    final later = DateTime(2026, 8, 29, 10, 11);
    expect(entry.isFresh(CachePolicy.providerFolders, now: later), isFalse);
    expect(entry.isFresh(CachePolicy.providerCatalogue, now: later), isTrue);
  });
}
