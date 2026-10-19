import 'package:flutter/foundation.dart';

/// The store a plan was bought through, in words.
String storeName(String? store) => switch (store) {
  'app_store' => 'the App Store',
  'google_play' => 'Google Play',
  _ =>
    defaultTargetPlatform == TargetPlatform.iOS
        ? 'the App Store'
        : 'Google Play',
};

/// The store's own subscription page — where the card is changed and where
/// cancelling lives. Keyed to the store that sold the plan, not to the phone
/// in hand: a plan bought on an iPhone is managed at Apple even when opened
/// from an Android device.
Uri manageUrl(String? store, String? productId) {
  final apple = switch (store) {
    'app_store' => true,
    'google_play' => false,
    _ => defaultTargetPlatform == TargetPlatform.iOS,
  };
  if (apple) return Uri.parse('https://apps.apple.com/account/subscriptions');
  return Uri.https('play.google.com', '/store/account/subscriptions', {
    'package': 'in.hawkapp.app',
    'sku': ?productId,
  });
}
