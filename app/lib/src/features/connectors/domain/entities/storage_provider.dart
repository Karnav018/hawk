/// Which storage a memory came from, and which storage we can connect.
///
/// Lives in `connectors` rather than `memory` because a provider is a
/// connector concept that memory happens to reference — the dependency points
/// this way, not the other. `memory_enums.dart` re-exports it so nothing in
/// the memory feature had to change.
enum StorageProvider {
  googleDrive,

  /// Captured in the app itself — a note, a share-sheet drop, a voice memo.
  /// Not connectable, so it never appears on screen 3F.
  internal;

  /// Unknown values fall through to [internal] rather than throwing.
  ///
  /// Load-bearing, not defensive. Dropbox and OneDrive were removed from the
  /// product, and any memory or account document written while they existed
  /// still carries `provider: "dropbox"` — parsing has to survive reading
  /// its own history. A memory whose provider we no longer recognise is
  /// still a memory, and showing it as captured-here beats crashing the
  /// library.
  static StorageProvider parse(String? raw) => switch (raw) {
    'google_drive' => googleDrive,
    _ => internal,
  };

  /// The id the backend uses. Must match `connectors/base.py`.
  String get wireName => switch (this) {
    googleDrive => 'google_drive',
    internal => 'internal',
  };

  String get label => switch (this) {
    googleDrive => 'Google Drive',
    internal => 'Vault',
  };

  /// What screen 3F says under the name before anything is known about it.
  String get tagline => switch (this) {
    googleDrive => 'Docs, sheets, PDFs',
    internal => 'Captured here',
  };
}

/// §46 — what Vault may do with the files, as the binary question screen 3G
/// actually asks.
enum ScopeLevel {
  /// Read and index. Required; there is no product without it.
  read,

  /// Archive, move and delete — always behind a per-file confirmation.
  manage;

  static ScopeLevel parse(String? raw) => raw == 'manage' ? manage : read;

  String get wireName => name;
}

/// §40 — a connection is a relationship, not a boolean.
enum ConnectorState {
  connected,
  syncing,

  /// The user paused syncing from Settings. Ours to resume.
  paused,

  /// The user pulled access at the provider. We still hold an index built
  /// from files we can no longer reach — a state the UI has to explain, not
  /// hide, which is why it is not merged with "disconnected".
  revoked,
  error;

  static ConnectorState parse(String? raw) => switch (raw) {
    'syncing' => syncing,
    'paused' => paused,
    'revoked' => revoked,
    'error' => error,
    _ => connected,
  };

  bool get isHealthy => this == connected || this == syncing;

  bool get needsAttention => this == revoked || this == error;
}
