import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../../../core/widgets/hawk_icons.dart';
import '../../../../core/widgets/hawk_kit.dart';
import '../../../memory/domain/entities/memory.dart';
import '../../../memory/presentation/widgets/memory_row.dart';
import '../../data/file_capture.dart';
import '../bloc/capture_cubit.dart';
import '../bloc/upload_intake.dart';
import '../bloc/upload_job.dart';
import 'upload_icons.dart';

/// Opens [child] as the flow's dark sheet, over everything — the nav pill
/// included, as the design draws it.
Future<T?> showUploadSheet<T>(BuildContext context, Widget child) =>
    showModalBottomSheet<T>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.64),
      elevation: 0,
      builder: (_) => child,
    );

/// The sheet every decision in this flow is drawn on: #191a1b, 34px top
/// corners, a grabber, and the home indicator's 34px under the last button.
class UploadSheet extends StatelessWidget {
  const UploadSheet({
    required this.children,
    this.bottom = AppSpacing.xxl,
    super.key,
  });

  final List<Widget> children;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(34)),
      ),
      padding: EdgeInsets.fromLTRB(AppSpacing.lg, 10, AppSpacing.lg, bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 5,
              margin: const EdgeInsets.only(bottom: AppSpacing.inset),
              decoration: BoxDecoration(
                color: p.border,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

/// A sheet's title with its × — the type sheet and the link sheet.
class SheetHeader extends StatelessWidget {
  const SheetHeader({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      children: [
        Expanded(child: Headline(title, size: 22)),
        const SizedBox(width: AppSpacing.md),
        CircleButton(
          icon: HawkIcons.close,
          semanticLabel: 'Close',
          size: 36,
          tone: p.raised,
          iconColor: p.textPrimary,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ],
    );
  }
}

// ===========================================================================
// F1·2 — "What are you adding?"
// ===========================================================================

/// What the type sheet was closed with.
///
/// [intake] is null for the two tiles that do not pick a file — Link and
/// Speak — which have their own screens to go to.
typedef TypeChoice = ({CaptureKind kind, Intake? intake});

/// The six tiles, on a sheet over the Library — a glyph and a name each,
/// and nothing else. The design put a line of formats under every tile, a
/// sentence under the title and the size limit under the grid; all three
/// were cut. Six words are the whole choice, and the limit is said at the
/// one moment it matters, when a file is over it (E2).
///
/// **The sheet stays up while the picker is open.** Backing out of the OS
/// picker lands on the sheet again, not on the Library (E1·2) — the user
/// was choosing a type, and cancelling the file is not cancelling that.
/// Only an outcome that needs the Library — a file to upload, a decision to
/// make — closes it.
class TypeSheet extends StatefulWidget {
  const TypeSheet({required this.onPick, super.key});

  /// Runs the picker for a file tile. The sheet waits on it.
  final Future<Intake> Function(CaptureKind kind) onPick;

  @override
  State<TypeSheet> createState() => _TypeSheetState();
}

class _TypeSheetState extends State<TypeSheet> {
  /// The tile being answered, drawn pressed until the picker comes back.
  CaptureKind? _active;

  Future<void> _choose(CaptureKind kind) async {
    if (_active != null) return;
    setState(() => _active = kind);

    if (!kind.uploads) {
      Navigator.of(context).pop<TypeChoice>((kind: kind, intake: null));
      return;
    }

    final intake = await widget.onPick(kind);
    if (!mounted) return;
    if (intake is IntakeCancelled) {
      setState(() => _active = null);
      return;
    }
    Navigator.of(context).pop<TypeChoice>((kind: kind, intake: intake));
  }

  @override
  Widget build(BuildContext context) {
    const kinds = CaptureKind.values;

    return UploadSheet(
      children: [
        const SheetHeader(title: 'What are you adding?'),
        const SizedBox(height: AppSpacing.lg),
        for (var row = 0; row < kinds.length; row += 2) ...[
          if (row > 0) const SizedBox(height: AppSpacing.gap),
          Row(
            children: [
              for (var col = 0; col < 2; col++) ...[
                if (col > 0) const SizedBox(width: AppSpacing.gap),
                Expanded(
                  child: TypeTile(
                    kind: kinds[row + col],
                    selected: _active == kinds[row + col],
                    onTap: () => _choose(kinds[row + col]),
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

/// One type — 96px, glyph above, name below.
class TypeTile extends StatelessWidget {
  const TypeTile({
    required this.kind,
    required this.onTap,
    this.selected = false,
    super.key,
  });

  final CaptureKind kind;
  final VoidCallback onTap;
  final bool selected;

  static String iconFor(CaptureKind kind) => switch (kind) {
    CaptureKind.files => HawkIcons.file,
    CaptureKind.images => HawkIcons.image,
    CaptureKind.links => HawkIcons.link,
    CaptureKind.scan => HawkIcons.scan,
    CaptureKind.audio => HawkIcons.audio,
    CaptureKind.speak => HawkIcons.mic,
  };

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final ink = selected ? p.onAccent : p.textPrimary;

    return Semantics(
      button: true,
      selected: selected,
      label: kind.label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedScale(
          scale: selected ? 0.97 : 1,
          duration: const Duration(milliseconds: 90),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: 96,
            padding: const EdgeInsets.all(AppSpacing.group),
            decoration: BoxDecoration(
              color: selected ? p.accent : p.raised,
              borderRadius: BorderRadius.circular(AppRadius.row),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                AppIcon(iconFor(kind), size: 21, color: ink, strokeWidth: 2),
                Text(
                  kind.label,
                  style: AppTypography.titleSmall.copyWith(color: ink),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// Decisions — E2, E4, E9, E10
// ===========================================================================

/// One button on a decision sheet, and what it answers.
typedef SheetAction<T> = ({String label, PillTone tone, T value});

/// A question the user has to answer before anything happens: an icon, a
/// headline, a sentence, and the ways out as full-width buttons.
///
/// A sheet rather than an island because each of these *blocks* — the file
/// is not uploaded until the user says what to do with it. An island is for
/// news; these are questions.
class DecisionSheet<T> extends StatelessWidget {
  const DecisionSheet({
    required this.icon,
    required this.title,
    required this.body,
    required this.actions,
    this.danger = false,
    this.child,
    super.key,
  });

  final String icon;
  final String title;
  final String body;
  final List<SheetAction<T>> actions;

  /// A red tile with an ink glyph — only for a refusal (E2).
  final bool danger;

  /// Drawn between the sentence and the buttons — E4's existing row.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return UploadSheet(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: danger ? p.danger : p.raised,
              borderRadius: BorderRadius.circular(17),
            ),
            alignment: Alignment.center,
            child: AppIcon(
              icon,
              size: 23,
              color: danger ? p.onAccent : p.textPrimary,
              strokeWidth: 2.2,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.inset),
        Headline(title, size: 22),
        const SizedBox(height: AppSpacing.sm),
        Text(
          body,
          style: AppTypography.bodyMedium.copyWith(
            fontSize: 14,
            height: 1.5,
            color: p.textTertiary,
          ),
        ),
        if (child != null) ...[
          const SizedBox(height: AppSpacing.inset),
          child!,
        ],
        const SizedBox(height: AppSpacing.card),
        for (final (i, action) in actions.indexed) ...[
          if (i > 0) const SizedBox(height: AppSpacing.gap),
          PillButton(
            label: action.label,
            tone: action.tone,
            height: AppSize.buttonSmall,
            onPressed: () => Navigator.of(context).pop(action.value),
          ),
        ],
      ],
    );
  }
}

/// E2 — "That file is too big". True means choose another file.
Future<bool> showTooLargeSheet(BuildContext context, PickedFile file) async {
  final limit = FileCapture.maxBytes ~/ (1024 * 1024);
  final again = await showUploadSheet<bool>(
    context,
    DecisionSheet<bool>(
      icon: UploadIcons.alert,
      danger: true,
      title: 'That file is too big',
      body:
          '${file.name} is ${megabytes(file.bytes)}. '
          'Hawk reads files up to $limit MB.',
      actions: const [
        (label: 'Choose another file', tone: PillTone.white, value: true),
        (label: 'Cancel', tone: PillTone.clear, value: false),
      ],
    ),
  );
  return again ?? false;
}

enum DuplicateChoice { open, keepBoth }

/// E4 — "Already in your Library", with the row it already has so it is
/// recognisable at a glance.
Future<DuplicateChoice?> showDuplicateSheet(
  BuildContext context,
  Memory existing, {
  int? windowDays,
}) => showUploadSheet<DuplicateChoice>(
  context,
  DecisionSheet<DuplicateChoice>(
    icon: UploadIcons.copy,
    title: 'Already in your Library',
    body:
        'You kept this file on ${dayMonth(existing.createdAt)}. '
        'Nothing has changed since.',
    actions: const [
      (label: 'Open it', tone: PillTone.white, value: DuplicateChoice.open),
      (
        label: 'Keep both',
        tone: PillTone.raised,
        value: DuplicateChoice.keepBoth,
      ),
    ],
    child: IgnorePointer(
      child: MemoryRow(memory: existing, windowDays: windowDays, onTap: () {}),
    ),
  ),
);

enum StorageChoice { upgrade, freeUp }

/// E10 — "Make room to upload". [reason] is the plan's own sentence, so a
/// Premium user is never told to buy what they already have; Go Pro is only
/// offered when paying would change the answer.
Future<StorageChoice?> showStorageSheet(
  BuildContext context, {
  required String reason,
  required bool upgradeable,
}) => showUploadSheet<StorageChoice>(
  context,
  DecisionSheet<StorageChoice>(
    icon: UploadIcons.lock,
    title: 'Make room to upload',
    body: reason,
    actions: [
      if (upgradeable)
        (label: 'Go Pro', tone: PillTone.white, value: StorageChoice.upgrade),
      (
        label: 'Free up space',
        tone: upgradeable ? PillTone.raised : PillTone.white,
        value: StorageChoice.freeUp,
      ),
    ],
  ),
);

/// E9's shape, for the camera.
///
/// The design draws this for photos, but the system photo picker needs no
/// permission — that sheet would never appear. The camera does need one on
/// iOS, and a scanner that silently did nothing would be the dead end the
/// design is avoiding.
Future<void> showCameraSheet(BuildContext context) async {
  final open = await showUploadSheet<bool>(
    context,
    DecisionSheet<bool>(
      icon: HawkIcons.scan,
      title: 'Let Hawk use the camera',
      body:
          'Scanning needs the camera. Turn it on for Hawk in Settings, '
          'then scan again.',
      actions: const [
        (label: 'Open Settings', tone: PillTone.white, value: true),
        (label: 'Not now', tone: PillTone.clear, value: false),
      ],
    ),
  );
  if (open ?? false) {
    // iOS only: Android's scanner is Google Play's, and asks for nothing.
    unawaited(launchUrl(Uri.parse('app-settings:')));
  }
}

/// `2 Aug`. From a fixed month table — `DateFormat` is not initialised in
/// this app and throws on first use.
String dayMonth(DateTime when) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final local = when.toLocal();
  return '${local.day} ${months[local.month - 1]}';
}
