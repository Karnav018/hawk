import 'package:flutter/material.dart';

import '../../app/theme/app_palette.dart';
import '../di/injector.dart';
import '../feedback/snack.dart';
import '../feedback/snack_controller.dart';
import '../widgets/app_icons.dart';
import 'original_access.dart';

/// What a screen knows about a memory's original. Enough to open or share
/// it; the three places a file appears — matches on 2C, sources on 3B, rows
/// in the library — each build one of these.
typedef OriginalRef = ({
  String memoryId,
  String title,
  String? url,

  /// Where the file is kept in the vault, when one was kept. Fetched on
  /// demand for a device that never had it.
  String? storagePath,

  /// Shared in place of the file when there is none on this phone — the
  /// passage that matched, or a note's own text.
  String? fallback,
});

/// Opens the original in whatever app the phone uses for that kind of file.
///
/// Every outcome that is not "opened" says so. A tap that silently does
/// nothing is the worst available answer, and it is what the library did.
Future<void> openOriginal(OriginalRef ref) async {
  final access = getIt<OriginalAccess>();
  var handle = await access.resolve(
    memoryId: ref.memoryId,
    url: ref.url,
    storagePath: ref.storagePath,
    filename: ref.title,
  );

  // A vault file is fetched before it can be opened, and the fetch is the
  // slow part — so say so first. On a phone that captured the file this is
  // skipped entirely, because it is already here.
  if (handle is OriginalInVault) {
    // A detail snack, not a progress one: `Snack.progress` needs a real
    // fraction, and `writeToFile` reports bytes only if its task is
    // observed. A made-up fraction that jumps to done is worse than a line
    // saying what is happening.
    getIt<SnackController>().show(
      Snack.detail(
        title: 'Fetching ${ref.title}',
        subtitle: 'Downloading it from your vault',
        mark: SnackMark.busy,
      ),
    );
    handle = await access.materialise(handle, ref.memoryId);
  }

  final outcome = await access.open(handle);

  final snack = switch (outcome) {
    OpenOutcome.opened => null,
    OpenOutcome.noApp => Snack.detail(
      title: 'Nothing here can open it',
      subtitle: 'Install an app for this kind of file, or share it instead.',
    ),
    OpenOutcome.missing => Snack.detail(
      title: 'The file is no longer on this phone',
      subtitle:
          'Its memory is still searchable. Capture it again to reopen it.',
    ),
    // Captured elsewhere, or before originals were kept. The memory is
    // still worth having, so this informs rather than apologises.
    OpenOutcome.unavailable => Snack.detail(
      title: ref.title,
      mark: SnackMark.file,
      subtitle:
          'The original is not on this phone — it was captured on '
          'another device or before Hawk kept files.',
    ),
    // The fetch failed, so the file is in the vault and this phone could
    // not reach it. Waiting fixes this; retrying now will not.
    OpenOutcome.unreachable => Snack.detail(
      title: 'Could not fetch it',
      mark: SnackMark.failure,
      subtitle:
          'Your file is in the vault. Check your connection and try '
          'again.',
    ),
    OpenOutcome.failed => Snack.detail(
      title: 'Could not open it',
      mark: SnackMark.failure,
      subtitle: ref.title,
    ),
  };
  if (snack != null) getIt<SnackController>().show(snack);
}

/// Shares the file itself where it is on this phone, the link where there is
/// one, and the title with its passage otherwise.
Future<void> shareOriginal(OriginalRef ref, {Rect? origin}) async {
  final access = getIt<OriginalAccess>();
  var handle = await access.resolve(
    memoryId: ref.memoryId,
    url: ref.url,
    storagePath: ref.storagePath,
    filename: ref.title,
  );
  // Sharing a vault file means sharing the file, so it has to come down
  // first — a link to a path nobody else can read would share nothing.
  handle = await access.materialise(handle, ref.memoryId);
  final shared = await access.share(
    handle,
    title: ref.title,
    fallback: ref.fallback,
    origin: origin,
  );
  if (!shared) {
    getIt<SnackController>().show(
      Snack.detail(title: 'Nothing to share', subtitle: ref.title),
    );
  }
}

/// A small share button for a row.
///
/// Finds its own position on screen and passes it as the share origin —
/// iPad anchors the share sheet to it and throws without one, which a
/// phone-only test would never catch.
class ShareOriginalButton extends StatelessWidget {
  const ShareOriginalButton({
    required this.original,
    this.size = 32,
    super.key,
  });

  final OriginalRef original;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return Semantics(
      button: true,
      label: 'Share ${original.title}',
      child: SizedBox.square(
        dimension: size,
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              final box = context.findRenderObject() as RenderBox?;
              final origin = box == null || !box.hasSize
                  ? null
                  : box.localToGlobal(Offset.zero) & box.size;
              shareOriginal(original, origin: origin);
            },
            child: Center(
              child: AppIcon(
                AppIcons.share,
                size: size * 0.5,
                color: p.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
