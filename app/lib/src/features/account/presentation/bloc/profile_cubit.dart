import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:injectable/injectable.dart';

import '../../../../core/bloc/safe_emit.dart';
import '../../../../core/error/app_exception.dart';
import '../../../../core/error/error_mapper.dart';
import '../../domain/entities/account_overview.dart';
import '../../domain/repositories/account_repository.dart';

part 'profile_cubit.freezed.dart';

/// Which irreversible thing, if any, is in flight.
///
/// Tracked as an enum rather than a pair of booleans so the two can never be
/// true at once — a screen that thinks it is both deactivating and deleting
/// has to pick one to render, and it will pick wrong.
enum AccountAction { none, deactivating, reactivating, deleting }

@freezed
abstract class ProfileState with _$ProfileState {
  const factory ProfileState({
    AccountOverview? overview,
    @Default(true) bool isLoading,
    @Default(AccountAction.none) AccountAction action,
    AppException? error,

    /// Set once the account is gone, so the screen can say so before the
    /// session ends and the router takes over.
    @Default(false) bool isDeleted,
  }) = _ProfileState;

  const ProfileState._();

  bool get isBusy => action != AccountAction.none;

  /// Nothing on this screen may be touched while a destructive action runs.
  bool get isInteractive => !isBusy && !isDeleted;
}

/// The account screen's state.
///
/// Loads its own summary rather than deriving it from other cubits, because
/// the numbers it shows (memories, dormant, connected accounts) are counts
/// nobody else needs and would be wasteful to keep live app-wide.
@injectable
class ProfileCubit extends Cubit<ProfileState> with SafeEmit<ProfileState> {
  ProfileCubit(this._accounts) : super(const ProfileState());

  final AccountRepository _accounts;

  Future<void> load() async {
    emit(state.copyWith(isLoading: true, error: null));

    // The last summary first, so the profile opens with its numbers rather
    // than zeros for the length of a Cloud Function call.
    AccountOverview? cached;
    try {
      cached = await _accounts.cachedOverview();
      if (cached != null) emit(state.copyWith(overview: cached));
    } on Object {
      // No head start; the fetch below is the real answer anyway.
    }

    try {
      // Into a local before the emit: `copyWith(overview: await …)` reads
      // `state` before the await and writes back whatever it was then.
      final overview = await _accounts.overview();
      emit(state.copyWith(overview: overview, isLoading: false));
    } catch (error, stackTrace) {
      emit(
        state.copyWith(
          isLoading: false,
          // Stale numbers on screen beat an error over them. The next open
          // tries again.
          error: cached == null ? ErrorMapper.map(error, stackTrace) : null,
        ),
      );
    }
  }

  Future<void> deactivate() => _run(
    AccountAction.deactivating,
    _accounts.deactivate,
    // Reloads afterwards: deactivation changes the status *and* the
    // connected-account count, and showing the old numbers next to a
    // "deactivated" badge would look like the action half-worked.
    reload: true,
  );

  Future<void> reactivate() =>
      _run(AccountAction.reactivating, _accounts.reactivate, reload: true);

  /// Returns true when the account is gone, so the caller can sign out.
  ///
  /// Deliberately *not* signing out itself. The order matters — the session
  /// has to survive long enough for the server call to be authorised, and a
  /// cubit that both deletes and signs out makes that sequencing invisible.
  Future<bool> delete(String confirmation) async {
    if (confirmation.trim().toUpperCase() != AccountRepository.deletePhrase) {
      emit(
        state.copyWith(
          error: const AppException.badRequest(
            message: 'Type DELETE to confirm.',
          ),
        ),
      );
      return false;
    }

    emit(state.copyWith(action: AccountAction.deleting, error: null));
    try {
      await _accounts.delete(confirmation: AccountRepository.deletePhrase);
      emit(state.copyWith(action: AccountAction.none, isDeleted: true));
      return true;
    } catch (error, stackTrace) {
      emit(
        state.copyWith(
          action: AccountAction.none,
          error: ErrorMapper.map(error, stackTrace),
        ),
      );
      return false;
    }
  }

  /// Turns offers and news by email on or off.
  ///
  /// The switch moves at once and moves back if the server refuses, so it
  /// never shows a choice that was not recorded. Returns false on failure
  /// for the caller to say so; the screen's own error state is for loading
  /// the account, and "could not load your account" would be the wrong words.
  Future<bool> setMarketing({required bool optIn}) async {
    final base = state.overview ?? const AccountOverview();
    emit(state.copyWith(overview: base.copyWith(marketingOptIn: optIn)));
    try {
      await _accounts.setMarketingConsent(optIn: optIn);
      return true;
    } on Object {
      final now = state.overview ?? base;
      emit(state.copyWith(overview: now.copyWith(marketingOptIn: !optIn)));
      return false;
    }
  }

  Future<void> _run(
    AccountAction action,
    Future<void> Function() operation, {
    bool reload = false,
  }) async {
    if (state.isBusy) return;
    emit(state.copyWith(action: action, error: null));
    try {
      await operation();
      emit(state.copyWith(action: AccountAction.none));
      if (reload) await load();
    } catch (error, stackTrace) {
      emit(
        state.copyWith(
          action: AccountAction.none,
          error: ErrorMapper.map(error, stackTrace),
        ),
      );
    }
  }

  void dismissError() => emit(state.copyWith(error: null));
}
