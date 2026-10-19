import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/core/di/firebase_module.dart';

/// The Firestore cache size is bounds-checked, but not where you would look.
///
/// `Settings(...)` accepts anything — the assertion lives in `copyWith`, which
/// `FirebaseFirestore.settings=` calls internally. So an out-of-range value is
/// invisible until assignment, and assignment happens inside the DI provider
/// that every other registration depends on. The result is not a Firestore
/// problem, it is a blank app: Firestore fails, then AuthRepository, then
/// SessionCubit, then the widget tree.
///
/// `flutter analyze` cannot see it (the value is a valid int) and no other
/// test builds the module. These call `copyWith` directly, which is the same
/// check the SDK runs, in the one place that will notice.
void main() {
  group('Firestore cache settings', () {
    test('the configured size is one the SDK will accept', () {
      expect(
        () =>
            const Settings().copyWith(cacheSizeBytes: FirestoreCache.maxBytes),
        returnsNormally,
      );
    });

    test('sits inside the SDK documented 1 MiB - 100 MiB range', () {
      const min = 1048576;
      const max = 104857600;
      expect(FirestoreCache.maxBytes, greaterThanOrEqualTo(min));
      expect(FirestoreCache.maxBytes, lessThanOrEqualTo(max));
    });

    test('is bigger than the default, which is the whole point', () {
      // Firestore defaults to 40 MB. Raising it is why this setting exists at
      // all — a library of thousands of memories evicts under the default and
      // silently starts costing a network round trip per screen.
      const firestoreDefault = 40 * 1024 * 1024;
      expect(FirestoreCache.maxBytes, greaterThan(firestoreDefault));
    });

    test('200 MB — the value that shipped broken — is rejected', () {
      // Kept as a live assertion rather than a comment: it documents that the
      // ceiling is real and enforced, and that the enforcement point is
      // `copyWith`, not the constructor. The constructor accepts 200 MB
      // happily, which is exactly why this got as far as a running device.
      expect(
        () => const Settings(cacheSizeBytes: 200 * 1024 * 1024),
        returnsNormally,
      );
      expect(
        () => const Settings().copyWith(cacheSizeBytes: 200 * 1024 * 1024),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
