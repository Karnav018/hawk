import 'package:bloc/bloc.dart';

/// Makes a late `emit` a no-op instead of a crash.
///
/// bloc throws `StateError: Cannot emit new states after calling close` on
/// purpose, and for most mistakes that is the right call — it means your
/// logic outlived the widget that owned it.
///
/// But this app has a shape where it is not a mistake and cannot be avoided
/// at the call site. Several cubits `await` a write whose *success changes the
/// session or the route*, and the router disposes the providing route as a
/// direct consequence. So:
///
///     await repository.completeOnboarding(...);   // session changes here
///     emit(state.copyWith(isSubmitting: false));  // route already gone
///
/// The trailing emit is the correct thing to write — the screen might still
/// be there — and whether it survives depends on which of two async events
/// lands first. Guarding every one of them individually is a rule that has to
/// be remembered fifty times; guarding here is a rule that cannot be
/// forgotten.
///
/// Deliberately silent. This is an expected race, not a warning, and logging
/// it would produce noise on every successful sign-in and every capture.
/// A genuine "logic outlived its widget" bug shows up as behaviour that does
/// not happen, which is what tests are for.
mixin SafeEmit<S> on BlocBase<S> {
  @override
  void emit(S state) {
    if (isClosed) return;
    super.emit(state);
  }
}
