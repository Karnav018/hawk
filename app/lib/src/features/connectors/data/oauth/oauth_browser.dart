import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:injectable/injectable.dart';

import '../../../../core/error/app_exception.dart';

/// The browser half of the OAuth round trip.
///
/// Wrapped in an interface for one reason that matters: this is the only thing
/// in the connector flow that cannot run in a test, so everything above it
/// stays testable by swapping this out.
abstract interface class OAuthBrowser {
  /// Opens [authorizationUrl] and resolves with the query parameters the
  /// provider redirected back with.
  ///
  /// Throws `AppException.cancelled()` when the user dismisses the sheet —
  /// backing out of a consent screen is a decision, not a failure, and must
  /// not surface as an error snackbar.
  Future<Map<String, String>> authorize({
    required String authorizationUrl,
    required String callbackScheme,
  });
}

@LazySingleton(as: OAuthBrowser)
class WebAuthOAuthBrowser implements OAuthBrowser {
  @override
  Future<Map<String, String>> authorize({
    required String authorizationUrl,
    required String callbackScheme,
  }) async {
    try {
      final result = await FlutterWebAuth2.authenticate(
        url: authorizationUrl,
        callbackUrlScheme: callbackScheme,
        // ephemeral: false keeps the system cookie jar, so somebody already
        // signed in to Google is not made to type their password again — the
        // difference between a two-tap connect and a two-minute one.
        options: const FlutterWebAuth2Options(preferEphemeral: false),
      );
      final uri = Uri.parse(result);

      // The provider reports refusal in the redirect, not as a transport
      // error, so the "user said no" path arrives here looking like success.
      final error = uri.queryParameters['error'];
      if (error != null) {
        throw error == 'access_denied'
            ? const AppException.cancelled(message: 'You did not grant access.')
            : AppException.badRequest(
                message:
                    uri.queryParameters['error_description'] ??
                    'The provider refused the connection.',
              );
      }
      return uri.queryParameters;
    } on AppException {
      rethrow;
    } catch (_) {
      // flutter_web_auth_2 throws a PlatformException on dismissal with a
      // message that varies by OS version, so the type is all there is to go
      // on. Treating an unexpected failure as a cancel is the safe direction:
      // the alternative is an error toast for someone who simply tapped Done.
      throw const AppException.cancelled(message: 'Connection cancelled.');
    }
  }
}
