import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/app/theme/app_palette.dart';
import 'package:knowra/src/app/theme/app_theme.dart';
import 'package:knowra/src/core/feedback/snack_controller.dart';
import 'package:knowra/src/core/files/local_originals.dart';
import 'package:knowra/src/core/logging/app_logger.dart';
import 'package:knowra/src/features/capture/data/file_capture.dart';
import 'package:knowra/src/features/capture/data/network_status.dart';
import 'package:knowra/src/features/capture/presentation/bloc/capture_cubit.dart';
import 'package:knowra/src/features/capture/presentation/bloc/upload_center.dart';
import 'package:knowra/src/features/capture/presentation/bloc/upload_intake.dart';
import 'package:knowra/src/features/capture/presentation/pages/indexing_page.dart';
import 'package:knowra/src/features/capture/presentation/widgets/upload_sheets.dart';
import 'package:knowra/src/features/memory/domain/entities/memory.dart';
import 'package:knowra/src/features/memory/domain/entities/memory_enums.dart';
import 'package:knowra/src/features/memory/domain/repositories/memory_repository.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/load_app_fonts.dart';

const _designSize = Size(402, 874);
const _mb = 1024 * 1024;

class _Files extends Fake implements FileCapture {}

class _Network implements NetworkStatus {
  @override
  Future<bool> isOnline() async => true;

  @override
  Stream<bool> get changes => const Stream.empty();
}

class _Memories extends Fake implements MemoryRepository {}

class _Originals extends Fake implements LocalOriginals {}

class _Logger extends Mock implements AppLogger {}

class _Navigator implements UploadNavigator {
  @override
  void openBatch(String batchId) {}

  @override
  void ask() {}
}

/// A center whose state the test sets outright. The run itself is covered
/// by `upload_center_test.dart`; these are pictures of where it can be.
///
/// Seeded rather than driven: the run's awaits resolve partly in the root
/// zone, which a widget test's fake clock never advances, so a driven run
/// stalls halfway here while working fine on a device.
class _Seeded extends UploadCenter {
  _Seeded()
    : super(
        _Files(),
        _Memories(),
        _Originals(),
        _Network(),
        SnackController(),
        _Navigator(),
        _Logger(),
      );

  void seed(List<UploadJob> jobs) => emit(UploadCenterState(jobs: jobs));
}

UploadJob _job(
  String name, {
  int bytes = (2.4 * _mb) ~/ 1,
  CaptureKind kind = CaptureKind.files,
  UploadPhase phase = UploadPhase.uploading,
  int sent = 0,
  ProcessingStatus? status,
  String? problem,
  int n = 0,
}) => UploadJob(
  id: 'j$n',
  batchId: 'b',
  kind: kind,
  file: (path: '/c/$name', name: name, bytes: bytes),
  addedAt: DateTime(2026, 9, 26, 9, 41),
  phase: phase,
  sent: sent,
  problem: problem,
  memory: status == null
      ? null
      : Memory(
          id: 'm$n',
          type: kind == CaptureKind.images ? MemoryType.photo : MemoryType.pdf,
          status: status,
          createdAt: DateTime(2026, 9, 26, 9, 41),
          title: name,
        ),
);

/// The Upload flow's new screens, on the real ground with the real fonts —
/// the pictures to hold against `Hawk Library.dc.html`.
void main() {
  setUpAll(loadAppFonts);

  late _Seeded center;

  setUp(() => center = _Seeded());
  tearDown(() => center.close());

  Future<void> shoot(WidgetTester tester, Widget home, String golden) async {
    tester.view
      ..physicalSize = _designSize
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        debugShowCheckedModeBanner: false,
        home: home,
      ),
    );
    // Not settle: an active step spins for as long as it is active.
    await tester.pump(const Duration(milliseconds: 400));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/$golden.png'),
    );
    // Leaving a finished batch announces it (F1·7); let that island's hold
    // run out rather than leave its timer behind.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  }

  Widget page() => BlocProvider<UploadCenter>.value(
    value: center,
    child: const IndexingPage(batchId: 'b'),
  );

  testWidgets('F1·2 — what are you adding?', (tester) async {
    await shoot(
      tester,
      Scaffold(
        backgroundColor: AppPalette.dark.ground,
        body: Align(
          alignment: Alignment.bottomCenter,
          child: TypeSheet(onPick: (_) async => const IntakeCancelled()),
        ),
      ),
      'type_sheet_f1_2',
    );
  });

  testWidgets('F1·4 — uploading', (tester) async {
    center.seed([_job('Lease agreement 2026.pdf', sent: _mb)]);
    await shoot(tester, page(), 'indexing_f1_4');
  });

  testWidgets('F1·5 — reading', (tester) async {
    center.seed([
      _job(
        'Lease agreement 2026.pdf',
        phase: UploadPhase.saved,
        status: ProcessingStatus.processing,
      ),
    ]);
    await shoot(tester, page(), 'indexing_f1_5');
  });

  testWidgets('F1·6 — ready', (tester) async {
    center.seed([
      _job(
        'Lease agreement 2026.pdf',
        phase: UploadPhase.saved,
        status: ProcessingStatus.ready,
      ),
    ]);
    await shoot(tester, page(), 'indexing_f1_6');
  });

  testWidgets('E6 — upload stopped', (tester) async {
    center.seed([
      _job(
        'Lease agreement 2026.pdf',
        phase: UploadPhase.stopped,
        sent: _mb,
        problem: 'Connection dropped at 1.0 MB',
      ),
    ]);
    await shoot(tester, page(), 'indexing_e6');
  });

  testWidgets('F3·4 — a batch of images', (tester) async {
    center.seed(
      [
        _job(
          'IMG_5102.heic',
          kind: CaptureKind.images,
          bytes: (3.1 * _mb) ~/ 1,
          phase: UploadPhase.saved,
          status: ProcessingStatus.ready,
        ),
        _job(
          'IMG_5103.heic',
          kind: CaptureKind.images,
          bytes: (2.8 * _mb) ~/ 1,
          phase: UploadPhase.saved,
          status: ProcessingStatus.ready,
          n: 1,
        ),
        _job(
          'IMG_5104.heic',
          kind: CaptureKind.images,
          bytes: (2.9 * _mb) ~/ 1,
          phase: UploadPhase.saved,
          status: ProcessingStatus.processing,
          n: 2,
        ),
        _job(
          'IMG_5105.heic',
          kind: CaptureKind.images,
          bytes: (3.4 * _mb) ~/ 1,
          sent: _mb,
          n: 3,
        ),
        // Newest first, as the center keeps them.
      ].reversed.toList(),
    );
    await shoot(tester, page(), 'indexing_f3_4');
  });
}
