import 'package:freezed_annotation/freezed_annotation.dart';

import 'storage_provider.dart';

part 'storage_account.freezed.dart';

/// A connected provider account, as the client is allowed to see it.
///
/// There is deliberately no token field. The OAuth grant lives in a Firestore
/// subcollection that `firestore.rules` denies to *everyone* — including the
/// owner — because a refresh token is a permanent key to the user's entire
/// drive and no screen needs to read one.
@freezed
abstract class StorageAccount with _$StorageAccount {
  const factory StorageAccount({
    required String id,
    required StorageProvider provider,
    @Default(ConnectorState.connected) ConnectorState state,
    @Default(ScopeLevel.read) ScopeLevel scopeLevel,

    /// Which account, for somebody with three Google logins.
    String? email,
    String? displayName,
    @Default(0) int fileCount,
    @Default(0) int bytes,
    @Default(<IndexedFolder>[]) List<IndexedFolder> indexedFolders,
    DateTime? connectedAt,
    DateTime? lastSyncedAt,

    /// What the scheduled sync last added on its own, and when. Written only
    /// when it added something, so a newer [lastSyncAddedAt] is news — the
    /// app's "Found 3 new files in Google Drive".
    @Default(0) int lastSyncAdded,
    DateTime? lastSyncAddedAt,
    ConnectorFault? fault,
  }) = _StorageAccount;

  const StorageAccount._();

  /// What screen 3F prints under the provider name.
  ///
  /// The state line wins over the file count: somebody whose Drive access was
  /// revoked needs to see that, not "10,412 FILES".
  String get statusLine => switch (state) {
    ConnectorState.revoked => 'ACCESS REVOKED',
    ConnectorState.error => 'NEEDS ATTENTION',
    ConnectorState.paused => 'PAUSED',
    ConnectorState.syncing => 'INDEXING…',
    ConnectorState.connected when fileCount == 0 => 'CONNECTED',
    ConnectorState.connected => '$_files · $_size',
  };

  String get _files {
    final n = fileCount.toString();
    // Grouped by hand: numerals are set in the metadata face and the
    // separator has to match "10,412 FILES" exactly.
    final grouped = n.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'),
      (m) => '${m[1]},',
    );
    return '$grouped FILES';
  }

  String get _size {
    const gib = 1024 * 1024 * 1024;
    if (bytes >= gib) {
      return '${(bytes / gib).toStringAsFixed(bytes < gib * 10 ? 1 : 0)} GB';
    }
    final mib = bytes / (1024 * 1024);
    return '${mib.toStringAsFixed(mib < 10 ? 1 : 0)} MB';
  }

  bool get canManage => scopeLevel == ScopeLevel.manage;
}

/// A folder the user chose on screen 3K, with the counts 3L reads back.
@freezed
abstract class IndexedFolder with _$IndexedFolder {
  const factory IndexedFolder({
    required String id,
    required String name,
    @Default('') String path,
    @Default(0) int fileCount,
    @Default(0) int bytes,
  }) = _IndexedFolder;
}

/// Why a connection stopped working, in terms the UI can act on.
@freezed
abstract class ConnectorFault with _$ConnectorFault {
  const factory ConnectorFault({
    required String code,
    required String message,
  }) = _ConnectorFault;
}

/// One row of screen 3F.
///
/// [isConfigured] is separate from "connected": a provider this build has no
/// credentials for is shown *dimmed with a reason* rather than hidden, so a
/// misconfigured release cannot look like a deliberate product decision. Same
/// rule the sign-in screen already follows for OAuth buttons.
@freezed
abstract class ConnectorOption with _$ConnectorOption {
  const factory ConnectorOption({
    required StorageProvider provider,
    required bool isConfigured,
    StorageAccount? account,
  }) = _ConnectorOption;

  const ConnectorOption._();

  bool get isConnected =>
      account != null && account!.state != ConnectorState.revoked;
}

/// Everything screen 3F renders, in one shape.
@freezed
abstract class ConnectorCatalog with _$ConnectorCatalog {
  const factory ConnectorCatalog({
    @Default(<ConnectorOption>[]) List<ConnectorOption> options,

    /// Null means unlimited. Free connects one.
    int? limit,
    @Default(0) int used,
    @Default(true) bool canConnectMore,
  }) = _ConnectorCatalog;

  const ConnectorCatalog._();

  List<StorageAccount> get accounts => [
    for (final o in options)
      if (o.account != null) o.account!,
  ];

  /// The line under the panel when the plan is the thing stopping you.
  String? get limitNote {
    if (canConnectMore || limit == null) return null;
    return limit == 1
        ? 'Your plan connects one account. Upgrade to add more.'
        : 'Your plan connects $limit accounts. Upgrade to add more.';
  }
}
