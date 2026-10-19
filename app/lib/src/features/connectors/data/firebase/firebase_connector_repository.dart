import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:injectable/injectable.dart';

import '../../../../core/cache/cache_policy.dart';
import '../../../../core/cache/cache_store.dart';
import '../../../../core/error/app_exception.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/index_job.dart';
import '../../domain/entities/provider_folder.dart';
import '../../domain/entities/storage_account.dart';
import '../../domain/entities/storage_provider.dart';
import '../../domain/repositories/connector_repository.dart';
import '../oauth/oauth_browser.dart';

/// [ConnectorRepository] over Cloud Functions and Firestore.
///
/// The split is deliberate and follows one rule: **reads stream from
/// Firestore, changes go through a callable.** Rendering an account list is
/// something rules can safely authorise; connecting one is not, because the
/// free tier's single-account limit has to be enforced somewhere a client
/// cannot reach.
///
/// The provider catalogue is the exception — which providers this build has
/// credentials for is server knowledge with no Firestore document behind it,
/// so it is fetched once and merged into the live account stream.
@LazySingleton(as: ConnectorRepository)
class FirebaseConnectorRepository implements ConnectorRepository {
  FirebaseConnectorRepository(
    this._firestore,
    this._functions,
    this._auth,
    this._browser,
    this._cache,
    this._logger,
  );

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  final fb.FirebaseAuth _auth;
  final OAuthBrowser _browser;
  final CacheStore _cache;
  final AppLogger _logger;

  /// The scheme the OS hands back to this app.
  ///
  /// Not what is registered with the providers — they redirect to an https
  /// endpoint (`connector_callback.py`), because Google rejects a custom
  /// scheme on any client requesting restricted scopes. That endpoint 302s
  /// here, so from the browser session's point of view this is still the
  /// callback it is waiting for, and the manifest and Info.plist entries are
  /// unchanged.
  static const _callbackScheme = 'com.knowra.knowra';

  String get _userId {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw const AppException.unauthorized();
    return uid;
  }

  // ------------------------------------------------------------- catalogue

  @override
  Stream<ConnectorCatalog> watchCatalog() {
    // Which providers this build has credentials for changes only on deploy,
    // so it is fetched once per subscription. Held as a Future rather than a
    // second stream: awaiting the same Future repeatedly returns the resolved
    // value without re-calling, which is exactly the caching wanted here and
    // saves pulling in a reactive-combinator dependency for one merge.
    //
    // The disk cache underneath it is what makes screen 3F draw on the first
    // frame: the account rows come from Firestore's own offline copy, and
    // without a cached catalogue they would sit behind a callable round trip
    // that has nothing to do with them.
    final catalogue = _cachedCatalogue();

    return _firestore
        .collection('storageAccounts')
        .where('userId', isEqualTo: _userId)
        .snapshots()
        .asyncMap((snapshot) async {
          final meta = await catalogue;
          final accounts = [
            for (final doc in snapshot.docs) _account(doc.id, doc.data()),
          ];
          final live = accounts
              .where((a) => a.state != ConnectorState.revoked)
              .length;

          return ConnectorCatalog(
            options: [
              for (final p in meta.providers)
                ConnectorOption(
                  provider: p.provider,
                  isConfigured: p.configured,
                  account: accounts
                      .where((a) => a.provider == p.provider)
                      .firstOrNull,
                ),
            ],
            limit: meta.limit,
            used: live,
            canConnectMore: meta.limit == null || live < meta.limit!,
          );
        })
        .handleError(_rethrow);
  }

  static const _catalogueKey = 'connectors.catalogue';

  Future<
    ({
      List<({StorageProvider provider, bool configured})> providers,
      int? limit,
    })
  >
  _cachedCatalogue() async {
    final cached = await _cache.read(_catalogueKey);
    if (cached != null && cached.isFresh(CachePolicy.providerCatalogue)) {
      return _decodeCatalogue(cached.value);
    }

    try {
      final data = await _call('list_connectors');
      await _cache.write(_catalogueKey, {
        'providers': data['providers'],
        'limit': data['limit'],
      });
      return _decodeCatalogue(data);
    } on AppException {
      // Stale beats empty. A screen that lists the providers with slightly
      // old plan limits is usable offline; one that throws is not — and the
      // limit is re-checked server-side the moment anyone taps Connect, so a
      // stale number here cannot actually let someone past their plan.
      if (cached != null) return _decodeCatalogue(cached.value);
      rethrow;
    }
  }

  ({List<({StorageProvider provider, bool configured})> providers, int? limit})
  _decodeCatalogue(Map<String, dynamic> data) {
    return (
      providers: [
        for (final raw in (data['providers'] as List? ?? const []))
          (
            provider: StorageProvider.parse(raw['id'] as String?),
            configured: raw['configured'] as bool? ?? false,
          ),
      ],
      limit: (data['limit'] as num?)?.toInt(),
    );
  }

  // ------------------------------------------------------------ connecting

  @override
  Future<ConnectResult> connect(
    StorageProvider provider, {
    ScopeLevel scope = ScopeLevel.read,
  }) async {
    final begun = await _call('begin_connection', {
      'provider': provider.wireName,
      'scopeLevel': scope.wireName,
    });

    final params = await _browser.authorize(
      authorizationUrl: begun['authorizationUrl'] as String,
      callbackScheme: _callbackScheme,
    );

    // The state check is repeated server-side against the stored challenge —
    // this one only saves a round trip on an obviously mismatched redirect.
    final code = params['code'];
    if (code == null || params['state'] != begun['state']) {
      throw const AppException.badRequest(
        message: 'That connection could not be verified. Try again.',
      );
    }

    final done = await _call('complete_connection', {
      'challengeId': begun['challengeId'],
      'code': code,
      'state': params['state'],
    });

    final account = done['account'] as Map<Object?, Object?>;
    return (
      account: _account(
        account['id'] as String,
        account.map((k, v) => MapEntry(k as String, v)),
      ),
      reconnected: done['reconnected'] as bool? ?? false,
    );
  }

  @override
  Future<StorageAccount> setScopeLevel(
    String accountId,
    ScopeLevel scope,
  ) async {
    final result = await _call('set_scope_level', {
      'accountId': accountId,
      'scopeLevel': scope.wireName,
    });

    // Widening a grant needs the user, so the server hands back another
    // authorization URL instead of a changed account.
    if (result['consentRequired'] == true) {
      final params = await _browser.authorize(
        authorizationUrl: result['authorizationUrl'] as String,
        callbackScheme: _callbackScheme,
      );
      final code = params['code'];
      if (code == null || params['state'] != result['state']) {
        throw const AppException.badRequest(
          message: 'That permission change could not be verified.',
        );
      }
      final done = await _call('complete_connection', {
        'challengeId': result['challengeId'],
        'code': code,
        'state': params['state'],
      });
      final account = done['account'] as Map<Object?, Object?>;
      return _account(
        account['id'] as String,
        account.map((k, v) => MapEntry(k as String, v)),
      );
    }

    final doc = await _firestore
        .collection('storageAccounts')
        .doc(accountId)
        .get();
    return _account(accountId, doc.data() ?? const {});
  }

  // --------------------------------------------------------------- folders

  String _foldersKey(String accountId) => 'connectors.folders.$accountId';

  @override
  Future<({List<ProviderFolder> folders, Set<String> selected})> listFolders(
    String accountId, {
    bool forceRefresh = false,
  }) async {
    final key = _foldersKey(accountId);

    // The most expensive call in the app by a wide margin: listing folders
    // means one provider request per folder just to count what is inside it,
    // and Drive is not fast. Screen 3K is also the easiest place in the flow
    // to re-enter — tap into 3L, come back, tap Back again — so without this
    // an indecisive user re-walks their entire Drive three times.
    if (!forceRefresh) {
      final cached = await _cache.read(key);
      if (cached != null && cached.isFresh(CachePolicy.providerFolders)) {
        return _decodeFolders(cached.value);
      }
    }

    final data = await _call('list_provider_folders', {'accountId': accountId});
    await _cache.write(key, {
      'folders': data['folders'],
      'selected': data['selected'],
    });
    return _decodeFolders(data);
  }

  ({List<ProviderFolder> folders, Set<String> selected}) _decodeFolders(
    Map<String, dynamic> data,
  ) {
    return (
      folders: [
        for (final raw in (data['folders'] as List? ?? const []))
          ProviderFolder(
            id: raw['id'] as String,
            name: raw['name'] as String? ?? '',
            path: raw['path'] as String? ?? '',
            fileCount: (raw['fileCount'] as num?)?.toInt() ?? 0,
            bytes: (raw['bytes'] as num?)?.toInt() ?? 0,
          ),
      ],
      selected: {
        for (final id in (data['selected'] as List? ?? const [])) id as String,
      },
    );
  }

  @override
  Future<String> setIndexedFolders(
    String accountId,
    List<ProviderFolder> folders,
  ) async {
    final data = await _call('set_indexed_folders', {
      'accountId': accountId,
      'folders': [
        for (final f in folders)
          {
            'id': f.id,
            'name': f.name,
            'path': f.path,
            'fileCount': f.fileCount,
            'bytes': f.bytes,
          },
      ],
    });
    // The cached listing carries the previous selection, which this call just
    // replaced. Evicting is cheaper and less error-prone than patching the
    // cached copy to match.
    await _cache.evict(_foldersKey(accountId));
    return data['jobId'] as String;
  }

  // ----------------------------------------------------------------- files

  @override
  Future<ProviderFilePage> listProviderFiles(
    String accountId, {
    String? pageToken,
  }) async {
    final data = await _call('list_provider_files', {
      'accountId': accountId,
      'pageToken': ?pageToken,
    });

    return (
      files: [
        for (final raw in (data['files'] as List? ?? const []))
          (
            id: raw['id'] as String,
            name: raw['name'] as String? ?? '',
            path: raw['path'] as String? ?? '',
            mimeType: raw['mimeType'] as String?,
            bytes: (raw['bytes'] as num?)?.toInt() ?? 0,
            indexed: raw['indexed'] as bool? ?? false,
          ),
      ],
      nextPageToken: data['nextPageToken'] as String?,
      indexedCount: (data['indexedCount'] as num?)?.toInt() ?? 0,
      totalCount: (data['totalCount'] as num?)?.toInt() ?? 0,
    );
  }

  /// Deliberately uncached, unlike [listFolders].
  ///
  /// The folder listing is cached because it is enormous and changes rarely.
  /// This one is the opposite: the user changes it themselves, one row at a
  /// time, and a cached page would show the file they just indexed as
  /// unindexed. The listing is also cheap — the provider returns a page of
  /// file metadata in one request, with none of the per-folder counting that
  /// makes `list_provider_folders` expensive.
  @override
  Future<void> setFileIndexed({
    required String accountId,
    required String fileId,
    required bool indexed,
  }) async {
    await _call('set_file_indexed', {
      'accountId': accountId,
      'fileId': fileId,
      'indexed': indexed,
    });

    // The cached *folder* listing carries a per-folder indexed count that
    // this call has just invalidated. Evicting is cheaper than patching a
    // cached copy to match, and the same reasoning as `setIndexedFolders`.
    await _cache.evict(_foldersKey(accountId));
  }

  @override
  Stream<IndexJob> watchIndexJob(String jobId) => _firestore
      .collection('indexJobs')
      .doc(jobId)
      .snapshots()
      .where((doc) => doc.exists)
      .map((doc) => _job(doc.id, doc.data() ?? const {}))
      .handleError(_rethrow);

  // ------------------------------------------------------------ lifecycle

  @override
  Future<void> disconnect(
    String accountId, {
    bool deleteMemories = false,
  }) async {
    await _call('disconnect_account', {
      'accountId': accountId,
      'deleteMemories': deleteMemories,
    });
    await _cache.evict(_foldersKey(accountId));
  }

  @override
  Future<void> completeSetup() => _call('complete_storage_setup');

  @override
  Future<StorageAccount> connectDeviceVault({String? deviceName}) async {
    final result = await _call('connect_device_vault', {
      'deviceName': ?deviceName,
    });
    final account = result['account'];
    if (account is! Map) {
      throw const AppException.unknown(
        message: 'The phone vault could not be set up.',
      );
    }
    final data = account.map((k, v) => MapEntry(k.toString(), v));
    return _account(data['id'] as String, data);
  }

  // ---------------------------------------------------------------- plumbing

  Future<Map<String, dynamic>> _call(
    String name, [
    Map<String, Object?>? body,
  ]) async {
    try {
      final result = await _functions.httpsCallable(name).call<Object?>(body);
      final data = result.data;
      if (data is Map) {
        return data.map((k, v) => MapEntry(k.toString(), v));
      }
      return const {};
    } on FirebaseFunctionsException catch (error, stackTrace) {
      _logger.warning(
        'connector call failed',
        name: 'connectors',
        data: {'function': name, 'code': error.code},
      );
      throw _mapFunctionError(error, stackTrace);
    }
  }

  /// Callable error codes carry meaning the UI acts on, so they are mapped
  /// individually rather than collapsed into "something went wrong".
  AppException _mapFunctionError(
    FirebaseFunctionsException error,
    StackTrace stackTrace,
  ) => switch (error.code) {
    'unauthenticated' => const AppException.unauthorized(),
    // The plan limit. Surfaced as a bad request so the screen can show the
    // upgrade note rather than a retry button.
    'resource-exhausted' => AppException.badRequest(
      message: error.message ?? 'That is as many accounts as your plan allows.',
    ),
    'permission-denied' => AppException.badRequest(
      message: error.message ?? 'Access was refused by the provider.',
    ),
    'failed-precondition' => AppException.badRequest(
      message: error.message ?? 'That provider is not available right now.',
    ),
    'not-found' => const AppException.notFound(message: 'No such connection.'),
    'unavailable' => const AppException.network(
      message: 'The provider is not responding. Try again shortly.',
    ),
    'deadline-exceeded' => const AppException.timeout(),
    _ => AppException.unknown(cause: error, stackTrace: stackTrace),
  };

  Never _rethrow(Object error, StackTrace stackTrace) {
    if (error is AppException) throw error;
    if (error is FirebaseException && error.code == 'permission-denied') {
      throw const AppException.unauthorized();
    }
    throw AppException.unknown(cause: error, stackTrace: stackTrace);
  }

  StorageAccount _account(String id, Map<String, dynamic> data) =>
      StorageAccount(
        id: id,
        provider: StorageProvider.parse(data['provider'] as String?),
        state: ConnectorState.parse(data['state'] as String?),
        scopeLevel: ScopeLevel.parse(data['scopeLevel'] as String?),
        email: data['email'] as String?,
        displayName: data['displayName'] as String?,
        fileCount: (data['fileCount'] as num?)?.toInt() ?? 0,
        bytes: (data['bytes'] as num?)?.toInt() ?? 0,
        indexedFolders: [
          for (final raw in (data['indexedFolders'] as List? ?? const []))
            IndexedFolder(
              id: raw['id'] as String,
              name: raw['name'] as String? ?? '',
              path: raw['path'] as String? ?? '',
              fileCount: (raw['fileCount'] as num?)?.toInt() ?? 0,
              bytes: (raw['bytes'] as num?)?.toInt() ?? 0,
            ),
        ],
        connectedAt: _moment(data['connectedAt']),
        lastSyncedAt: _moment(data['lastSyncedAt']),
        lastSyncAdded: (data['lastSyncAdded'] as num?)?.toInt() ?? 0,
        lastSyncAddedAt: _moment(data['lastSyncAddedAt']),
        fault: data['error'] is Map
            ? ConnectorFault(
                code: (data['error'] as Map)['code'] as String? ?? 'unknown',
                message: (data['error'] as Map)['message'] as String? ?? '',
              )
            : null,
      );

  IndexJob _job(String id, Map<String, dynamic> data) {
    final totals = data['totals'] as Map? ?? const {};
    final progress = data['progress'] as Map? ?? const {};
    final byKind = data['byKind'] as Map? ?? const {};
    final total = (totals['files'] as num?)?.toInt() ?? 0;
    final processed = (progress['processed'] as num?)?.toInt() ?? 0;

    return IndexJob(
      id: id,
      state: IndexJobState.parse(data['state'] as String?),
      totalFiles: total,
      totalBytes: (totals['bytes'] as num?)?.toInt() ?? 0,
      processed: processed,
      failed: (progress['failed'] as num?)?.toInt() ?? 0,
      stage: data['stage'] as String?,
      byKind: [
        for (final entry in byKind.entries)
          IndexKindProgress(
            kind: entry.key as String,
            done: (entry.value as num?)?.toInt() ?? 0,
            // The worker reports how many of each kind it has *found*, not a
            // per-kind target — it cannot know the split until the walk is
            // over. Showing found-as-total is honest while enumerating and
            // exact once complete.
            total: (entry.value as num?)?.toInt() ?? 0,
          ),
      ]..sort((a, b) => b.total.compareTo(a.total)),
      startedAt: _moment(data['startedAt']),
      finishedAt: _moment(data['finishedAt']),
      error: data['error'] as String?,
    );
  }

  DateTime? _moment(Object? value) => switch (value) {
    Timestamp() => value.toDate(),
    DateTime() => value,
    String() => DateTime.tryParse(value),
    _ => null,
  };
}
