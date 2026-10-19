import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/core/cache/cache_store.dart';
import 'package:knowra/src/core/error/app_exception.dart';
import 'package:knowra/src/features/account/domain/entities/account_overview.dart';
import 'package:knowra/src/features/account/domain/repositories/account_repository.dart';
import 'package:knowra/src/features/account/presentation/bloc/profile_cubit.dart';
import 'package:knowra/src/features/voice/presentation/bloc/vault_ready_cubit.dart';

class _Accounts extends Fake implements AccountRepository {
  _Accounts({required this.fresh, this.cached});

  final AccountOverview? cached;
  final Future<AccountOverview> Function() fresh;

  @override
  Future<AccountOverview?> cachedOverview() async => cached;

  @override
  Future<AccountOverview> overview() => fresh();
}

/// The account summary is a Cloud Function running five aggregations — the
/// slowest thing on home, the profile and the vault. These pin that the last
/// one draws at once and the live one replaces it.
void main() {
  test("home's greeting count is there on open, then corrected", () async {
    final live = Completer<AccountOverview>();
    final seen = <int?>[];
    final cubit = VaultReadyCubit(
      _Accounts(
        cached: const AccountOverview(indexed: 5),
        fresh: () => live.future,
      ),
    );
    addTearDown(cubit.close);
    final sub = cubit.stream.listen(seen.add);
    addTearDown(sub.cancel);

    await Future<void>.delayed(Duration.zero);
    expect(cubit.state, 5);
    live.complete(const AccountOverview(indexed: 6));
    await Future<void>.delayed(Duration.zero);
    expect(seen, [5, 6]);
  });

  test('a failed refresh keeps the cached count, not a dash', () async {
    final cubit = VaultReadyCubit(
      _Accounts(
        cached: const AccountOverview(indexed: 5),
        fresh: () async => throw const AppException.network(),
      ),
    );
    addTearDown(cubit.close);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state, 5);
  });

  test('the profile shows the last numbers, and no error over them', () async {
    final cubit = ProfileCubit(
      _Accounts(
        cached: const AccountOverview(memories: 12),
        fresh: () async => throw const AppException.network(),
      ),
    );
    addTearDown(cubit.close);
    await cubit.load();
    expect(cubit.state.overview?.memories, 12);
    expect(cubit.state.error, isNull);
    expect(cubit.state.isLoading, isFalse);
  });

  test('with nothing cached, a failure is still reported', () async {
    final cubit = ProfileCubit(
      _Accounts(fresh: () async => throw const AppException.network()),
    );
    addTearDown(cubit.close);
    await cubit.load();
    expect(cubit.state.error, isNotNull);
  });

  test('callable maps are made storable, all the way down', () {
    final json = jsonSafe(<Object?, Object?>{
      'counts': <Object?, Object?>{
        'byKind': <Object?, Object?>{'images': 3},
        'list': [
          <Object?, Object?>{1: 'a'},
        ],
      },
    });
    expect(json['counts'], isA<Map<String, dynamic>>());
    expect((json['counts'] as Map)['byKind'], {'images': 3});
    expect(((json['counts'] as Map)['list'] as List).single, {'1': 'a'});
  });
}
