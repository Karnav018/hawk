import 'answer.dart';

/// A question released with its files already found.
///
/// The voice face searches for what has been heard while the user is still
/// speaking (`VoiceCubit.find`, debounced), so by the time the finger lifts
/// the files for the sentence are usually already in hand. Handing them to
/// the result screen means the rows are there the instant it opens, and only
/// the answer is still to come — instead of the screen starting from nothing
/// and searching again for words it has had on screen for seconds.
class SeededQuestion {
  const SeededQuestion({
    required this.question,
    required this.matches,
    this.signals = const QuerySignals(),
  });

  final String question;
  final List<Match> matches;
  final QuerySignals signals;
}
