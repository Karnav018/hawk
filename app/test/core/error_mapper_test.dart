import 'dart:async' as async;
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/core/error/app_exception.dart';
import 'package:knowra/src/core/error/error_mapper.dart';

void main() {
  group('ErrorMapper', () {
    test('maps socket exceptions to network', () {
      expect(
        ErrorMapper.map(const SocketException('down')),
        isA<NetworkException>(),
      );
    });

    test('maps timeouts', () {
      expect(
        ErrorMapper.map(async.TimeoutException('slow')),
        isA<TimeoutException>(),
      );
    });

    test('maps decode failures to parsing', () {
      expect(
        ErrorMapper.map(const FormatException('not json')),
        isA<ParsingException>(),
      );
      // A bad cast out of a Firestore document is a TypeError, not a
      // FormatException, but it means the same thing to the user.
      expect(ErrorMapper.map(TypeError()), isA<ParsingException>());
    });

    test('keeps the cause and stack trace on an unrecognised error', () {
      final cause = StateError('boom');
      final stack = StackTrace.current;
      final result = ErrorMapper.map(cause, stack);
      expect(result, isA<UnknownException>());
      expect((result as UnknownException).cause, same(cause));
      expect(result.stackTrace, same(stack));
    });

    test('is idempotent for an already-mapped exception', () {
      const original = AppException.notFound();
      expect(ErrorMapper.map(original), same(original));
    });
  });
}
