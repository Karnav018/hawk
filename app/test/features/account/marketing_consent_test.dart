import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/features/account/domain/entities/account_overview.dart';
import 'package:knowra/src/features/account/domain/repositories/account_repository.dart';
import 'package:knowra/src/features/account/presentation/bloc/profile_cubit.dart';

/// Offers and news by email: what the profile's switch does.
class _Accounts extends Fake implements AccountRepository {
  _Accounts({this.optedIn});

  /// What the server reports; null means it sent no choice at all.
  final bool? optedIn;
  final List<bool> saved = [];
  Object? failure;

  @override
  Future<AccountOverview?> cachedOverview() async => null;

  @override
  Future<AccountOverview> overview() async => optedIn == null
      ? const AccountOverview(email: 'me@hawk.test')
      : AccountOverview(email: 'me@hawk.test', marketingOptIn: optedIn!);

  @override
  Future<void> setMarketingConsent({required bool optIn}) async {
    if (failure != null) throw failure!;
    saved.add(optIn);
  }
}

void main() {
  test('on by default, and turning it off is saved and shown', () async {
    final accounts = _Accounts();
    final cubit = ProfileCubit(accounts);
    await cubit.load();
    expect(
      cubit.state.overview!.marketingOptIn,
      isTrue,
      reason: 'offers are on until the user turns them off',
    );

    expect(await cubit.setMarketing(optIn: false), isTrue);
    expect(accounts.saved, [false]);
    expect(cubit.state.overview!.marketingOptIn, isFalse);
    await cubit.close();
  });

  test('a user who turned it off stays off', () async {
    final cubit = ProfileCubit(_Accounts(optedIn: false));
    await cubit.load();
    expect(cubit.state.overview!.marketingOptIn, isFalse);
    await cubit.close();
  });

  test('a refused save puts the switch back', () async {
    final accounts = _Accounts(optedIn: true)..failure = StateError('offline');
    final cubit = ProfileCubit(accounts);
    await cubit.load();

    expect(await cubit.setMarketing(optIn: false), isFalse);
    expect(
      cubit.state.overview!.marketingOptIn,
      isTrue,
      reason: 'the switch must never show a choice that was not recorded',
    );
    expect(
      cubit.state.error,
      isNull,
      reason: '"could not load your account" would be the wrong words',
    );
    await cubit.close();
  });

  test('it works before the account has loaded', () async {
    final accounts = _Accounts();
    final cubit = ProfileCubit(accounts);

    expect(await cubit.setMarketing(optIn: false), isTrue);
    expect(cubit.state.overview!.marketingOptIn, isFalse);
    await cubit.close();
  });
}
