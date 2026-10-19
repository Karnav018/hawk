import '../entities/answer.dart';

/// What `search` returns: files, and how the question was read.
typedef MatchResults = ({List<Match> matches, QuerySignals signals});

/// Domain-owned contract for §25 retrieval and §27 RAG. Throws `AppException`.
abstract interface class AnswerRepository {
  /// Finds files, without generating prose.
  ///
  /// Screen 2C calls this while the user is still speaking, so it must not
  /// wait on a model to write an answer.
  ///
  /// Does **not** spend a question from the daily allowance; [ask] does. The
  /// allowance bounds generation, which is the expensive half, and searching
  /// is the product's core verb — metering it would let a free user exhaust
  /// their day finding a file without ever asking anything about it.
  Future<MatchResults> search(String query);

  /// Asks a question of the vault.
  ///
  /// [conversationId] continues a thread: a follow-up is *retrieved* with the
  /// previous turns folded in but *answered* as asked, so the model never
  /// answers a question the user did not put. Pass null to start a new
  /// thread; the id comes back on the [Answer].
  ///
  /// Throws `AppException.badRequest` carrying the server's own message when
  /// the daily allowance is spent.
  Future<Answer> ask(
    String question, {
    String? conversationId,
    List<String> earlier = const [],
  });
}
