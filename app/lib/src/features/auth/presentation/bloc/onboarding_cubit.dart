import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:injectable/injectable.dart';

import '../../../../core/bloc/safe_emit.dart';
import '../../../../core/error/app_exception.dart';
import '../../../../core/error/error_mapper.dart';
import '../../../../core/validation/validators.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/entities/auth_user.dart';
import '../../domain/repositories/auth_repository.dart';

part 'onboarding_cubit.freezed.dart';

@freezed
abstract class OnboardingState with _$OnboardingState {
  const factory OnboardingState({
    @Default('') String name,
    @Default(InputPreference.voice) InputPreference inputPreference,
    @Default(false) bool isSubmitting,
    @Default(false) bool nameTouched,
    AppException? exception,
  }) = _OnboardingState;

  const OnboardingState._();

  ValidationResult get nameValidation => Validators.displayName(name);

  /// The name is optional — the server accepts null, and forcing a value here
  /// would just collect junk from people who want to get on with it. It still
  /// has to be *sane* when given.
  String? get nameError =>
      nameTouched && !nameValidation.isValid ? nameValidation.message : null;

  bool get canSubmit => !isSubmitting && nameValidation.isValid;
}

/// Screen 3J — your name, and how you'll mostly ask.
@injectable
class OnboardingCubit extends Cubit<OnboardingState>
    with SafeEmit<OnboardingState> {
  OnboardingCubit(this._repository)
    : super(
        // Start from what the session already knows. A social sign-in usually
        // arrives with a name attached, and asking for it again would look
        // like the app was not paying attention.
        OnboardingState(
          name: switch (_repository.current) {
            AuthOnboarding(:final user) => user.name ?? '',
            AuthAuthenticated(:final user) => user.name ?? '',
            _ => '',
          },
        ),
      );

  final AuthRepository _repository;

  void nameChanged(String value) =>
      emit(state.copyWith(name: value, nameTouched: false, exception: null));

  void nameBlurred() => emit(state.copyWith(nameTouched: true));

  void preferenceChanged(InputPreference preference) =>
      emit(state.copyWith(inputPreference: preference));

  Future<void> submit() async {
    if (!state.nameValidation.isValid) {
      emit(state.copyWith(nameTouched: true));
      return;
    }
    if (!state.canSubmit) return;
    emit(state.copyWith(isSubmitting: true, exception: null));

    try {
      final name = state.name.trim();
      await _repository.completeOnboarding(
        name: name.isEmpty ? null : name,
        inputPreference: state.inputPreference,
      );
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
}
