import '../entities/index_job.dart';
import '../entities/provider_folder.dart';
import '../entities/storage_account.dart';
import '../entities/storage_provider.dart';

/// What a completed OAuth round trip produced.
typedef ConnectResult = ({StorageAccount account, bool reconnected});

/// One file in a connected account, as screen 1L lists it.
///
/// A record rather than a freezed entity because it is a *listing* row and
/// nothing owns it: it is read, drawn, and thrown away on the next page. A
/// `ProviderFile` never outlives the screen that asked for it, so there is
/// nothing for `copyWith`, equality or JSON to do.
///
/// [indexed] is the only mutable thing about it, and it is not mutated here —
/// [ConnectorRepository.setFileIndexed] tells the server, and the next
/// listing reports the result.
typedef ProviderFile = ({
  String id,
  String name,

  // Where it sits, already joined for display: "Drive › Contracts". The
  // provider's own folder chain, not a filesystem path.
  String path,
  String? mimeType,
  int bytes,
  bool indexed,
});

/// A page of [ProviderFile]s, plus the two numbers 1L prints in its header.
///
/// The counts come down with the page rather than being derived from it: the
/// header says "842 OF 10,412 INDEXED" about the whole account, and a client
/// that has loaded thirty rows cannot work either number out.
typedef ProviderFilePage = ({
  List<ProviderFile> files,
  String? nextPageToken,
  int indexedCount,
  int totalCount,
});

/// Domain-owned contract. Every method throws an `AppException` on failure.
///
/// Notice what is *not* here: no `getAccessToken`, no `refresh`, no token of
/// any kind. The client never holds provider credentials — it asks for a URL,
/// hands back a code, and reads the account that results. Keeping that out of
/// the contract is what stops a future screen from casually adding it.
abstract interface class ConnectorRepository {
  /// Screen 3F. Live, because connecting an account elsewhere — or losing one
  /// to a revocation — has to show up without a pull-to-refresh.
  Stream<ConnectorCatalog> watchCatalog();

  /// Runs the whole browser round trip and returns once the account exists.
  ///
  /// Throws `AppException.cancelled()` if the user backs out of the provider's
  /// consent screen, which is an ordinary outcome and not an error to report.
  Future<ConnectResult> connect(StorageProvider provider, {ScopeLevel scope});

  /// Screen 3G's second toggle.
  ///
  /// Escalating to [ScopeLevel.manage] cannot be done server-side — only the
  /// user can widen a grant — so this runs the same browser round trip.
  /// Narrowing drops the tokens and requires a reconnect, because no provider
  /// offers a partial revoke and a toggle that reads "off" while a
  /// manage-capable token is still live would be a lie.
  Future<StorageAccount> setScopeLevel(String accountId, ScopeLevel scope);

  /// Screen 3K's list.
  ///
  /// Cached, because listing folders costs one provider request per folder
  /// just to count what is inside it. [forceRefresh] is the pull-to-refresh
  /// escape hatch for somebody who just created a folder and expects to see
  /// it.
  Future<({List<ProviderFolder> folders, Set<String> selected})> listFolders(
    String accountId, {
    bool forceRefresh,
  });

  /// 3K → 3L. Returns the job id the progress screen then streams.
  Future<String> setIndexedFolders(
    String accountId,
    List<ProviderFolder> folders,
  );

  /// Screen 3L.
  Stream<IndexJob> watchIndexJob(String jobId);

  /// Screen 1L's list of individual files.
  ///
  /// Separate from [listFolders] because the two answer different questions.
  /// Folders are the *bulk* decision made once during onboarding — "index all
  /// of Contracts" — and are cached hard because counting them is the most
  /// expensive call in the app. Files are the *retail* decision made forever
  /// afterwards, one row at a time, and must reflect a change the moment the
  /// user makes it. Caching this the way folders are cached would show a file
  /// as unindexed seconds after it was indexed.
  ///
  /// Paged with an opaque token rather than an offset: the provider's own
  /// listing is a cursor, and a file added while the user is scrolling would
  /// shift every offset below it.
  Future<ProviderFilePage> listProviderFiles(
    String accountId, {
    String? pageToken,
  });

  /// Screen 1L's per-row chip: index this one file, or drop its index.
  ///
  /// **Only ever the index.** Dropping a file from the index removes what Hawk
  /// derived from it — the chunks and the embeddings — and does not touch the
  /// file in the user's Drive. That is §7 and §10, and it is why the chip can
  /// be a single tap with no confirmation: nothing it does is destructive to
  /// anything the user owns. The screen says so in as many words underneath
  /// the list.
  ///
  /// Returns when the server has recorded the change, not when the indexing
  /// has finished — a large file may take minutes, and the row reports that
  /// through its next listing rather than by holding this call open.
  Future<void> setFileIndexed({
    required String accountId,
    required String fileId,
    required bool indexed,
  });

  /// §40's fork. [deleteMemories] is the destructive branch and defaults to
  /// false: keeping the index means reconnecting restores everything.
  Future<void> disconnect(String accountId, {bool deleteMemories});

  /// Ends the onboarding run, including screen 3F's "Skip" path.
  Future<void> completeSetup();

  /// Screen 1G's second option: make this phone a source.
  ///
  /// Not a [connect] with a different provider, because there is nothing to
  /// connect *to* — no browser, no grant, no account to name. The call exists
  /// only so the choice becomes a row the user can see and later disconnect;
  /// the files themselves arrive one at a time through the system picker.
  Future<StorageAccount> connectDeviceVault({String? deviceName});
}
