/// How long each cached thing stays usable, in one place.
///
/// TTLs are set by *what changes the data*, not by gut feel:
///
/// * [providerCatalogue] changes only when the backend is deployed with new
///   credentials, so it can be hours.
/// * [providerFolders] is a live walk of somebody's Drive — the most
///   expensive call in the app, several round trips per folder — and the
///   thing it describes changes on a human timescale. Ten minutes covers a
///   back-and-forth through screen 3K without re-walking anything.
/// * [subscription] gates the paywall, so it is deliberately short: showing
///   a stale free tier to someone who just upgraded is the worst failure of
///   the set.
abstract final class CachePolicy {
  static const providerCatalogue = Duration(hours: 6);
  static const providerFolders = Duration(minutes: 10);
  static const subscription = Duration(minutes: 2);

  /// Anything older than this is dropped on sight rather than served stale.
  /// A hard ceiling so a cache entry written by an old build cannot outlive
  /// the shape it was written in.
  static const hardExpiry = Duration(days: 7);
}
