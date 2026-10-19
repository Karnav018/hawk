import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/bloc/safe_emit.dart';
import '../../../../core/error/app_exception.dart';
import '../../../../core/error/error_mapper.dart';
import '../../../connectors/domain/entities/provider_folder.dart';
import '../../../connectors/domain/entities/storage_account.dart';
import '../../../connectors/domain/entities/storage_provider.dart';
import '../../../connectors/domain/repositories/connector_repository.dart';
import '../../domain/entities/account_overview.dart';
import '../../domain/repositories/account_repository.dart';

/// Everything screen 1R draws.
///
/// A hand-written state class rather than a `@freezed` one, for the same
/// reason [VaultCubit] is not `@injectable`: generating it would mean running
/// `build_runner`, and this lane shares `core/di/injector.config.dart` with
/// every other lane's port. Five fields and a `copyWith` is a cheaper price
/// than rewriting somebody else's wiring while they are mid-screen.
class VaultState {
  const VaultState({
    this.catalog,
    this.overview,
    this.isLoading = true,
    this.isRebuilding = false,
    this.error,
  });

  /// The live source list. Streamed, because connecting or losing an account
  /// happens elsewhere — on another device, or in the browser tab the OAuth
  /// round trip opened — and 1R must not need a pull-to-refresh to notice.
  final ConnectorCatalog? catalog;

  /// The account-wide counts. Fetched once; nothing on this screen changes
  /// them.
  final AccountOverview? overview;

  final bool isLoading;
  final bool isRebuilding;
  final AppException? error;

  /// Every connected source, device vault included.
  List<StorageAccount> get sources => catalog?.accounts ?? const [];

  /// This phone, if it has been made a source.
  StorageAccount? get deviceVault =>
      sources.where((a) => a.provider == StorageProvider.internal).firstOrNull;

  /// The headline number on the white card: every memory in the vault.
  ///
  /// **The account's own total, not a sum of the source rows.** It used to be
  /// the rows added up, on the reasoning that a card should agree with the
  /// list under it. But a source's `fileCount` only counts what was indexed
  /// *through* that source — the phone vault's counter starts when it is
  /// connected, so files captured before that were in the vault and in no
  /// row. The card said "0 files" over chips reading "2 documents, 3 images",
  /// while home said "5 memories ready". The breakdown chips come from the
  /// same summary, so this is the number they add up to.
  ///
  /// The row sum stays as the fallback for the moment before the summary
  /// arrives, or if it fails — a real, if partial, number rather than none.
  int get indexedFiles =>
      overview?.memories ??
      sources.fold(0, (total, account) => total + account.fileCount);

  int get indexedBytes =>
      sources.fold(0, (total, account) => total + account.bytes);

  /// Whether anything could be rebuilt. The device vault is excluded: its
  /// files are indexed one at a time as they are picked, so there is no folder
  /// scope to re-run and the server refuses the call for it.
  bool get canRebuild => sources.any(
    (a) =>
        a.provider != StorageProvider.internal && a.indexedFolders.isNotEmpty,
  );

  VaultState copyWith({
    ConnectorCatalog? catalog,
    AccountOverview? overview,
    bool? isLoading,
    bool? isRebuilding,
    AppException? error,
    bool clearError = false,
  }) => VaultState(
    catalog: catalog ?? this.catalog,
    overview: overview ?? this.overview,
    isLoading: isLoading ?? this.isLoading,
    isRebuilding: isRebuilding ?? this.isRebuilding,
    error: clearError ? null : (error ?? this.error),
  );
}

/// Screen 1R's state.
///
/// It joins two sources that nobody else joins: the connector catalogue, which
/// knows what is connected and how much of it is indexed, and the account
/// summary, which knows what the index *became*. 1R is the only screen that
/// wants both, which is why the join is here and not in a repository.
///
/// **Not `@injectable`.** Every other cubit in the app is, and this one would
/// be too if registering it did not require regenerating
/// `injector.config.dart` — a file that belongs to no feature and that three
/// lanes are porting into at once. Screen 1R constructs it from `getIt` at its
/// `BlocProvider`, which is the same lookup the generated code would do.
/// Annotate it and delete the manual construction once the port is finished.
class VaultCubit extends Cubit<VaultState> with SafeEmit<VaultState> {
  VaultCubit(this._connectors, this._accounts) : super(const VaultState());

  final ConnectorRepository _connectors;
  final AccountRepository _accounts;

  StreamSubscription<ConnectorCatalog>? _catalog;

  Future<void> load() async {
    _catalog ??= _connectors.watchCatalog().listen(
      (catalog) => emit(
        state.copyWith(catalog: catalog, isLoading: false, clearError: true),
      ),
      // A failed catalogue read leaves the last one on screen. The numbers
      // are a few seconds stale at worst, and a vault that empties itself
      // because a stream hiccuped would look like data loss.
      onError: (Object error, StackTrace stackTrace) => emit(
        state.copyWith(
          isLoading: false,
          error: ErrorMapper.map(error, stackTrace),
        ),
      ),
    );

    // The last summary first: the headline and the chips draw on open,
    // and the fetch below corrects them if anything changed.
    try {
      final cached = await _accounts.cachedOverview();
      if (cached != null && state.overview == null) {
        emit(state.copyWith(overview: cached));
      }
    } on Object {
      // No head start.
    }

    try {
      // Awaited into a local first. `emit(state.copyWith(overview: await
      // …))` reads `state` *before* the await, so the catalogue arriving
      // meanwhile was written back over with the stale state — catalog
      // null, still loading. The screen then sat on its grey placeholder
      // with a headline of 0, forever: the exact screenshot this fixes.
      final overview = await _accounts.overview();
      emit(state.copyWith(overview: overview));
    } catch (_) {
      // Swallowed on purpose. The summary only feeds the breakdown chips on
      // the white card; the card's headline, every source row and both
      // buttons come from the catalogue. Failing the whole screen because an
      // aggregation query timed out would hide the part that works.
    }
  }

  /// Re-runs the index over the folders the user already chose.
  ///
  /// There is no `rebuild_index` callable — re-submitting the same folder
  /// scope is what the backend treats as a rebuild, and it is the same call
  /// screen 3K makes. So this is not a workaround: it is the one operation
  /// that means "read all of this again".
  ///
  /// Nothing is navigated to afterwards. The progress screen lives under
  /// `/welcome`, which the router's guard bars to a signed-in user, so the
  /// only honest feedback is the one already on screen — each account flips to
  /// `syncing` and its row starts saying INDEXING…, live, through the
  /// catalogue stream.
  Future<void> rebuild() async {
    if (state.isRebuilding) return;
    emit(state.copyWith(isRebuilding: true, clearError: true));

    try {
      for (final account in state.sources) {
        if (account.provider == StorageProvider.internal) continue;
        if (account.indexedFolders.isEmpty) continue;

        await _connectors.setIndexedFolders(account.id, [
          for (final folder in account.indexedFolders)
            ProviderFolder(
              id: folder.id,
              name: folder.name,
              path: folder.path,
              fileCount: folder.fileCount,
              bytes: folder.bytes,
            ),
        ]);
      }
      emit(state.copyWith(isRebuilding: false));
    } catch (error, stackTrace) {
      emit(
        state.copyWith(
          isRebuilding: false,
          error: ErrorMapper.map(error, stackTrace),
        ),
      );
    }
  }

  void dismissError() => emit(state.copyWith(clearError: true));

  @override
  Future<void> close() {
    _catalog?.cancel();
    return super.close();
  }
}
