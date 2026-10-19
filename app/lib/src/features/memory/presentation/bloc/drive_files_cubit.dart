import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:injectable/injectable.dart';

import '../../../../core/bloc/safe_emit.dart';
import '../../../../core/error/app_exception.dart';
import '../../../../core/error/error_mapper.dart';
import '../../../connectors/domain/entities/storage_account.dart';
import '../../../connectors/domain/entities/storage_provider.dart';
import '../../../connectors/domain/repositories/connector_repository.dart';

part 'drive_files_cubit.freezed.dart';

@freezed
abstract class DriveFilesState with _$DriveFilesState {
  const factory DriveFilesState({
    /// The connected Drive account, or null if there is not one.
    StorageAccount? account,
    @Default(<ProviderFile>[]) List<ProviderFile> files,

    /// The two numbers in the header, for the *whole* account — not for the
    /// page that has been loaded. See [ProviderFilePage].
    @Default(0) int indexedCount,
    @Default(0) int totalCount,
    @Default(true) bool isLoading,
    @Default(false) bool isAppending,

    /// Opaque provider cursor. Non-null means there is another page.
    String? nextPageToken,

    /// File ids whose index state is being changed right now.
    ///
    /// Per file rather than a single flag, because the whole point of this
    /// screen is tapping several rows in a row — a global "busy" would lock
    /// the list while one 3 MB spreadsheet was being queued.
    @Default(<String>{}) Set<String> pending,

    /// Files taken out of the index this session, one at a time — what the
    /// Drive tab's "Removed from your index" listens to.
    @Default(0) int unindexed,
    AppException? exception,
  }) = _DriveFilesState;

  const DriveFilesState._();

  /// Connected *and* usable. A revoked account still has a row in Firestore
  /// and an index built from files we can no longer reach, which is a state
  /// the screen has to explain rather than hide.
  bool get isConnected => account != null && account!.state.isHealthy;

  bool get hasMore => nextPageToken != null;

  /// `842 OF 10,412 INDEXED`, in the design's own grouping.
  String get countLine =>
      '${_grouped(indexedCount)} OF ${_grouped(totalCount)} INDEXED';

  /// `CONNECTED · SYNCED 21:04`.
  ///
  /// The sync time rather than the file count, because the count is already
  /// printed under the list — repeating it here would spend the account
  /// card's one line of metadata saying the same thing twice.
  String get accountLine {
    final synced = account?.lastSyncedAt?.toLocal();
    final state = switch (account?.state) {
      ConnectorState.syncing => 'INDEXING',
      ConnectorState.paused => 'PAUSED',
      ConnectorState.revoked => 'ACCESS REVOKED',
      ConnectorState.error => 'NEEDS ATTENTION',
      _ => 'CONNECTED',
    };
    if (synced == null) return state;
    final h = synced.hour.toString().padLeft(2, '0');
    final m = synced.minute.toString().padLeft(2, '0');
    return '$state · SYNCED $h:$m';
  }

  static String _grouped(int value) => value.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (m) => '${m[1]},',
  );
}

/// Screen 1L — the Library's Drive tab.
///
/// **Files, not folders.** Onboarding asks the bulk question once on 3K
/// ("index all of Contracts"); this is the retail one, asked forever
/// afterwards, one row at a time. They are different enough to be different
/// calls: folders are cached hard because counting them is the most expensive
/// request in the app, and files are not cached at all because the user is
/// changing them as they look at them.
///
/// The account comes from the same live catalogue screen 1G reads, rather
/// than from a second fetch. There is one answer to "is Drive connected" and
/// this is not the place to invent a second.
@injectable
class DriveFilesCubit extends Cubit<DriveFilesState>
    with SafeEmit<DriveFilesState> {
  DriveFilesCubit(this._connectors) : super(const DriveFilesState()) {
    _subscription = _connectors.watchCatalog().listen(
      _onCatalog,
      onError: (Object error, StackTrace stackTrace) => emit(
        state.copyWith(
          isLoading: false,
          exception: ErrorMapper.map(error, stackTrace),
        ),
      ),
    );
  }

  final ConnectorRepository _connectors;
  late final StreamSubscription<ConnectorCatalog> _subscription;

  /// Which account the loaded page belongs to.
  ///
  /// Guards the case that makes a listing lie: reconnecting under a different
  /// Google login leaves the previous account's rows on screen under the new
  /// account's name. The id changing is what triggers a reload.
  String? _loadedFor;

  void _onCatalog(ConnectorCatalog catalog) {
    final account = catalog.options
        .where((o) => o.provider == StorageProvider.googleDrive)
        .map((o) => o.account)
        .firstOrNull;

    if (account == null) {
      // Disconnected, or never connected. The rows are cleared rather than
      // left behind: a list of files from an account that is gone is the
      // most confident-looking wrong answer this screen can give.
      _loadedFor = null;
      emit(
        state.copyWith(
          account: null,
          isLoading: false,
          files: const [],
          indexedCount: 0,
          totalCount: 0,
          nextPageToken: null,
        ),
      );
      return;
    }

    emit(state.copyWith(account: account));

    if (account.id != _loadedFor) {
      _loadedFor = account.id;
      unawaited(refresh());
    }
  }

  Future<void> refresh() async {
    final accountId = state.account?.id;
    if (accountId == null) return;

    emit(state.copyWith(isLoading: true, exception: null));
    try {
      final page = await _connectors.listProviderFiles(accountId);
      emit(
        state.copyWith(
          isLoading: false,
          files: page.files,
          indexedCount: page.indexedCount,
          totalCount: page.totalCount,
          nextPageToken: page.nextPageToken,
        ),
      );
    } catch (error, stackTrace) {
      emit(
        state.copyWith(
          isLoading: false,
          exception: ErrorMapper.map(error, stackTrace),
        ),
      );
    }
  }

  Future<void> loadMore() async {
    final accountId = state.account?.id;
    final token = state.nextPageToken;
    if (accountId == null || token == null || state.isAppending) return;

    emit(state.copyWith(isAppending: true));
    try {
      final page = await _connectors.listProviderFiles(
        accountId,
        pageToken: token,
      );
      emit(
        state.copyWith(
          isAppending: false,
          files: [...state.files, ...page.files],
          indexedCount: page.indexedCount,
          totalCount: page.totalCount,
          nextPageToken: page.nextPageToken,
        ),
      );
    } catch (error, stackTrace) {
      // A failed *append* must not throw away the rows already on screen.
      emit(
        state.copyWith(
          isAppending: false,
          exception: ErrorMapper.map(error, stackTrace),
        ),
      );
    }
  }

  /// Index this file, or drop its index.
  ///
  /// The row is updated **after** the server confirms, not optimistically.
  /// Everywhere else in the app an optimistic update is right, because the
  /// worst case is a row that flickers back. Here the worst case is a row
  /// that says INDEXED when nothing was indexed, and the user believing an
  /// answer drew on a file it never read. Half a second of a spinner is the
  /// cheaper mistake.
  ///
  /// Dropping an index never touches the file in Drive — see
  /// [ConnectorRepository.setFileIndexed], and the note the screen prints
  /// under the list.
  Future<void> toggleIndexed(ProviderFile file) async {
    final accountId = state.account?.id;
    if (accountId == null || state.pending.contains(file.id)) return;

    emit(state.copyWith(pending: {...state.pending, file.id}, exception: null));

    try {
      await _connectors.setFileIndexed(
        accountId: accountId,
        fileId: file.id,
        indexed: !file.indexed,
      );

      emit(
        state.copyWith(
          files: [
            for (final f in state.files)
              if (f.id == file.id)
                (
                  id: f.id,
                  name: f.name,
                  path: f.path,
                  mimeType: f.mimeType,
                  bytes: f.bytes,
                  indexed: !f.indexed,
                )
              else
                f,
          ],
          // Moved by one rather than re-counted: the header's number is the
          // server's, and re-listing the whole account to move it by one
          // would be a page fetch per tap.
          indexedCount: state.indexedCount + (file.indexed ? -1 : 1),
          pending: {...state.pending}..remove(file.id),
          // Counted, not flagged: two removals in a row are two pieces of
          // news, and a flag that was already true would say nothing.
          unindexed: state.unindexed + (file.indexed ? 1 : 0),
        ),
      );
    } catch (error, stackTrace) {
      emit(
        state.copyWith(
          pending: {...state.pending}..remove(file.id),
          exception: ErrorMapper.map(error, stackTrace),
        ),
      );
    }
  }

  void dismissError() => emit(state.copyWith(exception: null));

  @override
  Future<void> close() {
    _subscription.cancel();
    return super.close();
  }
}
