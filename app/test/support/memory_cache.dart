import 'package:knowra/src/core/cache/cache_store.dart';

/// A [CacheStore] that lives in memory, for tests that need one to exist.
class MemoryCacheStore implements CacheStore {
  final _entries = <String, CacheEntry<Map<String, dynamic>>>{};

  @override
  Future<CacheEntry<Map<String, dynamic>>?> read(String key) async =>
      _entries[key];

  @override
  Future<void> write(String key, Map<String, dynamic> value) async =>
      _entries[key] = CacheEntry(value, DateTime.now());

  @override
  Future<void> evict(String key) async => _entries.remove(key);

  @override
  Future<void> clear() async => _entries.clear();

  @override
  void bindUser(String? userId) {}
}
