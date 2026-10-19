/// Field validation, as pure functions.
///
/// Pure and UI-free on purpose: a validator that needs a `BuildContext` cannot
/// be unit-tested, and one that lives inside a widget gets copied the moment a
/// second screen needs it. These are the single definition, used by the cubits
/// (which decide *when* to show a message) and testable on their own.
///
/// The guiding rule throughout: **be permissive, and let the server be the
/// authority.** A regex that rejects a valid address is a worse failure than
/// one round trip, because the user has no way to argue with it.
library;

/// Why a value was rejected, separate from the words shown to the user.
///
/// Keeping the reason and the copy apart means messages can be reworded or
/// translated without touching a single rule.
enum ValidationIssue {
  required,
  tooShort,
  tooLong,
  malformedEmail,
  disposableEmail,
  notSixDigits,
  containsUrl,
}

class ValidationResult {
  const ValidationResult.valid() : issue = null, message = null;
  const ValidationResult.invalid(this.issue, this.message);

  final ValidationIssue? issue;
  final String? message;

  bool get isValid => issue == null;
}

const _valid = ValidationResult.valid();

abstract final class Validators {
  // ------------------------------------------------------------- email ----

  /// Deliberately loose.
  ///
  /// The full RFC 5322 grammar allows quoted strings, comments and IP-literal
  /// domains; almost every "email regex" on the internet rejects valid
  /// addresses. This checks the shape a typo would break — one `@`, something
  /// either side, a dot in the domain — and leaves the rest to the server,
  /// which finds out for certain by delivering a code to it.
  static ValidationResult email(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) {
      return const ValidationResult.invalid(
        ValidationIssue.required,
        'Enter your email address.',
      );
    }
    if (value.length > 320) {
      // RFC 5321: 64 for the local part, 255 for the domain.
      return const ValidationResult.invalid(
        ValidationIssue.tooLong,
        'That address is too long.',
      );
    }

    final at = value.indexOf('@');
    final lastAt = value.lastIndexOf('@');
    if (at <= 0 || at != lastAt || at == value.length - 1) {
      return const ValidationResult.invalid(
        ValidationIssue.malformedEmail,
        "That doesn't look like an email address.",
      );
    }

    final local = value.substring(0, at);
    final domain = value.substring(at + 1);

    if (local.length > 64) {
      return const ValidationResult.invalid(
        ValidationIssue.tooLong,
        'That address is too long.',
      );
    }
    if (value.contains(' ')) {
      return const ValidationResult.invalid(
        ValidationIssue.malformedEmail,
        'An email address cannot contain spaces.',
      );
    }

    final dot = domain.indexOf('.');
    final valid =
        dot > 0 &&
        dot < domain.length - 1 &&
        !domain.startsWith('.') &&
        !domain.endsWith('.') &&
        !domain.contains('..') &&
        !domain.startsWith('-') &&
        !domain.endsWith('-');

    if (!valid) {
      return const ValidationResult.invalid(
        ValidationIssue.malformedEmail,
        "That doesn't look like an email address.",
      );
    }

    return _valid;
  }

  /// A likely typo in a common provider's domain.
  ///
  /// Advisory, never blocking. Somebody's real domain might genuinely be one
  /// character from `gmail.com`, and refusing their address would be worse
  /// than a code that never arrives.
  static String? emailDomainSuggestion(String? raw) {
    final value = raw?.trim().toLowerCase() ?? '';
    final at = value.lastIndexOf('@');
    if (at < 0 || at == value.length - 1) return null;

    final domain = value.substring(at + 1);
    const common = [
      'gmail.com',
      'googlemail.com',
      'outlook.com',
      'hotmail.com',
      'yahoo.com',
      'icloud.com',
      'me.com',
      'proton.me',
      'protonmail.com',
    ];

    if (common.contains(domain)) return null;

    for (final candidate in common) {
      if (_editDistance(domain, candidate) == 1) {
        return '${value.substring(0, at + 1)}$candidate';
      }
    }
    return null;
  }

  /// Damerau-Levenshtein distance (optimal string alignment).
  ///
  /// Plain Levenshtein is not enough here. `gmial.com` — probably the single
  /// most common email typo there is — is a *transposition*, which Levenshtein
  /// scores as 2 and would therefore never suggest. Counting an adjacent swap
  /// as one edit catches `gmial`, `gmali`, `hotmial` and the rest of the
  /// fast-typing family.
  static int _editDistance(String a, String b) {
    if ((a.length - b.length).abs() > 1) return 2;

    // Three rows, because a transposition looks two steps back.
    var twoBack = <int>[];
    var previous = List<int>.generate(b.length + 1, (i) => i);

    for (var i = 1; i <= a.length; i++) {
      final current = <int>[i, ...List<int>.filled(b.length, 0)];

      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        var best = [
          current[j - 1] + 1, // insertion
          previous[j] + 1, // deletion
          previous[j - 1] + cost, // substitution
        ].reduce((x, y) => x < y ? x : y);

        final isSwap =
            i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1];
        if (isSwap) {
          final swapped = twoBack[j - 2] + 1;
          if (swapped < best) best = swapped;
        }

        current[j] = best;
      }

      twoBack = previous;
      previous = current;
    }

    return previous[b.length];
  }

  // -------------------------------------------------------------- code ----

  static ValidationResult verificationCode(String? raw, {int length = 6}) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) {
      return const ValidationResult.invalid(
        ValidationIssue.required,
        'Enter the code from your email.',
      );
    }
    if (value.length != length || !RegExp(r'^\d+$').hasMatch(value)) {
      return ValidationResult.invalid(
        ValidationIssue.notSixDigits,
        'The code is $length digits.',
      );
    }
    return _valid;
  }

  // -------------------------------------------------------------- name ----

  /// Optional by design.
  ///
  /// The server accepts null, and forcing a value on screen 3J would only
  /// collect junk from people who want to get on with it.
  static ValidationResult displayName(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return _valid;

    if (value.length > 80) {
      return const ValidationResult.invalid(
        ValidationIssue.tooLong,
        'Keep it under 80 characters.',
      );
    }
    if (_looksLikeUrl(value)) {
      // Display names are rendered in the app's own chrome; a link in one is
      // spam or an attempt at phishing, never a real name.
      return const ValidationResult.invalid(
        ValidationIssue.containsUrl,
        "A name can't contain a link.",
      );
    }
    return _valid;
  }

  // ------------------------------------------------------------ capture ----

  /// A URL to capture. Accepts what a person would actually paste.
  static ValidationResult captureUrl(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) {
      return const ValidationResult.invalid(
        ValidationIssue.required,
        'Paste a link to save.',
      );
    }

    // People paste `example.com/x` far more often than they type `https://`.
    final candidate = value.contains('://') ? value : 'https://$value';
    final uri = Uri.tryParse(candidate);

    final ok =
        uri != null &&
        uri.hasAuthority &&
        uri.host.contains('.') &&
        !uri.host.endsWith('.') &&
        const {'http', 'https'}.contains(uri.scheme);

    if (!ok) {
      return const ValidationResult.invalid(
        ValidationIssue.malformedEmail,
        "That doesn't look like a link.",
      );
    }
    return _valid;
  }

  /// The `https://`-prefixed form of a pasted link.
  static String? normalizeUrl(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return null;
    return value.contains('://') ? value : 'https://$value';
  }

  // ------------------------------------------------------------- notes ----

  static ValidationResult captureText(String? raw, {int max = 20000}) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) {
      return const ValidationResult.invalid(
        ValidationIssue.required,
        'Write something to remember.',
      );
    }
    if (value.length > max) {
      return ValidationResult.invalid(
        ValidationIssue.tooLong,
        'That is longer than $max characters.',
      );
    }
    return _valid;
  }

  static bool _looksLikeUrl(String value) {
    final lowered = value.toLowerCase();
    return lowered.contains('://') ||
        lowered.contains('www.') ||
        RegExp(r'\b[\w-]+\.(com|net|org|io|co|ru|xyz)\b').hasMatch(lowered);
  }
}
