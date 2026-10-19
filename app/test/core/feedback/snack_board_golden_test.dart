import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/app/theme/app_palette.dart';
import 'package:knowra/src/app/theme/app_theme.dart';
import 'package:knowra/src/app/theme/app_typography.dart';
import 'package:knowra/src/core/feedback/snack.dart';
import 'package:knowra/src/core/feedback/widgets/snack_views.dart';

import '../../support/load_app_fonts.dart';

/// One snack the app fires, where from, and when.
typedef _Entry = ({String site, Snack snack});

void _noop() {}

const _offlineCause = 'You’re offline. Check your connection and try again.';

/// Every snack in the app, as of the Library redesign — the board from
/// `Hawk Snackbars.dc.html` §2 "Every snack in the app", rebuilt from the
/// real call sites and drawn by the real [SnackView]. Error subtitles come
/// from `error.displayMessage` at runtime; the ones here are the design's
/// representative ones.
final _board = <String, List<_Entry>>{
  'capture': [
    (
      site: 'capture_page · link saved',
      snack: const Snack.confirmation(message: 'Saved — reading it now'),
    ),
    (
      site: 'capture_page · saved on a plan window',
      snack: const Snack.detail(
        title: 'Saved — goes dormant in 14 days',
        subtitle: 'Free plan memory window',
        mark: SnackMark.clock,
        action: SnackAction(
          label: 'Keep',
          style: SnackActionStyle.text,
          onPressed: _noop,
        ),
      ),
    ),
    (
      site: 'capture_page · save failed',
      snack: const Snack.detail(
        title: 'Could not save that link',
        subtitle: _offlineCause,
        mark: SnackMark.failure,
      ),
    ),
    (
      site: 'upload_center · link page refused',
      snack: const Snack.detail(
        title: 'Could not save that link',
        subtitle: 'That page blocks readers. Save it as a PDF instead.',
        mark: SnackMark.failure,
      ),
    ),
    (
      site: 'speak_capture_page · saved',
      snack: const Snack.confirmation(message: 'Saved — transcribing it now'),
    ),
    (
      site: 'speak_capture_page · nothing heard',
      snack: const Snack.detail(
        title: 'Nothing was heard',
        subtitle: 'Nothing saved. Try again a little closer.',
      ),
    ),
    (
      site: 'speak_capture_page · error',
      snack: const Snack.detail(
        title: 'Could not save',
        subtitle: 'The recording was too short to keep.',
        mark: SnackMark.failure,
      ),
    ),
    (
      site: 'home_page · camera error',
      snack: const Snack.detail(
        title: 'Could not save that photo',
        subtitle: _offlineCause,
        mark: SnackMark.failure,
      ),
    ),
  ],
  'upload': [
    (
      site: 'upload_center · working, screen left',
      snack: const Snack.progress(message: 'Indexing 1 file', fraction: 0.64),
    ),
    (
      site: 'upload_center · recording, screen left',
      snack: const Snack.progress(
        message: 'Transcribing 1 file',
        fraction: 0.36,
      ),
    ),
    (
      site: 'upload_center · batch left mid-way',
      snack: const Snack.confirmation(
        message: 'Saved 4 files — reading them now',
      ),
    ),
    (
      site: 'upload_center · landed away',
      snack: const Snack.confirmation(
        message: 'Ready to ask',
        action: SnackAction(
          label: 'Ask',
          style: SnackActionStyle.text,
          onPressed: _noop,
        ),
      ),
    ),
    (
      site: 'upload_center · batch landed away',
      snack: const Snack.confirmation(
        message: '4 files ready to ask',
        action: SnackAction(
          label: 'Ask',
          style: SnackActionStyle.text,
          onPressed: _noop,
        ),
      ),
    ),
    (
      site: 'upload_center · finished screen left',
      snack: const Snack.confirmation(
        message: 'Lease agreement 2026.pdf is ready',
      ),
    ),
    (
      site: 'upload_center · offline',
      snack: const Snack.detail(
        title: 'You’re offline',
        subtitle: 'We’ll upload it as soon as you’re back.',
        mark: SnackMark.offline,
      ),
    ),
    (
      site: 'upload_center · failed away',
      snack: const Snack.detail(
        title: 'Couldn’t add Lease agreement 2026.pdf',
        subtitle: 'Connection dropped at 1.0 MB',
        mark: SnackMark.failure,
        action: SnackAction(
          label: 'Open',
          style: SnackActionStyle.text,
          onPressed: _noop,
        ),
      ),
    ),
    (
      site: 'upload_center · partly read',
      snack: const Snack.detail(
        title: 'Saved — some pages unreadable',
        subtitle: '3 of 12 pages had no readable text',
        mark: SnackMark.file,
      ),
    ),
    (
      site: 'upload_center · retry error',
      snack: const Snack.detail(
        title: 'Could not try again',
        subtitle: _offlineCause,
        mark: SnackMark.failure,
      ),
    ),
  ],
  'upload_checks': [
    (
      site: 'upload_flow · type Hawk can’t read',
      snack: const Snack.detail(
        title: 'Can’t read .pages files',
        subtitle: 'Export it as PDF, then upload that.',
        mark: SnackMark.failure,
      ),
    ),
    (
      site: 'upload_flow · some of a batch left out',
      snack: const Snack.detail(
        title: 'Left out 1 of 5',
        subtitle:
            'Too big, already in your Library, or a type Hawk can’t read.',
      ),
    ),
    (
      site: 'upload_flow · nothing added',
      snack: const Snack.detail(
        title: 'Nothing added',
        subtitle:
            'All 2 were too big, already kept, or a type Hawk can’t read.',
        mark: SnackMark.failure,
      ),
    ),
    (
      site: 'upload_flow · images error',
      snack: const Snack.detail(
        title: 'Could not add those images',
        subtitle: _offlineCause,
        mark: SnackMark.failure,
      ),
    ),
    (
      site: 'upload_flow · save error',
      snack: const Snack.detail(
        title: 'Could not save',
        subtitle: 'Your vault is full. Free up space or go Pro.',
        mark: SnackMark.failure,
      ),
    ),
  ],
  'files': [
    (
      site: 'original_actions · fetching',
      snack: const Snack.detail(
        title: 'Fetching Lake_Tahoe_Grandma.jpg',
        subtitle: 'Downloading it from your vault',
        mark: SnackMark.busy,
      ),
    ),
    (
      site: 'original_actions · noApp',
      snack: const Snack.detail(
        title: 'Nothing here can open it',
        subtitle: 'Install an app for this kind of file, or share it instead.',
      ),
    ),
    (
      site: 'original_actions · missing',
      snack: const Snack.detail(
        title: 'The file is no longer on this phone',
        subtitle:
            'Its memory is still searchable. Capture it again to reopen it.',
      ),
    ),
    (
      site: 'original_actions · unavailable',
      snack: const Snack.detail(
        title: 'Tax_Return_2023.pdf',
        subtitle:
            'The original is not on this phone — it was captured on another '
            'device or before Hawk kept files.',
        mark: SnackMark.file,
      ),
    ),
    (
      site: 'original_actions · unreachable',
      snack: const Snack.detail(
        title: 'Could not fetch it',
        subtitle:
            'Your file is in the vault. Check your connection and try again.',
        mark: SnackMark.failure,
      ),
    ),
    (
      site: 'original_actions · failed',
      snack: const Snack.detail(
        title: 'Could not open it',
        subtitle: 'Lake_Tahoe_Grandma.jpg',
        mark: SnackMark.failure,
      ),
    ),
    (
      site: 'original_actions · share',
      snack: const Snack.detail(
        title: 'Nothing to share',
        subtitle: 'Voice memo — Friday standup',
      ),
    ),
    (
      site: 'file_viewer_page · remove (5s to undo)',
      snack: Snack.undo(message: 'Memory removed', onUndo: _noop),
    ),
    (
      site: 'pending_removals · delete failed',
      snack: const Snack.detail(
        title: 'Could not remove it',
        subtitle: _offlineCause,
        mark: SnackMark.failure,
      ),
    ),
    (
      site: 'library_page · Drive file un-indexed',
      snack: const Snack.confirmation(
        message: 'Removed from your index. The file is untouched.',
      ),
    ),
    (
      site: 'library_page · change error',
      snack: const Snack.detail(
        title: 'Could not change that file',
        subtitle: _offlineCause,
        mark: SnackMark.failure,
      ),
    ),
  ],
  'account': [
    (
      site: 'sync_news · Drive sync added files',
      snack: Snack.assistant(
        message: 'Found 3 new files in Google Drive',
        onOpen: _noop,
      ),
    ),
    (
      site: 'connect_storage_page · error',
      snack: const Snack.detail(
        title: 'Could not connect',
        subtitle: "Google Drive didn't respond. Try again in a moment.",
        mark: SnackMark.failure,
      ),
    ),
    (
      site: 'choose_folders_page · error',
      snack: const Snack.detail(
        title: 'Could not start indexing',
        subtitle: _offlineCause,
        mark: SnackMark.failure,
      ),
    ),
    (
      site: 'permissions_page · unchanged',
      snack: const Snack.detail(
        title: 'Permissions unchanged',
        subtitle: 'Google kept the old access. Try again.',
        mark: SnackMark.failure,
      ),
    ),
    (
      site: 'permissions_page · revoked',
      snack: const Snack.detail(
        title: 'Manage access removed',
        subtitle: 'Reconnect to keep indexing this account.',
      ),
    ),
    (
      site: 'vault_page · rebuild error',
      snack: const Snack.detail(
        title: 'Could not rebuild',
        subtitle: 'An index is already rebuilding. Give it a minute.',
        mark: SnackMark.failure,
      ),
    ),
    (
      site: 'profile_page · home = voice',
      snack: const Snack.confirmation(message: 'Home opens to the orb'),
    ),
    (
      site: 'profile_page · home = type',
      snack: const Snack.confirmation(message: 'Home opens to a thread'),
    ),
    (
      site: 'profile_page · pref error',
      snack: const Snack.detail(
        title: 'Not saved',
        subtitle: _offlineCause,
        mark: SnackMark.failure,
      ),
    ),
    (
      site: 'profile_page · load error',
      snack: const Snack.detail(
        title: 'Could not load your account',
        subtitle: _offlineCause,
        mark: SnackMark.failure,
      ),
    ),
    (
      site: 'paywall_page · purchased',
      snack: const Snack.confirmation(message: 'Pro is active'),
    ),
    (
      site: 'paywall_page · not completed',
      snack: const Snack.detail(
        title: 'Not completed',
        subtitle: 'The purchase was cancelled. You were not charged.',
        mark: SnackMark.failure,
      ),
    ),
  ],
};

/// One board: each snack on the ink ground, its source under it.
Widget _boardFor(List<_Entry> entries) => MaterialApp(
  theme: AppTheme.dark,
  debugShowCheckedModeBanner: false,
  home: Builder(
    builder: (context) {
      final p = context.palette;
      // Transparent Material, as `SnackHost` gives every snack in the app —
      // without it, text falls back to Flutter's debug underline.
      return Material(
        color: p.ground,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final entry in entries) ...[
                Center(
                  child: SnackView(snack: entry.snack, onDismiss: _noop),
                ),
                const SizedBox(height: 6),
                Text(
                  entry.site,
                  textAlign: TextAlign.center,
                  style: AppTypography.meta.copyWith(color: p.textFaint),
                ),
                const SizedBox(height: 18),
              ],
            ],
          ),
        ),
      );
    },
  ),
);

void main() {
  setUpAll(loadAppFonts);

  for (final MapEntry(key: name, value: entries) in _board.entries) {
    testWidgets('every snack in the app — $name', (tester) async {
      tester.view
        ..physicalSize = Size(402, 20 + entries.length * 116.0)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      // The assistant snack's glyph is the Hawk mark, an image.
      await precacheAppImages(tester);

      await tester.pumpWidget(_boardFor(entries));
      // Not settle: the busy mark turns for as long as it is up.
      await tester.pump(const Duration(milliseconds: 100));

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/board_$name.png'),
      );
    });
  }

  test('the board lists every snack, and every one follows the rules', () {
    final all = [for (final group in _board.values) ...group];
    expect(all, hasLength(46));
    for (final (:site, :snack) in all) {
      // Red only on failures: a failure-looking title must carry the mark.
      if (snack case DetailSnack(:final title, :final mark)) {
        final soundsLikeFailure = RegExp(
          r'^(Could not|Couldn’t|Can’t|Not saved|Not completed|'
          r'Nothing added|Permissions unchanged)',
        ).hasMatch(title);
        expect(
          mark == SnackMark.failure,
          soundsLikeFailure,
          reason: '$site: "$title"',
        );
      }
    }
  });
}
