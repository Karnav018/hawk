import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/router/app_router.dart';
import '../../../core/di/injector.dart';
import '../../../core/feedback/snack.dart';
import '../../../core/feedback/snack_controller.dart';
import '../../memory/presentation/pages/library_page.dart';
import '../domain/entities/storage_account.dart';
import '../domain/repositories/connector_repository.dart';

/// What a sync added on its own, ready to say.
typedef SyncNewsItem = ({int added, DateTime at, String message});

/// The assistant snack (2D) — "only for things Hawk did on its own".
///
/// The one thing Hawk does unasked is the scheduled sync: every six hours
/// it looks in the Drive folders the user chose and indexes what is new.
/// The sync records what it added and when (`lastSyncAdded`,
/// `lastSyncAddedAt`); this watches the accounts and, when that time is newer
/// than the last one it announced, says so once — "Found 3 new files in
/// Google Drive" — and opens the Library if tapped.
///
/// **Once, and never the past.** The last announced time is kept on the
/// phone, so the news is not repeated on every launch. On the very first
/// launch there is nothing to compare with, and the right answer is to note
/// the time and say nothing: a sync from last week is not news to somebody
/// who has just installed the app.
@lazySingleton
class SyncNews {
  SyncNews(this._connectors, this._snacks, this._router);

  final ConnectorRepository _connectors;
  final SnackController _snacks;
  final AppRouter _router;

  StreamSubscription<Object?>? _subscription;

  static const _seenKey = 'sync_news.seen';

  void start() {
    if (_subscription != null) return;
    _subscription = _connectors.watchCatalog().listen(
      (catalog) => unawaited(_consider(catalog.accounts)),
      // No catalogue, no news. Nothing here is worth an error of its own.
      onError: (Object _) {},
    );
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  Future<void> _consider(List<StorageAccount> accounts) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getInt(_seenKey);
    if (stored == null) {
      await prefs.setInt(_seenKey, DateTime.now().millisecondsSinceEpoch);
      return;
    }
    final news = newsSince(
      accounts,
      DateTime.fromMillisecondsSinceEpoch(stored),
    );
    if (news == null) return;
    await prefs.setInt(_seenKey, news.at.millisecondsSinceEpoch);
    _snacks.show(
      Snack.assistant(
        message: news.message,
        onOpen: () => _router.config.go(LibraryPage.routePath),
      ),
    );
  }

  /// What arrived after [seen], summed across accounts, or null.
  ///
  /// Summed because two Drives syncing in the same six hours are one piece
  /// of news about the Library, not two islands queued behind each other.
  @visibleForTesting
  static SyncNewsItem? newsSince(List<StorageAccount> accounts, DateTime seen) {
    final fresh = [
      for (final a in accounts)
        if (a.lastSyncAdded > 0 && (a.lastSyncAddedAt?.isAfter(seen) ?? false))
          a,
    ];
    if (fresh.isEmpty) return null;

    final added = fresh.fold(0, (sum, a) => sum + a.lastSyncAdded);
    final at = fresh
        .map((a) => a.lastSyncAddedAt!)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    final providers = {for (final a in fresh) a.provider.label};
    final where = providers.length == 1 ? providers.single : 'your storage';
    return (
      added: added,
      at: at,
      message: 'Found $added new file${added == 1 ? '' : 's'} in $where',
    );
  }
}

/// Keeps [SyncNews] listening for as long as the signed-in app is up.
///
/// A widget rather than a call at startup because the catalogue is per
/// user: this sits inside the tab shell, which only exists while somebody
/// is signed in, so signing out stops the listening with it.
class SyncNewsScope extends StatefulWidget {
  const SyncNewsScope({required this.child, super.key});

  final Widget child;

  @override
  State<SyncNewsScope> createState() => _SyncNewsScopeState();
}

class _SyncNewsScopeState extends State<SyncNewsScope> {
  /// Null where nothing registered it — a widget test that builds the shell
  /// around one screen has no connector catalogue to watch, and a scope
  /// that threw there would make every such test register one.
  late final SyncNews? _news = getIt.isRegistered<SyncNews>()
      ? getIt<SyncNews>()
      : null;

  @override
  void initState() {
    super.initState();
    _news?.start();
  }

  @override
  void dispose() {
    final news = _news;
    if (news != null) unawaited(news.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
