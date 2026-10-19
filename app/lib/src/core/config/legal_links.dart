import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// The privacy policy and the terms — the landing site's own pages.
///
/// One place for both addresses, because three screens link to them
/// (sign-in's consent line, 2K's two rows) and a store reviewer follows every
/// one. They are the landing's clean URLs (`vercel.json` sets `cleanUrls`),
/// served as standalone pages that open without loading the hero film.
///
/// The host is a build-time define so a custom domain is a flag, not a code
/// change: `--dart-define=LANDING_URL=https://hawkapp.in`.
abstract final class LegalLinks {
  static const _host = String.fromEnvironment(
    'LANDING_URL',
    defaultValue: 'https://hawkapp.in',
  );

  static final Uri privacy = Uri.parse('$_host/privacy');
  static final Uri terms = Uri.parse('$_host/terms');

  /// Opens a page in the in-app browser — SFSafariViewController on iOS,
  /// Custom Tabs on Android — so reading the terms is a sheet over Hawk, not
  /// a trip out to another app and back.
  static Future<bool> open(Uri page) => opener(page);

  /// Swapped in tests, which have no browser to open.
  @visibleForTesting
  static Future<bool> Function(Uri) opener = (page) =>
      launchUrl(page, mode: LaunchMode.inAppBrowserView);
}
