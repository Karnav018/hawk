import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/core/files/local_originals.dart';
import 'package:knowra/src/core/files/original_access.dart';
import 'package:knowra/src/core/logging/app_logger.dart';

class _FakeOriginals implements LocalOriginals {
  _FakeOriginals([this.files = const {}]);
  final Map<String, File> files;

  @override
  Future<File?> find(String memoryId) async => files[memoryId];

  @override
  Future<File> keep({
    required String memoryId,
    required String sourcePath,
    required String filename,
  }) => throw UnimplementedError();

  @override
  Future<void> forget(String memoryId) async {}

  @override
  Future<File> destination({
    required String memoryId,
    required String filename,
  }) async => File('/tmp/$memoryId/$filename');
}

class _FakeLogger implements AppLogger {
  @override
  void noSuchMethod(Invocation invocation) {}
}

/// Which original a memory resolves to, and in what order.
void main() {
  // Storage is never reached by `resolve`, which is all these exercise —
  // fetching is covered on a device, not here.
  final noStorage = _UnusedStorage();

  test('a file on this phone wins over a url', () async {
    // The kept file is the real thing, works offline, and opens in the app
    // the user already reads that kind of file in.
    final file = File('/tmp/kept.pdf');
    final access = NativeOriginalAccess(
      _FakeOriginals({'m1': file}),
      noStorage,
      _FakeLogger(),
    );

    final handle = await access.resolve(
      memoryId: 'm1',
      url: 'https://example.com/a.pdf',
    );

    expect(handle, isA<OriginalOnDevice>());
    expect((handle as OriginalOnDevice).file, same(file));
  });

  test('a link or a Drive file resolves to its url', () async {
    final access = NativeOriginalAccess(
      _FakeOriginals(),
      noStorage,
      _FakeLogger(),
    );

    final handle = await access.resolve(
      memoryId: 'm1',
      url: 'https://drive.google.com/file/d/abc/view',
    );

    expect(handle, isA<OriginalAtUrl>());
    expect((handle as OriginalAtUrl).uri.host, 'drive.google.com');
  });

  test('only web urls are handed to the OS', () async {
    // A memory's url is user- or connector-supplied data. Passing an
    // arbitrary scheme to the OS is how an app launches something nobody
    // meant it to.
    final access = NativeOriginalAccess(
      _FakeOriginals(),
      noStorage,
      _FakeLogger(),
    );

    for (final url in [
      'file:///data/data/com.other/secret',
      'javascript:alert(1)',
      'intent://scan/#Intent;scheme=zxing;end',
      'tel:+15555550100',
      '',
      '   ',
      'not a url',
    ]) {
      expect(
        await access.resolve(memoryId: 'm1', url: url),
        isA<OriginalUnavailable>(),
        reason: url,
      );
    }
  });

  test('neither file nor url is unavailable, not an error', () async {
    final access = NativeOriginalAccess(
      _FakeOriginals(),
      noStorage,
      _FakeLogger(),
    );
    expect(await access.resolve(memoryId: 'm1'), isA<OriginalUnavailable>());
  });

  test('opening an unavailable original reports it, without the OS', () async {
    final access = NativeOriginalAccess(
      _FakeOriginals(),
      noStorage,
      _FakeLogger(),
    );
    expect(
      await access.open(const OriginalUnavailable()),
      OpenOutcome.unavailable,
    );
  });

  test('a kept file deleted since it was found is reported missing', () async {
    final access = NativeOriginalAccess(
      _FakeOriginals(),
      noStorage,
      _FakeLogger(),
    );
    expect(
      await access.open(OriginalOnDevice(File('/definitely/not/here.pdf'))),
      OpenOutcome.missing,
    );
  });

  test('a kept file resolves to the vault when this phone lacks it', () async {
    // The case that makes this a vault rather than an index: captured on a
    // phone that was since lost, or on another device entirely.
    final access = NativeOriginalAccess(
      _FakeOriginals(),
      noStorage,
      _FakeLogger(),
    );

    final handle = await access.resolve(
      memoryId: 'm1',
      storagePath: 'users/u1/originals/m1/Pricing v4.pdf',
      filename: 'Pricing v4.pdf',
    );

    expect(handle, isA<OriginalInVault>());
    expect(
      (handle as OriginalInVault).storagePath,
      'users/u1/originals/m1/Pricing v4.pdf',
    );
  });

  test('a file already on this phone beats the vault copy', () async {
    // Instant, offline, and no data spent re-downloading what is here.
    final file = File('/tmp/kept.pdf');
    final access = NativeOriginalAccess(
      _FakeOriginals({'m1': file}),
      noStorage,
      _FakeLogger(),
    );

    final handle = await access.resolve(
      memoryId: 'm1',
      storagePath: 'users/u1/originals/m1/kept.pdf',
    );

    expect(handle, isA<OriginalOnDevice>());
  });

  test('a vault handle falls back to its object name when unnamed', () async {
    final access = NativeOriginalAccess(
      _FakeOriginals(),
      noStorage,
      _FakeLogger(),
    );

    final handle = await access.resolve(
      memoryId: 'm1',
      storagePath: 'users/u1/originals/m1/Pricing v4.pdf',
      filename: '   ',
    );

    expect((handle as OriginalInVault).filename, 'Pricing v4.pdf');
  });

  test('opening a vault handle directly reports it unreachable', () async {
    // `openOriginal` fetches first; reaching `open` with a vault handle
    // means the fetch was skipped or failed, and waiting is the remedy.
    final access = NativeOriginalAccess(
      _FakeOriginals(),
      noStorage,
      _FakeLogger(),
    );

    expect(
      await access.open(const OriginalInVault(storagePath: 'p', filename: 'f')),
      OpenOutcome.unreachable,
    );
  });

  test('with nothing at all to share, nothing is shared', () async {
    // share_plus throws on empty text, so this has to be caught before the
    // platform call rather than after it.
    final access = NativeOriginalAccess(
      _FakeOriginals(),
      noStorage,
      _FakeLogger(),
    );
    expect(
      await access.share(const OriginalUnavailable(), title: '   '),
      isFalse,
    );
  });
}

/// Stands in for Firebase Storage. Any call is a bug in the test.
class _UnusedStorage implements FirebaseStorage {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('storage must not be touched by resolve()');
}
