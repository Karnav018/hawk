import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';

import '../../../core/cache/cache_store.dart';
import '../domain/entities/recent_find.dart';

/// The last two questions that found something, kept on this phone.
///
/// Shown above the nav on the voice face as LAST FOUND, and reopened from
/// there as a replay — no server call, so no ask spent. Two, because the row
/// has room for two chips without scrolling and "what did I just find" is
/// rarely further back than that.
///
/// Stored through [CacheStore], so it is scoped to the signed-in user and
/// cleared on sign-out like every other cached answer.
@lazySingleton
class RecentFinds extends ChangeNotifier {
  RecentFinds(this._cache);

  final CacheStore _cache;

  static const keep = 2;
  static const _key = 'chat.recentFinds';

  List<RecentFind> _items = const [];
  bool _loaded = false;

  /// Newest first, at most [keep].
  List<RecentFind> get items => _items;

  Future<void> load() async {
    try {
      final cached = await _cache.read(_key);
      _items = [
        for (final raw in (cached?.value['items'] as List? ?? const []))
          RecentFind.fromJson(Map<String, dynamic>.from(raw as Map)),
      ].take(keep).toList();
    } on Object {
      // A broken entry is an empty row, not a crash on home.
      _items = const [];
    }
    _loaded = true;
    notifyListeners();
  }

  /// Keeps [find] as the newest, dropping an older one for the same
  /// question — asking the same thing twice is one find, updated.
  Future<void> record(RecentFind find) async {
    if (!_loaded) await load();
    final same = find.question.trim().toLowerCase();
    _items = [
      find,
      for (final f in _items)
        if (f.question.trim().toLowerCase() != same) f,
    ].take(keep).toList();
    notifyListeners();
    try {
      await _cache.write(_key, {
        'items': [for (final f in _items) f.toJson()],
      });
    } on Object {
      // Still on screen for this session; just not kept.
    }
  }
}
