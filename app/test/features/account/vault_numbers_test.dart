import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/features/account/domain/entities/account_overview.dart';
import 'package:knowra/src/features/account/domain/repositories/account_repository.dart';
import 'package:knowra/src/features/account/presentation/bloc/vault_cubit.dart';
import 'package:knowra/src/features/account/presentation/pages/vault_page.dart';
import 'package:knowra/src/features/account/presentation/widgets/profile_pieces.dart';
import 'package:knowra/src/features/connectors/domain/entities/storage_account.dart';
import 'package:knowra/src/features/connectors/domain/entities/storage_provider.dart';
import 'package:knowra/src/features/connectors/domain/repositories/connector_repository.dart';

/// Screen 1R prints four numbers and every one of them is derived rather than
/// fetched. These are the derivations.
void main() {
  StorageAccount account({
    required StorageProvider provider,
    int files = 0,
    int bytes = 0,
    ConnectorState state = ConnectorState.connected,
    List<IndexedFolder> folders = const [],
  }) => StorageAccount(
    id: provider.wireName,
    provider: provider,
    state: state,
    fileCount: files,
    bytes: bytes,
    indexedFolders: folders,
  );

  VaultState withSources(List<StorageAccount> accounts) => VaultState(
    catalog: ConnectorCatalog(
      options: [
        for (final a in accounts)
          ConnectorOption(provider: a.provider, isConfigured: true, account: a),
      ],
    ),
    isLoading: false,
  );

  group('the headline count', () {
    test('is the account\'s total — what home and the chips count', () {
      // The QA account on 26 Sep: five files captured from the phone before
      // any source was connected. The row sum said 0; the vault holds 5.
      final state = VaultState(
        catalog: const ConnectorCatalog(options: []),
        overview: const AccountOverview(
          memories: 5,
          indexed: 5,
          byKind: {'documents': 2, 'images': 3},
        ),
        isLoading: false,
      );
      expect(state.indexedFiles, 5);
      expect(chipsFor(state.overview), ['2 documents', '3 images']);
    });

    test('falls back to the rows while the total is loading', () {
      final state = withSources([
        account(provider: StorageProvider.googleDrive, files: 842),
        account(
          provider: StorageProvider.internal,
          files: 674,
          bytes: 9772265046,
        ),
      ]);

      expect(state.indexedFiles, 1516);
      expect(groupedCount(state.indexedFiles), '1,516');
    });

    test('is zero, not an error, before anything is connected', () {
      expect(const VaultState().indexedFiles, 0);
      expect(const VaultState().sources, isEmpty);
    });
  });

  test('the sources that arrive while the total loads are kept', () async {
    // The bug in the screenshot: the catalogue landed while the summary was
    // still in flight, and `copyWith(overview: await …)` wrote the state
    // from before it back over the top — placeholder box, headline 0.
    final catalog = StreamController<ConnectorCatalog>();
    final summary = Completer<AccountOverview>();
    final cubit = VaultCubit(
      _Connectors(catalog.stream),
      _Accounts(summary.future),
    );
    addTearDown(cubit.close);

    unawaited(cubit.load());
    catalog.add(
      withSources([
        account(provider: StorageProvider.internal, files: 3),
      ]).catalog!,
    );
    await Future<void>.delayed(Duration.zero);
    summary.complete(
      const AccountOverview(memories: 5, byKind: {'documents': 2, 'images': 3}),
    );
    await Future<void>.delayed(Duration.zero);

    expect(cubit.state.isLoading, isFalse);
    expect(cubit.state.sources, hasLength(1));
    expect(cubit.state.indexedFiles, 5);
  });

  group('rebuilding', () {
    test('is offered only where there is a folder scope to re-run', () {
      final nothingChosen = withSources([
        account(provider: StorageProvider.googleDrive, files: 842),
      ]);
      expect(nothingChosen.canRebuild, isFalse);

      final chosen = withSources([
        account(
          provider: StorageProvider.googleDrive,
          files: 842,
          folders: const [IndexedFolder(id: 'f1', name: 'Contracts')],
        ),
      ]);
      expect(chosen.canRebuild, isTrue);
    });

    test('is never offered for the phone vault alone', () {
      // Its files are indexed one at a time as they are picked, so there is
      // no scope to re-run — and the server refuses the call for a device
      // account. A button that always failed would be worse than a dead one.
      final deviceOnly = withSources([
        account(
          provider: StorageProvider.internal,
          files: 674,
          folders: const [IndexedFolder(id: 'f1', name: 'Picked')],
        ),
      ]);
      expect(deviceOnly.canRebuild, isFalse);
    });
  });

  test('the device vault is found by provider, not by position', () {
    final state = withSources([
      account(provider: StorageProvider.googleDrive, files: 842),
      account(provider: StorageProvider.internal, files: 674),
    ]);
    expect(state.deviceVault?.provider, StorageProvider.internal);
    expect(const VaultState().deviceVault, isNull);
  });

  group('the breakdown chips', () {
    test('print the kinds the design names, in its order', () {
      const overview = AccountOverview(
        memories: 1516,
        byKind: {'images': 1204, 'documents': 248, 'recordings': 64},
      );

      expect(chipsFor(overview), [
        '248 documents',
        '64 recordings',
        '1,204 images',
      ]);
    });

    test('a kind with nothing in it gets no chip', () {
      const overview = AccountOverview(
        memories: 248,
        byKind: {'documents': 248, 'recordings': 0, 'images': 0},
      );

      expect(chipsFor(overview), ['248 documents']);
    });

    test('dormant memories are named beside the kinds', () {
      const overview = AccountOverview(
        memories: 12,
        dormant: 4,
        byKind: {'documents': 12},
      );
      expect(chipsFor(overview), ['12 documents', '4 dormant']);
    });

    test('an older server falls back to the states, not to nothing', () {
      // `counts.byKind` postdates the screen. A deploy skew must leave the
      // card saying something true rather than leaving it blank.
      const overview = AccountOverview(memories: 40, indexed: 38, dormant: 2);

      expect(chipsFor(overview), ['40 memories', '38 searchable', '2 dormant']);
    });
  });
}

class _Connectors extends Fake implements ConnectorRepository {
  _Connectors(this.catalog);
  final Stream<ConnectorCatalog> catalog;

  @override
  Stream<ConnectorCatalog> watchCatalog() => catalog;
}

class _Accounts extends Fake implements AccountRepository {
  _Accounts(this.summary);
  final Future<AccountOverview> summary;

  @override
  Future<AccountOverview> overview() => summary;
}
