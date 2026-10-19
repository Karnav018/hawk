import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:injectable/injectable.dart';

import '../../../../core/bloc/safe_emit.dart';
import '../../../../core/error/app_exception.dart';
import '../../../../core/error/error_mapper.dart';
import '../../data/datasources/social_auth_gateway.dart';
import '../../domain/entities/auth_user.dart';
import '../../domain/repositories/auth_repository.dart';

part 'sign_in_cubit.freezed.dart';

@freezed
sealed class SignInState with _$SignInState {
  const factory SignInState.idle() = SignInIdle;

  /// Which provider is in flight, so only that button shows a spinner.
  const factory SignInState.submitting(SocialProvider provider) =
      SignInSubmitting;

  const factory SignInState.failure(AppException exception) = SignInFailure;
}

/// Drives screen 3E's provider buttons.
///
/// Success is not a state here: the repository publishes the new session and
/// the router reacts. A "signed in" state on this cubit would be a second
/// source of truth that could disagree with the first.
@injectable
class SignInCubit extends Cubit<SignInState> with SafeEmit<SignInState> {
  SignInCubit(this._repository, this._gateway)
    : super(const SignInState.idle());

  final AuthRepository _repository;
  final SocialAuthGateway _gateway;

  bool isAvailable(SocialProvider provider) => _gateway.isAvailable(provider);

  /// A provider the platform supports but this build has no credentials for.
  ///
  /// Shown, not hidden: a missing button looks like a design decision, and a
  /// release built without credentials would ship that way unnoticed. Dimmed
  /// with a clear message is louder and still safe.
  bool isConfigured(SocialProvider provider) => _gateway.isConfigured(provider);

  Future<void> signInWith(SocialProvider provider) async {
    if (state is SignInSubmitting) return;
    emit(SignInState.submitting(provider));

    try {
      await _repository.signInWith(provider);
      emit(const SignInState.idle());
    } catch (error, stackTrace) {
      final exception = ErrorMapper.map(error, stackTrace);

      // Backing out of the provider sheet is a normal thing to do, not a
      // failure worth putting an error in front of someone.
      emit(
        exception is CancelledException
            ? const SignInState.idle()
            : SignInState.failure(exception),
      );
    }
  }

  void dismissError() => emit(const SignInState.idle());
}
