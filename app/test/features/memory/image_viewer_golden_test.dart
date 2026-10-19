import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/app/theme/app_theme.dart';
import 'package:knowra/src/core/di/injector.dart';
import 'package:knowra/src/core/feedback/snack_controller.dart';
import 'package:knowra/src/core/files/original_access.dart';
import 'package:knowra/src/features/memory/domain/entities/memory.dart';
import 'package:knowra/src/features/memory/domain/entities/memory_enums.dart';
import 'package:knowra/src/features/memory/domain/repositories/memory_repository.dart';
import 'package:knowra/src/features/memory/domain/usecases/memory_usecases.dart';
import 'package:knowra/src/features/memory/presentation/bloc/file_viewer_cubit.dart';
import 'package:knowra/src/features/memory/presentation/pages/file_viewer_page.dart';

import '../../support/load_app_fonts.dart';

/// A 600×400 picture — landscape, so a viewer that forced it into a page
/// shape would be caught.
final _photo = File('test/fixtures/photo_landscape.png');

Memory _memory({String? text}) => Memory(
  id: 'm1',
  type: MemoryType.photo,
  status: ProcessingStatus.ready,
  title: 'whiteboard-tiers.jpg',
  text: text,
  createdAt: DateTime(2026, 8, 24, 10),
);

class _Memories extends Fake implements MemoryRepository {
  _Memories(this.memory);
  final Memory memory;

  @override
  Future<Memory> fetchMemory(String id) async => memory;
}

/// The photo is on this phone.
class _Access extends Fake implements OriginalAccess {
  @override
  Future<OriginalHandle> resolve({
    required String memoryId,
    String? url,
    String? storagePath,
    String? filename,
  }) async => OriginalOnDevice(_photo);
}

/// Screen 2I — the photo at its own shape on a dark stage, never on a page.
void main() {
  setUpAll(loadAppFonts);
  setUp(() {
    getIt
      ..registerSingleton<OriginalAccess>(_Access())
      ..registerSingleton<SnackController>(SnackController());
  });
  tearDown(() => getIt.reset(dispose: false));

  Future<void> pump(WidgetTester tester, Memory memory) async {
    tester.view
      ..physicalSize = const Size(402, 874)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repo = _Memories(memory);
    final cubit = FileViewerCubit(GetMemory(repo), 'm1');
    addTearDown(cubit.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        debugShowCheckedModeBanner: false,
        home: BlocProvider.value(value: cubit, child: const FileViewerPage()),
      ),
    );
    // The file is decoded off the test's fake clock. Once it is in the
    // image cache the widget's own `Image` resolves it synchronously.
    await tester.runAsync(
      () => precacheImage(
        FileImage(_photo),
        tester.element(find.byType(MaterialApp)),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('a photo with text read from it', (tester) async {
    await pump(
      tester,
      _memory(
        text:
            'TIERS — solo \$12 · team \$29/seat · scale quote · floor 40k, '
            'check w/ finance',
      ),
    );

    expect(tester.takeException(), isNull);
    // 2I's header line, not the document viewer's page marker.
    expect(find.text('24 AUG · PHOTO · ON DEVICE'), findsOneWidget);
    expect(find.textContaining('PAGE 1 OF'), findsNothing);
    expect(find.text('TEXT READ FROM THIS IMAGE'), findsOneWidget);

    // The picture keeps its own 3:2 — not stretched to a page, not boxed.
    final size = tester.getSize(find.byType(Image));
    expect(size.width / size.height, closeTo(1.5, 0.02));

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/image_viewer_2i.png'),
    );
  });

  testWidgets('a photo with nothing to read gets the stage alone', (
    tester,
  ) async {
    await pump(tester, _memory());

    expect(tester.takeException(), isNull);
    expect(find.text('TEXT READ FROM THIS IMAGE'), findsNothing);
    // Neither apology the paper viewer printed under a picture.
    expect(find.textContaining('Nothing readable'), findsNothing);
    expect(find.textContaining('No text was found'), findsNothing);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/image_viewer_2i_plain.png'),
    );
  });

  test(
    'the fixture is landscape, so the ratio check means something',
    () async {
      final bytes = await _photo.readAsBytes();
      final image = await decodeImageFromList(bytes);
      expect(image.width, 600);
      expect(image.height, 400);
      image.dispose();
    },
  );
}
