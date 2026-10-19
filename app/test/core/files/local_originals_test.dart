import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/core/files/local_originals.dart';
import 'package:path/path.dart' as p;

/// The phone's kept copy of each captured file.
///
/// Run against the real filesystem in a temporary directory: the behaviour
/// that matters — a move rather than a copy, and a name that cannot escape
/// its folder — is a filesystem behaviour, and a fake would only restate it.
void main() {
  late Directory root;
  late SandboxOriginals originals;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('originals_test');
    originals = SandboxOriginals.at(root);
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  /// A file standing in for the picker's cache copy.
  Future<File> picked(String name, String content) async {
    final cache = Directory(p.join(root.path, 'cache'));
    await cache.create(recursive: true);
    return File(p.join(cache.path, name))..writeAsStringSync(content);
  }

  test('keeps the file under its memory, with its own name', () async {
    final source = await picked('tmp-8812.pdf', 'pricing');

    final kept = await originals.keep(
      memoryId: 'm1',
      sourcePath: source.path,
      filename: 'Pricing schedule v4.pdf',
    );

    // The name the user chose survives: it is what a viewer shows in its
    // title bar and what the recipient of a share receives.
    expect(p.basename(kept.path), 'Pricing schedule v4.pdf');
    expect(kept.readAsStringSync(), 'pricing');
  });

  test('moves rather than copies — no second set of bytes', () async {
    final source = await picked('tmp.jpg', 'photo');

    await originals.keep(
      memoryId: 'm1',
      sourcePath: source.path,
      filename: 'IMG_0111.jpg',
    );

    // The picker already copied the file into the sandbox. Keeping it must
    // not copy it a second time, or every capture costs its size twice.
    expect(source.existsSync(), isFalse);
  });

  test('finds what it kept, and nothing for a memory it never had', () async {
    final source = await picked('tmp.txt', 'note');
    await originals.keep(
      memoryId: 'm1',
      sourcePath: source.path,
      filename: 'a.txt',
    );

    expect((await originals.find('m1'))?.readAsStringSync(), 'note');
    // Captured on another phone, or before originals were kept.
    expect(await originals.find('m-elsewhere'), isNull);
  });

  test('forget removes the copy, and is safe to repeat', () async {
    final source = await picked('tmp.txt', 'note');
    await originals.keep(
      memoryId: 'm1',
      sourcePath: source.path,
      filename: 'a.txt',
    );

    await originals.forget('m1');
    expect(await originals.find('m1'), isNull);

    // A second delete — or one for a memory with no copy — is not an error.
    await originals.forget('m1');
    await originals.forget('never-kept');
  });

  test('a filename cannot escape its folder', () async {
    final source = await picked('tmp.txt', 'x');

    final kept = await originals.keep(
      memoryId: 'm1',
      sourcePath: source.path,
      filename: '../../../escape.txt',
    );

    // The name arrives as data from the picker. A path built from data is
    // sanitised, or a crafted name writes outside `originals/`.
    expect(
      p.isWithin(p.join(root.path, 'originals', 'm1'), kept.path),
      isTrue,
      reason: 'kept at ${kept.path}',
    );
  });

  test('a memory id cannot escape its folder either', () async {
    final source = await picked('tmp.txt', 'x');

    final kept = await originals.keep(
      memoryId: '../../outside',
      sourcePath: source.path,
      filename: 'a.txt',
    );

    expect(
      p.isWithin(p.join(root.path, 'originals'), kept.path),
      isTrue,
      reason: 'kept at ${kept.path}',
    );
  });
}
