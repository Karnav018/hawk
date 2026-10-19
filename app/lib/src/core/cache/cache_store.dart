import 'dart:async';
import 'dart:convert';

import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../logging/app_logger.dart';
import 'cache_policy.dart';

/// A callable's result, made storable.
///
/// Callables hand back `Map<Object?, Object?>` all the way down, which
/// `jsonEncode` refuses. Keys become strings; lists and nested maps are
/// converted the same way; everything else is left as it is.
Map<String, dynamic> jsonSafe(Map<Object?, Object?> map) => {
  for (final MapEntry(:key, :value) in map.entries)
    key.toString(): _jsonSafeValue(value),
};

Object? _jsonSafeValue(Object? value) => switch (value) {
  final Map<Object?, Object?> m => jsonSafe(m),
  final List<Object?> l => [for (final v in l) _jsonSafeValue(v)],
  _ => value,
};

/// A cached value plus when it was written.
///
/// The timestamp travels with the value rather than living in a parallel key,
/// because two keys that can be written independently will eventually
/// disagree — and a value with a lost timestamp is a value that never expires.
class CacheEntry<T> {
  const CacheEntry(this.value, this.storedAt);

  final T value;
  final DateTime storedAt;

  Duration age({DateTime? now}) => (now ?? DateTime.now()).difference(storedAt);

  bool isFresh(Duration ttl, {DateTime? now}) => age(now: now) < ttl;
}

/// Read-through cache for things Firestore's own offline layer does not cover.
///
/// Firestore documents already cache themselves — `snapshots()` serves the
/// local copy first and the app renders instantly offline. **Callables do
/// not.** Every `httpsCallable` is a cold network round trip, and the
/// expensive ones in this app (walking a user's Drive) are exactly the ones a
/// user re-triggers by tapping Back and then Forward. That gap is what this
/// fills.
///
/// Every key is namespaced by user id. Not a nicety: without it, signing out
/// and signing in as somebody else on a shared device would serve them the
/// previous person's folder names.
abstract interface class CacheStore {
  Future<CacheEntry<Map<String, dynamic>>?> read(String key);

  Future<void> write(String key, Map<String, dynamic> value);

  Future<void> evict(String key);

  /// Drops everything for the signed-in user. Called on sign-out.
  Future<void> clear();

  /// Binds subsequent operations to a user. Passing null (sign-out) makes
  /// every read miss, so a cache left uncleared because of a crash still cannot
  /// leak across accounts.
  void bindUser(String? userId);
}

@LazySingleton(as: CacheStore)
class PrefsCacheStore implements CacheStore {
  PrefsCacheStore(this._logger);

  final AppLogger _logger;

  static const _prefix = 'cache';
  static const _valueKey = 'v';
  static const _storedAtKey = 't';

  String? _userId;
  SharedPreferences? _prefs;

  @override
  void bindUser(String? userId) => _userId = userId;

  Future<SharedPreferences> get _store async =>
      _prefs ??= await SharedPreferences.getInstance();

  String? _key(String key) => _userId == null ? null : '$_prefix:$_userId:$key';

  @override
  Future<CacheEntry<Map<String, dynamic>>?> read(String key) async {
    final scoped = _key(key);
    if (scoped == null) return null;

    try {
      final raw = (await _store).getString(scoped);
      if (raw == null) return null;

      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final storedAt = DateTime.fromMillisecondsSinceEpoch(
        decoded[_storedAtKey] as int,
      );

      if (DateTime.now().difference(storedAt) > CachePolicy.hardExpiry) {
        await evict(key);
        return null;
      }
      return CacheEntry(decoded[_valueKey] as Map<String, dynamic>, storedAt);
    } catch (error) {
      // A cache is an optimisation. An unreadable entry — a shape change
      // between builds, a truncated write — must degrade to a miss, never to
      // an error the user sees.
      _logger.breadcrumb('cache read failed', category: 'cache');
      await evict(key);
      return null;
    }
  }

  @override
  Future<void> write(String key, Map<String, dynamic> value) async {
    final scoped = _key(key);
    if (scoped == null) return;
    try {
      await (await _store).setString(
        scoped,
        jsonEncode({
          _valueKey: value,
          _storedAtKey: DateTime.now().millisecondsSinceEpoch,
        }),
      );
    } catch (error) {
      _logger.breadcrumb('cache write failed', category: 'cache');
    }
  }

  @override
  Future<void> evict(String key) async {
    final scoped = _key(key);
    if (scoped == null) return;
    await (await _store).remove(scoped);
  }

  @override
  Future<void> clear() async {
    final store = await _store;
    final mine = '$_prefix:${_userId ?? ''}:';
    for (final key in store.getKeys().where((k) => k.startsWith(mine))) {
      await store.remove(key);
    }
  }
}
