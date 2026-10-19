import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:injectable/injectable.dart';

/// Firestore's offline cache budget.
///
/// Outside [FirebaseModule] on purpose. Injectable treats every public member
/// of a `@module` class as something to register — a `static const int` in
/// there was generated as `gh.factory<int>(...)`, i.e. an `int` provider in
/// the DI graph, which then failed to compile because the generated subclass
/// cannot see an inherited static. Constants live outside the module.
abstract final class FirestoreCache {
  /// The largest value `Settings` accepts: 100 MiB.
  ///
  /// Not a preference — the SDK asserts on anything larger, inside
  /// `copyWith`, which is what `FirebaseFirestore.settings=` calls. Exceeding
  /// it takes down the whole DI graph on the first frame.
  static const maxBytes = 100 * 1024 * 1024;
}

/// The Firebase singletons, registered so nothing reaches for `.instance`
/// directly.
///
/// That indirection is the whole reason the repositories are testable: a test
/// binds a fake here instead of every call site having a hard dependency on a
/// live Firebase app.
@module
abstract class FirebaseModule {
  @lazySingleton
  FirebaseAuth get auth => FirebaseAuth.instance;

  /// Firestore, with its offline cache turned on explicitly and given room.
  ///
  /// It is on by default on mobile, but the default 40 MB ceiling is small
  /// for a library of thousands of memories — and once it is hit, Firestore
  /// starts evicting, so the library goes from instant to a network round
  /// trip with no visible cause.
  ///
  /// [maxCacheBytes] is the SDK's own ceiling, not a preference. Anything
  /// larger fails an assertion inside `Settings` at construction, which means
  /// it takes the whole DI graph down on the first frame — Firestore, then
  /// the auth repository, then the session cubit.
  ///
  /// Bounded rather than `CACHE_SIZE_UNLIMITED`: unlimited switches off
  /// garbage collection entirely, and a cache that never evicts is one that
  /// grows until the phone complains.
  ///
  /// This is the app's primary cache and the reason `snapshots()` is used
  /// everywhere in preference to `get()`: a listener serves the local copy
  /// on the first frame and then updates, so a cold start renders real
  /// content immediately and a plane-mode session still works. Settings must
  /// be assigned before the first Firestore call, which is why this happens
  /// in the provider rather than in `bootstrap`.
  @lazySingleton
  FirebaseFirestore get firestore => FirebaseFirestore.instance
    ..settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: FirestoreCache.maxBytes,
    );

  @lazySingleton
  FirebaseStorage get storage => FirebaseStorage.instance;

  /// Callables live in `us-central1`, matching the `region=` on each function.
  /// A mismatch here does not fail at build time — it fails at call time with
  /// an opaque `not-found`.
  @lazySingleton
  FirebaseFunctions get functions =>
      FirebaseFunctions.instanceFor(region: 'us-central1');
}
