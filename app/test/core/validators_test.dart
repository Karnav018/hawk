import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/core/validation/validators.dart';

void main() {
  group('email', () {
    test('accepts addresses a strict regex would wrongly reject', () {
      // Every one of these is valid, and every one is rejected by some
      // popular "email regex". Refusing a real address is worse than one
      // round trip, because the user has no way to argue with it.
      const valid = [
        'sam@northwind.co',
        'sam.kaur@northwind.co.uk',
        'sam+vault@northwind.co',
        "o'brien@northwind.ie",
        'sam_kaur@sub.domain.example',
        'sam-kaur@north-wind.co',
        '123@456.com',
        'a@b.co',
        'user%name@example.com',
        'sam!#\$%&*@example.com',
      ];
      for (final address in valid) {
        expect(
          Validators.email(address).isValid,
          isTrue,
          reason: 'should accept $address',
        );
      }
    });

    test('rejects the shapes a typo actually produces', () {
      const invalid = {
        '': ValidationIssue.required,
        '   ': ValidationIssue.required,
        'sam': ValidationIssue.malformedEmail,
        'sam@': ValidationIssue.malformedEmail,
        '@northwind.co': ValidationIssue.malformedEmail,
        'sam@northwind': ValidationIssue.malformedEmail,
        'sam@northwind.': ValidationIssue.malformedEmail,
        'sam@.co': ValidationIssue.malformedEmail,
        'sam@north..wind.co': ValidationIssue.malformedEmail,
        'sam@@northwind.co': ValidationIssue.malformedEmail,
        'sam kaur@northwind.co': ValidationIssue.malformedEmail,
        'sam@-northwind.co': ValidationIssue.malformedEmail,
      };
      invalid.forEach((address, issue) {
        final result = Validators.email(address);
        expect(result.isValid, isFalse, reason: 'should reject "$address"');
        expect(result.issue, issue, reason: address);
        expect(result.message, isNotEmpty);
      });
    });

    test('rejects addresses over the RFC length limits', () {
      expect(
        Validators.email('${'a' * 65}@example.com').issue,
        ValidationIssue.tooLong,
      );
      expect(
        Validators.email('a@${'b' * 400}.com').issue,
        ValidationIssue.tooLong,
      );
    });

    test('surrounding whitespace is forgiven, not rejected', () {
      expect(Validators.email('  sam@northwind.co  ').isValid, isTrue);
    });
  });

  group('email typo suggestions', () {
    test('catches a one-character slip in a common provider', () {
      expect(
        Validators.emailDomainSuggestion('sam@gmial.com'),
        'sam@gmail.com',
      );
      expect(
        Validators.emailDomainSuggestion('sam@outlok.com'),
        'sam@outlook.com',
      );
      expect(
        Validators.emailDomainSuggestion('sam@icloud.co'),
        'sam@icloud.com',
      );
    });

    test('says nothing about a correct address', () {
      expect(Validators.emailDomainSuggestion('sam@gmail.com'), isNull);
    });

    test('says nothing about an unrelated domain', () {
      // Somebody's real company domain must not be second-guessed.
      expect(Validators.emailDomainSuggestion('sam@northwind.co'), isNull);
      expect(Validators.emailDomainSuggestion('sam@anthropic.com'), isNull);
    });

    test('does not guess when the distance is more than one', () {
      expect(Validators.emailDomainSuggestion('sam@gmil.co'), isNull);
    });

    test('catches transpositions, the commonest typo of all', () {
      // Plain Levenshtein scores an adjacent swap as 2 and would never
      // suggest these — which would miss the single most common way people
      // mistype `gmail`.
      expect(
        Validators.emailDomainSuggestion('sam@gmial.com'),
        'sam@gmail.com',
      );
      expect(
        Validators.emailDomainSuggestion('sam@hotmial.com'),
        'sam@hotmail.com',
      );
      expect(
        Validators.emailDomainSuggestion('sam@yahooo.com'),
        'sam@yahoo.com',
      );
    });
  });

  group('verification code', () {
    test('accepts exactly six digits', () {
      expect(Validators.verificationCode('419372').isValid, isTrue);
      expect(Validators.verificationCode('000000').isValid, isTrue);
    });

    test('rejects anything else', () {
      for (final bad in [
        '',
        '41937',
        '4193725',
        'abcdef',
        '41 93 72',
        '4193-72',
      ]) {
        expect(
          Validators.verificationCode(bad).isValid,
          isFalse,
          reason: 'should reject "$bad"',
        );
      }
    });
  });

  group('display name', () {
    test('is optional', () {
      // The server accepts null; demanding one here only collects junk.
      expect(Validators.displayName('').isValid, isTrue);
      expect(Validators.displayName(null).isValid, isTrue);
      expect(Validators.displayName('   ').isValid, isTrue);
    });

    test('accepts real names, including ones ASCII rules break', () {
      for (final name in [
        'Sam Kaur',
        "O'Brien",
        'Jean-Luc',
        '李雷',
        'Ólafur Arnalds',
        'María José',
      ]) {
        expect(
          Validators.displayName(name).isValid,
          isTrue,
          reason: 'should accept $name',
        );
      }
    });

    test('rejects links, which are spam rather than names', () {
      for (final spam in [
        'http://spam.example',
        'www.spam.example',
        'Buy now at spam.com',
      ]) {
        expect(Validators.displayName(spam).issue, ValidationIssue.containsUrl);
      }
    });

    test('rejects an unreasonably long name', () {
      expect(Validators.displayName('a' * 200).issue, ValidationIssue.tooLong);
    });
  });

  group('capture url', () {
    test('accepts what a person actually pastes', () {
      for (final url in [
        'https://example.com',
        'http://example.com/path?q=1#frag',
        'example.com',
        'sub.example.co.uk/deep/path',
        'https://example.com:8443/x',
      ]) {
        expect(
          Validators.captureUrl(url).isValid,
          isTrue,
          reason: 'should accept $url',
        );
      }
    });

    test('rejects non-links and unsupported schemes', () {
      for (final bad in [
        '',
        'not a url',
        'ftp://example.com',
        'javascript:x',
      ]) {
        expect(
          Validators.captureUrl(bad).isValid,
          isFalse,
          reason: 'should reject "$bad"',
        );
      }
    });

    test('adds the scheme people leave off', () {
      expect(Validators.normalizeUrl('example.com'), 'https://example.com');
      expect(
        Validators.normalizeUrl('http://example.com'),
        'http://example.com',
      );
      expect(Validators.normalizeUrl('  '), isNull);
    });
  });

  group('capture text', () {
    test('requires something', () {
      expect(Validators.captureText('  ').issue, ValidationIssue.required);
    });

    test('accepts a long note but not an unbounded one', () {
      expect(Validators.captureText('a' * 19999).isValid, isTrue);
      expect(
        Validators.captureText('a' * 20001).issue,
        ValidationIssue.tooLong,
      );
    });
  });
}
