import 'package:flutter/material.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/widgets/hawk_icons.dart';
import '../../../../core/widgets/hawk_kit.dart';
import '../../../connectors/domain/repositories/connector_repository.dart';

/// One file in a connected Drive — screen 1L's list.
///
/// The same 22px row as the on-device tab, with one difference that carries
/// the whole meaning of the screen: the trailing control is a **chip, not a
/// chevron**. A device file is somewhere you go; a Drive file is something you
/// decide about, and the decision is the row's only action.
///
/// **The chip's colour is the offer.** An unindexed file wears the accent,
/// because the row is offering you something — index this. An indexed one is
/// [AppPalette.raised], because it is not offering anything, it is simply
/// available. That is the rule `InlineChip.isAccent` already encodes, and it
/// is why a screenful of already-indexed files is calm and a screenful of new
/// ones is not.
class DriveFileRow extends StatelessWidget {
  const DriveFileRow({
    required this.file,
    required this.onAction,
    this.isBusy = false,
    super.key,
  });

  final ProviderFile file;

  /// Index it, or open it. Which one is decided by [ProviderFile.indexed],
  /// so the row cannot label itself one thing and do the other.
  final VoidCallback onAction;

  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return HawkRow(
      title: file.name,
      meta: [
        if (file.path.isNotEmpty) file.path,
        file.indexed ? 'INDEXED' : 'NOT INDEXED',
      ].join(' · '),
      icon: iconForProviderFile(file),
      trailing: isBusy
          ? SizedBox(
              width: AppSize.chip,
              height: AppSize.chip,
              child: Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(p.accent),
                  ),
                ),
              ),
            )
          : InlineChip(
              label: file.indexed ? 'Open' : 'Index',
              isAccent: !file.indexed,
              onPressed: onAction,
            ),
    );
  }
}

/// The glyph for a provider file.
///
/// Derived from the extension rather than from the mime type. Drive reports
/// its own documents as `application/vnd.google-apps.document`, which is not
/// in any mime table the app carries, while the name is always there and
/// always says what it is. The mime type is used only where the name has no
/// extension at all, which is what a Google-native file looks like.
String iconForProviderFile(ProviderFile file) {
  final dot = file.name.lastIndexOf('.');
  final extension = dot <= 0 ? '' : file.name.substring(dot + 1).toLowerCase();

  return switch (extension) {
    'png' ||
    'jpg' ||
    'jpeg' ||
    'heic' ||
    'heif' ||
    'webp' ||
    'gif' => HawkIcons.image,
    'mp3' || 'm4a' || 'aac' || 'wav' || 'ogg' || 'opus' => HawkIcons.audio,
    '' when (file.mimeType ?? '').startsWith('image/') => HawkIcons.image,
    '' when (file.mimeType ?? '').startsWith('audio/') => HawkIcons.audio,
    // Everything else is a document, including the spreadsheets and slide
    // decks the design draws with the same folded-corner mark.
    _ => HawkIcons.file,
  };
}
