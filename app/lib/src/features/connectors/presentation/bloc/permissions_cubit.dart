import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:injectable/injectable.dart';

import '../../../../core/bloc/safe_emit.dart';
import '../../../../core/error/app_exception.dart';
import '../../../../core/error/error_mapper.dart';
import '../../domain/entities/storage_account.dart';
import '../../domain/entities/storage_provider.dart';
import '../../domain/repositories/connector_repository.dart';

part 'permissions_cubit.freezed.dart';

@freezed
abstract class PermissionsState with _$PermissionsState {
  const factory PermissionsState({
    required StorageAccount account,
    @Default(false) bool isSubmitting,

    /// Set after narrowing to read-only, which drops the grant entirely —
    /// no provider offers a partial revoke.
    @Default(false) bool needsReconnect,
    AppException? exception,
  }) = _PermissionsState;

  const PermissionsState._();

  bool get canManage => account.scopeLevel == ScopeLevel.manage;
}

/// Screen 3G — PERMISSIONS, READ VS MANAGE.
///
/// The read toggle is fixed on and not interactive: §46 makes indexing the
/// minimum permission, and a switch that cannot be turned off is honest about
/// that where a missing switch would just look like an oversight.
@injectable
class PermissionsCubit extends Cubit<PermissionsState>
    with SafeEmit<PermissionsState> {
  PermissionsCubit(this._repository, @factoryParam StorageAccount account)
    : super(PermissionsState(account: account));

  final ConnectorRepository _repository;

  Future<void> setManage(bool enabled) async {
    if (state.isSubmitting) return;
    final target = enabled ? ScopeLevel.manage : ScopeLevel.read;
    if (state.account.scopeLevel == target) return;

    emit(state.copyWith(isSubmitting: true, exception: null));
    try {
      final account = await _repository.setScopeLevel(state.account.id, target);
      emit(
        state.copyWith(
          account: account,
          isSubmitting: false,
          needsReconnect: !enabled,
        ),
      );
    } on CancelledException {
      // Declining the wider consent leaves the connection exactly as it was.
      emit(state.copyWith(isSubmitting: false));
    } catch (error, stackTrace) {
      emit(
        state.copyWith(
          isSubmitting: false,
          exception: ErrorMapper.map(error, stackTrace),
        ),
      );
    }
  }

  void dismissError() => emit(state.copyWith(exception: null));
}
