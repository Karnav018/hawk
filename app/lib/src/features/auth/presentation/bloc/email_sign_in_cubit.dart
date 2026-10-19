import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:injectable/injectable.dart';

import '../../../../core/bloc/safe_emit.dart';
import '../../../../core/error/app_exception.dart';
import '../../../../core/error/error_mapper.dart';
import '../../../../core/validation/validators.dart';
import '../../domain/repositories/auth_repository.dart';

part 'email_sign_in_cubit.freezed.dart';

@freezed
abstract class EmailSignInState with _$EmailSignInState {
  const factory EmailSignInState({
    @Default('') String email,
    @Default('') String code,
    @Default(false) bool isSending,
    @Default(false) bool isVerifying,

    /// Set once a code is in flight to the inbox — screen 3I is reachable.
    @Default(false) bool codeSent,

    /// Seconds until "Resend code" becomes tappable again.
    @Default(0) int resendIn,

    /// True once the field has been left or submitted.
    ///
    /// Errors are held back until then: telling someone their address is
    /// invalid while they are still typing the second character is noise, not
    /// help.
    @Default(false) bool emailTouched,
    AppException? exception,
  }) = _EmailSignInState;

  const EmailSignInState._();

  ValidationResult get emailValidation => Validators.email(email);

  bool get isEmailValid => emailValidation.isValid;

  /// Shown under the field, and only once the user has stopped typing it.
  String? get emailError =>
      emailTouched && !isEmailValid ? emailValidation.message : null;

  /// A likely typo — advisory, never blocking.
  String? get emailSuggestion =>
      isEmailValid ? Validators.emailDomainSuggestion(email) : null;

  bool get isCodeComplete => code.length == EmailSignInCubit.codeLength;

  bool get canSend => isEmailValid && !isSending;

  bool get canResend => resendIn == 0 && !isSending;
}

/// Screens 3H (enter address) and 3I (verify code).
@injectable
class EmailSignInCubit extends Cubit<EmailSignInState>
    with SafeEmit<EmailSignInState> {
  EmailSignInCubit(this._repository) : super(const EmailSignInState());

  static const codeLength = 6;

  final AuthRepository _repository;
  Timer? _resendTimer;

  void emailChanged(String value) => emit(
    // Typing clears a stale error rather than re-validating on every
    // keystroke; the message comes back on blur or submit.
    state.copyWith(email: value, emailTouched: false, exception: null),
  );

  /// Called on blur, so the error appears when the user has moved on.
  void emailBlurred() => emit(state.copyWith(emailTouched: true));

  /// Accepts the "did you mean …" suggestion.
  void acceptEmailSuggestion() {
    final suggestion = state.emailSuggestion;
    if (suggestion != null) {
      emit(state.copyWith(email: suggestion, emailTouched: true));
    }
  }

  /// Digits only, capped at the code length — the keyboard is numeric but
  /// paste and autofill are not.
  void codeChanged(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    emit(
      state.copyWith(
        code: digits.length > codeLength
            ? digits.substring(0, codeLength)
            : digits,
        exception: null,
      ),
    );
  }

  Future<void> sendCode() async {
    if (!state.isEmailValid) {
      // Surfaces the message rather than failing silently when someone taps a
      // disabled-looking button.
      emit(state.copyWith(emailTouched: true));
      return;
    }
    if (!state.canSend) return;

    // Normalise here, not just in the repository: this value is also what
    // screen 3I prints back ("Six digits sent to ..."), and raw keyboard input
    // carries stray casing and whitespace.
    final email = state.email.trim().toLowerCase();
    // codeSent is lowered before the request, not just raised after it.
    // Screen 3H navigates on the false -> true edge, so leaving it latched
    // means coming back from 3I and tapping Send again changes nothing at
    // all — the code is re-sent and the user sits on the address screen.
    emit(
      state.copyWith(
        email: email,
        isSending: true,
        codeSent: false,
        exception: null,
      ),
    );

    try {
      final challenge = await _repository.requestEmailCode(email);
      emit(
        state.copyWith(
          isSending: false,
          codeSent: true,
          code: '',
          resendIn: challenge.resendIn.inSeconds,
        ),
      );
      _startResendCountdown();
    } catch (error, stackTrace) {
      emit(
        state.copyWith(
          isSending: false,
          exception: ErrorMapper.map(error, stackTrace),
        ),
      );
    }
  }

  Future<void> verify() async {
    if (!Validators.verificationCode(state.code, length: codeLength).isValid) {
      return;
    }
    if (state.isVerifying) return;
    emit(state.copyWith(isVerifying: true, exception: null));

    try {
      await _repository.verifyEmailCode(email: state.email, code: state.code);
      // No success state: the repository publishes the session and the router
      // moves. Emitting one here would be a second source of truth.
      emit(state.copyWith(isVerifying: false));
    } catch (error, stackTrace) {
      // Wrong code: clear the field so the next attempt starts clean rather
      // than making someone delete six digits by hand.
      emit(
        state.copyWith(
          isVerifying: false,
          code: '',
          exception: ErrorMapper.map(error, stackTrace),
        ),
      );
    }
  }

  void _startResendCountdown() {
    _resendTimer?.cancel();
    // Nothing to count down: a server with no cooldown must not leave a
    // periodic timer running for the life of the screen.
    if (state.resendIn <= 0) return;
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final next = state.resendIn - 1;
      if (next <= 0) {
        timer.cancel();
        emit(state.copyWith(resendIn: 0));
      } else {
        emit(state.copyWith(resendIn: next));
      }
    });
  }

  @override
  Future<void> close() {
    _resendTimer?.cancel();
    return super.close();
  }
}
