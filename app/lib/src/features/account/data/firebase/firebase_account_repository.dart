import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:injectable/injectable.dart';

import '../../../../core/cache/cache_store.dart';
import '../../../../core/error/app_exception.dart';
import '../../domain/entities/account_overview.dart';
import '../../domain/repositories/account_repository.dart';

/// [AccountRepository] over the account callables.
///
/// All four operations are server-side, and they have to be: the client can
/// no more delete its own memories than it can grant itself Premium — the
/// security rules deny both — and a client-side "delete everything" loop
/// that dies halfway leaves an account that is neither alive nor gone.
@LazySingleton(as: AccountRepository)
class FirebaseAccountRepository implements AccountRepository {
  FirebaseAccountRepository(this._functions, this._cache);

  final FirebaseFunctions _functions;

  /// Keeps the last summary, so home's "N memories ready", the profile and
  /// the vault draw their numbers on open instead of after a Cloud Function
  /// round trip — `account_summary` runs five aggregations and was the
  /// slowest thing on each of those screens.
  final CacheStore _cache;

  static const _summaryKey = 'account.summary';

  @override
  Future<AccountOverview> overview() async {
    try {
      final result = await _functions
          .httpsCallable('account_summary')
          .call<Object?>();
      final data = result.data;
      if (data is! Map) return const AccountOverview();
      final json = jsonSafe(data);
      unawaited(_cache.write(_summaryKey, json));
      return _parse(json);
    } on FirebaseFunctionsException catch (error, stackTrace) {
      throw _map(error, stackTrace);
    }
  }

  @override
  Future<AccountOverview?> cachedOverview() async {
    final cached = await _cache.read(_summaryKey);
    return cached == null ? null : _parse(cached.value);
  }

  AccountOverview _parse(Map<String, dynamic> data) {
    final counts = (data['counts'] as Map?) ?? const {};
    int at(String key) => (counts[key] as num?)?.toInt() ?? 0;

    return AccountOverview(
      email: data['email'] as String?,
      name: data['name'] as String?,
      createdAt: DateTime.tryParse(data['createdAt'] as String? ?? ''),
      status: AccountStatus.parse(data['status'] as String?),
      memories: at('memories'),
      indexed: at('indexed'),
      dormant: at('dormant'),
      accounts: at('accounts'),
      byKind: {
        for (final e in ((counts['byKind'] as Map?) ?? const {}).entries)
          e.key.toString(): (e.value as num?)?.toInt() ?? 0,
      },
      isTestAccount: data['isTestAccount'] as bool? ?? false,
      marketingOptIn: data['marketingOptIn'] as bool? ?? true,
    );
  }

  @override
  Future<void> deactivate() => _call('deactivate_account');

  @override
  Future<void> reactivate() => _call('reactivate_account');

  @override
  Future<void> setMarketingConsent({required bool optIn}) =>
      _call('set_marketing_consent', {'optIn': optIn});

  @override
  Future<void> delete({required String confirmation}) =>
      _call('delete_account', {'confirm': confirmation});

  Future<void> _call(String name, [Map<String, Object?>? data]) async {
    try {
      await _functions.httpsCallable(name).call<Object?>(data);
    } on FirebaseFunctionsException catch (error, stackTrace) {
      throw _map(error, stackTrace);
    }
  }

  AppException _map(
    FirebaseFunctionsException error,
    StackTrace stackTrace,
  ) => switch (error.code) {
    'unauthenticated' => const AppException.unauthorized(),
    // The typed-confirmation check, and anything else the server refuses on
    // its own terms. Carries the server's own message: "Type \"DELETE\" to
    // confirm" is the whole point, and a generic string loses it.
    'failed-precondition' => AppException.badRequest(
      message: error.message ?? 'That could not be done right now.',
    ),
    'unavailable' => const AppException.network(),
    // Deleting a large vault is a lot of batched writes. A timeout here does
    // not mean nothing happened — it means we stopped watching. The screen
    // says so rather than offering a retry that may not be needed.
    'deadline-exceeded' => const AppException.timeout(),
    _ => AppException.unknown(cause: error, stackTrace: stackTrace),
  };
}
