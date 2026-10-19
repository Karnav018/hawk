import '../../../../core/widgets/eye/eye_orb.dart';
import '../bloc/voice_cubit.dart';

/// `VoicePhase` -> `OrbState`, in the presentation layer where it belongs.
///
/// The two enums line up 1:1 and could have been one enum. They are not,
/// because [OrbState] has a fifth value — `indexing` — that the voice layer
/// can never be in: screen 1J has no microphone anywhere near it. Folding
/// them together would have given [VoiceCubit] a state it is not able to
/// enter, and every `switch` over the phase an unreachable branch to handle.
///
/// The mapping lives here rather than on the cubit so the bloc layer does not
/// import a widget's enum to describe its own state.
extension VoicePhaseOrb on VoicePhase {
  OrbState get orbState => switch (this) {
    VoicePhase.ready => OrbState.ready,
    VoicePhase.listening => OrbState.listening,
    VoicePhase.retrieving => OrbState.retrieving,
    VoicePhase.answered => OrbState.answered,
  };
}
