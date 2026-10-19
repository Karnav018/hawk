import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/injector.dart';
import '../../../core/feedback/snack.dart';
import '../../../core/feedback/snack_controller.dart';
import '../../memory/presentation/pages/file_viewer_page.dart';
import 'bloc/capture_cubit.dart';
import 'bloc/upload_center.dart';
import 'bloc/upload_intake.dart';
import 'pages/indexing_page.dart';
import 'widgets/upload_sheets.dart';

/// What happens between a picker closing and a file going up.
///
/// Shared by the Library (after the type sheet) and the Indexing screen
/// (Rescan), so "too big", "already kept" and "can't read that" are answered
/// the same way wherever a pick starts.
///
/// The steps, and where each outcome goes:
///
/// * ready → queue it, open the Indexing screen (F1·4)
/// * too big → a sheet; "Choose another file" reopens the picker directly,
///   not the type sheet (E2·3)
/// * already kept → a sheet with the existing row; "Open it" or "Keep both"
///   (E4)
/// * can't read that type → an island with the way forward (E3)
/// * camera off → the permission sheet
/// * cancelled → nothing (E1)
abstract final class UploadFlow {
  /// Pick for [kind] with no type sheet in front of it, then [handle] it.
  static Future<void> run(
    BuildContext context,
    CaptureKind kind, {
    bool replace = false,
  }) async {
    final intake = await getIt<UploadIntake>().pick(kind);
    if (!context.mounted) return;
    await handle(context, intake, replace: replace);
  }

  /// [replace] swaps the Indexing screen [context] is on for the new batch's,
  /// rather than stacking a second one on it — Rescan (E7).
  static Future<void> handle(
    BuildContext context,
    Intake intake, {
    int? windowDays,
    bool replace = false,
  }) async {
    final snacks = getIt<SnackController>();

    switch (intake) {
      case IntakeCancelled():
        return;

      case IntakeReady(
        :final kind,
        :final files,
        :final hashes,
        :final skipped,
      ):
        final batchId = getIt<UploadCenter>().enqueue(
          files,
          kind: kind,
          hashes: hashes,
        );
        if (skipped > 0) {
          snacks.show(
            Snack.detail(
              title: 'Left out $skipped of ${files.length + skipped}',
              subtitle:
                  'Too big, already in your Library, or a type Hawk '
                  'can’t read.',
            ),
          );
        }
        if (replace) {
          context.pushReplacementNamed(
            IndexingPage.routeName,
            pathParameters: {'batchId': batchId},
          );
        } else {
          unawaited(
            context.pushNamed(
              IndexingPage.routeName,
              pathParameters: {'batchId': batchId},
            ),
          );
        }

      case IntakeTooLarge(:final kind, :final file):
        final again = await showTooLargeSheet(context, file);
        if (again && context.mounted) {
          await run(context, kind, replace: replace);
        }

      case IntakeDuplicate(:final existing):
        final choice = await showDuplicateSheet(
          context,
          existing,
          windowDays: windowDays,
        );
        if (!context.mounted) return;
        switch (choice) {
          case DuplicateChoice.open:
            unawaited(
              context.pushNamed(
                FileViewerPage.routeName,
                pathParameters: {'memoryId': existing.id},
              ),
            );
          case DuplicateChoice.keepBoth:
            await handle(
              context,
              UploadIntake.keepBoth(intake),
              replace: replace,
            );
          case null:
            return;
        }

      case IntakeUnsupported(:final extension):
        // Non-blocking (E3): the island says why and what to do, and the
        // Library underneath is exactly where it was.
        snacks.show(
          Snack.detail(
            title: extension.isEmpty
                ? 'Can’t read that file'
                : 'Can’t read $extension files',
            subtitle: 'Export it as PDF, then upload that.',
            mark: SnackMark.failure,
          ),
        );

      case IntakeNothing(:final skipped):
        snacks.show(
          Snack.detail(
            title: 'Nothing added',
            subtitle: skipped == 1
                ? 'It was too big, already kept, or a type Hawk can’t read.'
                : 'All $skipped were too big, already kept, or a type Hawk '
                      'can’t read.',
            mark: SnackMark.failure,
          ),
        );

      case IntakeCameraDenied():
        await showCameraSheet(context);

      case IntakeFailed(:final exception, :final kind):
        snacks.show(
          Snack.detail(
            // The snackbar board's own titles: images_capture_page's for a
            // photo pick, library_page's save error for the rest.
            title: kind == CaptureKind.images
                ? 'Could not add those images'
                : 'Could not save',
            subtitle: exception.displayMessage,
            mark: SnackMark.failure,
          ),
        );
    }
  }
}
