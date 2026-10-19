import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:injectable/injectable.dart';

import '../../../../core/bloc/safe_emit.dart';
import '../../../../core/error/app_exception.dart';
import '../../../../core/error/error_mapper.dart';
import '../../domain/entities/storage_account.dart';
import '../../domain/entities/storage_provider.dart';
import '../../domain/repositories/connector_repository.dart';

part 'connect_storage_cubit.freezed.dart';

@freezed
abstract class ConnectStorageState with _$ConnectStorageState {
  const factory ConnectStorageState({
    ConnectorCatalog? catalog,
    @Default(true) bool isLoading,

    /// Which provider's browser sheet is open. One at a time — the OAuth
    /// round trip owns the screen while it runs.
    StorageProvider? connecting,
    @Default(false) bool isFinishing,

    /// The account that was just connected, which screen 3G then scopes.
    StorageAccount? justConnected,
    AppException? exception,
  }) = _ConnectStorageState;

  const ConnectStorageState._();

  bool get isBusy => connecting != null || isFinishing;

  /// Continue is only meaningful with something connected; without one the
  /// way forward is "Skip — use device storage only".
  bool get hasAnyConnection =>
      (catalog?.options ?? const []).any((o) => o.isConnected);
}

/// Screen 3F — CONNECT STORAGE (BYOS).
@injectable
class ConnectStorageCubit extends Cubit<ConnectStorageState>
    with SafeEmit<ConnectStorageState> {
  ConnectStorageCubit(this._repository) : super(const ConnectStorageState()) {
    _subscription = _repository.watchCatalog().listen(
      (catalog) => emit(state.copyWith(catalog: catalog, isLoading: false)),
      onError: (Object error, StackTrace stackTrace) => emit(
        state.copyWith(
          isLoading: false,
          exception: ErrorMapper.map(error, stackTrace),
        ),
      ),
    );
  }

  final ConnectorRepository _repository;
  late final StreamSubscription<ConnectorCatalog> _subscription;

  Future<void> connect(StorageProvider provider) async {
    if (state.isBusy) return;
    emit(state.copyWith(connecting: provider, exception: null));

    try {
      final result = await _repository.connect(provider);
      emit(state.copyWith(connecting: null, justConnected: result.account));
    } on CancelledException {
      // Backing out of a consent screen is a decision, not a failure. Clearing
      // the busy flag silently is the whole handling — an error toast here
      // would tell people off for changing their mind.
      emit(state.copyWith(connecting: null));
    } catch (error, stackTrace) {
      emit(
        state.copyWith(
          connecting: null,
          exception: ErrorMapper.map(error, stackTrace),
        ),
      );
    }
  }

  /// Screen 1G's second option — make this phone a source.
  ///
  /// Deliberately not routed through [connect]: there is no browser round
  /// trip, so there is no consent to cancel and no `justConnected` hand-off to
  /// screen 1H. The row simply appears, and the picker that fills it is the
  /// Library's job from here on.
  Future<void> connectDevice() async {
    if (state.isBusy) return;
    emit(state.copyWith(connecting: StorageProvider.internal, exception: null));

    try {
      await _repository.connectDeviceVault();
      emit(state.copyWith(connecting: null));
    } catch (error, stackTrace) {
      emit(
        state.copyWith(
          connecting: null,
          exception: ErrorMapper.map(error, stackTrace),
        ),
      );
    }
  }

  Future<void> disconnect(String accountId) async {
    if (state.isBusy) return;
    try {
      // Never the destructive branch from this screen. Deleting the index is
      // offered in Settings, where there is room to explain what goes.
      await _repository.disconnect(accountId);
    } catch (error, stackTrace) {
      emit(state.copyWith(exception: ErrorMapper.map(error, stackTrace)));
    }
  }

  /// Both "Continue" and "Skip" land here — skipping is a real choice, and a
  /// device-only vault is a usable product.
  Future<void> finish() async {
    if (state.isBusy) return;
    emit(state.copyWith(isFinishing: true, exception: null));
    try {
      await _repository.completeSetup();
      emit(state.copyWith(isFinishing: false));
    } catch (error, stackTrace) {
      emit(
        state.copyWith(
          isFinishing: false,
          exception: ErrorMapper.map(error, stackTrace),
        ),
      );
    }
  }

  void acknowledgeConnection() => emit(state.copyWith(justConnected: null));

  void dismissError() => emit(state.copyWith(exception: null));

  @override
  Future<void> close() {
    _subscription.cancel();
    return super.close();
  }
}
