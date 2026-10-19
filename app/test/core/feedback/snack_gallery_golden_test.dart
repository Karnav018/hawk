import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/app/theme/app_palette.dart';
import 'package:knowra/src/app/theme/app_theme.dart';
import 'package:knowra/src/core/feedback/snack.dart';
import 'package:knowra/src/core/feedback/snack_controller.dart';
import 'package:knowra/src/core/feedback/snack_host.dart';
import 'package:knowra/src/core/feedback/widgets/snack_views.dart';

import '../../support/load_app_fonts.dart';

/// `Hawk Snackbars.dc.html` section 2 — the five types, with the design's
/// own sample copy, resting where the host puts them: 8px under a Dynamic
/// Island's safe area.
final _types = <String, Snack>{
  '2a_confirmation': const Snack.confirmation(
    message: 'Saved — reading it now',
  ),
  '2b_detail': const Snack.detail(
    title: 'Could not connect',
    subtitle: "Google Drive didn't respond. Try again in a moment.",
    mark: SnackMark.failure,
  ),
  '2c_progress': const Snack.progress(
    message: 'Indexing 24 files',
    fraction: 0.62,
  ),
  '2d_assistant': Snack.assistant(
    message: 'Found 3 new photos from Tahoe',
    onOpen: () {},
  ),
  '2e_undo': Snack.undo(message: 'Memory removed', onUndo: () {}),
};

void main() {
  setUpAll(loadAppFonts);

  for (final MapEntry(key: name, value: snack) in _types.entries) {
    testWidgets('$name — top island', (tester) async {
      tester.view
        ..physicalSize = const Size(402, 176)
        ..devicePixelRatio = 1.0
        // An island iPhone's status-bar inset.
        ..padding = const FakeViewPadding(top: 59);
      addTearDown(tester.view.reset);
      await precacheAppImages(tester);

      final controller = SnackController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          debugShowCheckedModeBanner: false,
          builder: (context, child) =>
              SnackHost(controller: controller, island: true, child: child!),
          home: Builder(
            builder: (context) => ColoredBox(color: context.palette.ground),
          ),
        ),
      );
      controller.show(snack);
      // Past the 500ms entrance, well inside the 4s hold.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/snack_$name.png'),
      );
      controller.dismiss();
      await tester.pump(const Duration(seconds: 1));
    });
  }

  testWidgets('every detail mark — the catalogue', (tester) async {
    tester.view
      ..physicalSize = const Size(402, 470)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    const details = [
      Snack.detail(
        title: 'Could not save that link',
        subtitle: 'That page blocks readers. Save it as a PDF instead.',
        mark: SnackMark.failure,
      ),
      Snack.detail(
        title: 'Nothing here can open it',
        subtitle: 'Install an app for this kind of file, or share it instead.',
      ),
      Snack.detail(
        title: 'Tax_Return_2023.pdf',
        subtitle: 'The original is not on this phone.',
        mark: SnackMark.file,
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        debugShowCheckedModeBanner: false,
        home: Builder(
          // Inside a Material, as the host provides one in the app.
          builder: (context) => Material(
            color: context.palette.ground,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              children: [
                for (final snack in details) ...[
                  SnackView(snack: snack, onDismiss: () {}),
                  const SizedBox(height: 14),
                ],
                SnackView(
                  snack: Snack.detail(
                    title: 'Saved — goes dormant in 14 days',
                    subtitle: 'Free plan memory window',
                    mark: SnackMark.clock,
                    action: SnackAction(
                      label: 'Keep',
                      onPressed: () {},
                      style: SnackActionStyle.text,
                    ),
                  ),
                  onDismiss: () {},
                ),
                const SizedBox(height: 14),
                const SnackView(
                  snack: Snack.detail(
                    title: 'Fetching Lake_Tahoe_Grandma.jpg',
                    subtitle: 'Downloading it from your vault',
                    mark: SnackMark.busy,
                  ),
                  onDismiss: _noop,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/snack_catalogue.png'),
    );
  });
}

void _noop() {}
