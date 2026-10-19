import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/pop_or.dart';
import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/di/injector.dart';
import '../../../../core/feedback/snack.dart';
import '../../../../core/feedback/snack_controller.dart';
import '../../../../core/widgets/app_screen.dart';
import '../../../../core/widgets/hawk_icons.dart';
import '../../../../core/widgets/hawk_kit.dart';
import '../../../connectors/domain/entities/storage_account.dart';
import '../../../connectors/domain/entities/storage_provider.dart';
import '../../../connectors/presentation/pages/connect_storage_page.dart';
import '../../domain/entities/account_overview.dart';
import '../bloc/vault_cubit.dart';
import '../widgets/profile_pieces.dart';
import 'profile_page.dart';

/// Screen 1R — VAULT (INSIDE PROFILE).
///
/// **The profile is where storage lives now.** v2 reached storage from a
/// bottom-nav dock, which gave a setup screen permanent equal billing with the
/// two things people do every day; v3 removed it from the nav entirely and put
/// it one level in, behind You → Vault. This screen is that level: it answers
/// "what does Hawk actually hold, and where did it come from", and the
/// connect flow is a button on it rather than a destination in its own right.
///
/// The screen's one white card is the **count**, not a source. That is the
/// design making a point: the thing worth knowing is how much is askable, and
/// which provider it came from is a detail of the list underneath. v2 led with
/// the connected accounts and buried the number in a stat tile, which answered
/// the question nobody opens this screen to ask.
///
/// The accent is spent once, on "Add a source" — the live dot on a healthy
/// source is the same colour and is the one exception the design draws, since
/// a dot is a state rather than an action.
class VaultPage extends StatelessWidget {
  const VaultPage({super.key});

  static const routeName = 'vault';

  /// Under `/profile`, because that is genuinely where it sits — and because
  /// a path that reads like the navigation means a deep link into it restores
  /// the same back stack a tap would have built.
  static const routePath = '/profile/vault';

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      // Built by hand rather than resolved as a whole: see [VaultCubit] for
      // why it is not `@injectable`. The two arguments are the same
      // singletons the generated wiring would pass.
      create: (_) => VaultCubit(getIt(), getIt())..load(),
      child: const _VaultView(),
    );
  }
}

class _VaultView extends StatelessWidget {
  const _VaultView();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<VaultCubit, VaultState>(
      listenWhen: (a, b) => a.error != b.error && b.error != null,
      listener: (context, state) {
        getIt<SnackController>().show(
          Snack.detail(
            title: 'Could not rebuild',
            mark: SnackMark.failure,
            subtitle: state.error!.displayMessage,
          ),
        );
        context.read<VaultCubit>().dismissError();
      },
      builder: (context, state) {
        final cubit = context.read<VaultCubit>();

        return AppScreen(
          // v3 has no wash. 1R is a plain ground with cards on it.
          ambientOpacity: 0,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const _Header(),
              const SizedBox(height: AppSpacing.lg),

              _IndexCard(state: state),
              const SizedBox(height: AppSpacing.group),

              if (state.isLoading && state.catalog == null)
                const _SourcesPlaceholder()
              else if (state.sources.isEmpty)
                _NoSources(hasFiles: state.indexedFiles > 0)
              else
                RowGroup(
                  children: [
                    for (final account in state.sources)
                      _SourceRow(account: account),
                  ],
                ),
              const SizedBox(height: AppSpacing.group),

              PillButton(
                label: 'Add a source',
                // Leading, not trailing: a plus before the label means *this
                // adds a thing*, where a glyph after it would read as
                // navigation.
                leadingIcon: HawkIcons.plus,
                height: AppSize.buttonMedium,
                // The storage screen already exists and is already ported.
                // Pushed by name, so 1R stays on the stack underneath and
                // "Done" comes back here rather than to the profile.
                onPressed: () =>
                    context.pushNamed(ConnectStoragePage.manageRouteName),
              ),
              const SizedBox(height: AppSpacing.gap),
              PillButton(
                label: 'Rebuild index',
                tone: PillTone.secondary,
                height: AppSize.buttonMedium,
                isBusy: state.isRebuilding,
                // Disabled rather than hidden when there is nothing to
                // rebuild: a button that vanishes teaches that the product
                // cannot do it, and the same rule governs every other locked
                // affordance in the app.
                onPressed: state.canRebuild ? cubit.rebuild : null,
              ),
              const SizedBox(height: AppSpacing.group),

              const InfoNote(
                'Removing a source deletes only its index. Your files stay '
                'where they are.',
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Back, then the title inline beside it.
///
/// Not `AuthHeader`: that one deliberately carries no title, because the
/// screens it serves put a 34px headline three lines below and repeating it
/// would be saying the same thing twice. 1R has no headline — the white card
/// is the first thing — so the title has nowhere else to go and the design
/// sets it at 24px on the header row itself.
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) => Row(
    children: [
      CircleButton(
        icon: HawkIcons.chevronLeft,
        semanticLabel: 'Back',
        // The Vault is always pushed from the profile — but a deep link to
        // `/profile/vault` arrives with nothing behind it, and back still
        // means the profile.
        onPressed: () => context.popOrGo(ProfilePage.routeName),
      ),
      const SizedBox(width: AppSpacing.md),
      const Expanded(child: Headline('Vault', size: 24)),
    ],
  );
}

/// The one white card: how much is indexed, and what it breaks down into.
class _IndexCard extends StatelessWidget {
  const _IndexCard({required this.state});

  final VaultState state;

  @override
  Widget build(BuildContext context) {
    final paper = AppPalette.onPaper;
    final files = state.indexedFiles;

    return HawkCard(
      tone: CardTone.paper,
      padding: const EdgeInsets.all(AppSpacing.cardWide),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Not the design's "INDEXED ON DEVICE". Hawk's index lives on the
          // server — the vectors are in Firestore — so that label promised
          // something the product does not do, on the screen whose whole job
          // is to say what the vault holds and where.
          MetaText('In your vault', wide: true, color: paper.muted),
          const SizedBox(height: AppSpacing.sm),
          Headline(
            '${groupedCount(files)} ${files == 1 ? 'file' : 'files'}',
            size: 34,
            color: paper.ink,
          ),
          if (chipsFor(state.overview).isNotEmpty) ...[
            const SizedBox(height: AppSpacing.inset),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final chip in chipsFor(state.overview)) PaperPill(chip),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// One source inside the shared card.
///
/// [HawkRow] rather than a local shape, because this *is* the kit's row: a
/// tile, a name, a line of metadata and one trailing affordance. Only the tile
/// is dressed down to the 38px the design draws for a source, against the 42px
/// it uses for a file.
class _SourceRow extends StatelessWidget {
  const _SourceRow({required this.account});

  final StorageAccount account;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isDevice = account.provider == StorageProvider.internal;

    // A healthy source gets the live dot and nothing to tap: there is nothing
    // further in, and the design says so by drawing no chevron. One that needs
    // attention gets the chevron and leads to the screen that can fix it —
    // which is the same screen, and the same reasoning, as 1G's source cards.
    final settled = account.state.isHealthy;

    return HawkRow(
      title: isDevice ? 'Phone vault' : account.provider.label,
      meta: _meta(account),
      leading: IconTile(
        icon: isDevice ? HawkIcons.phoneVault : HawkIcons.googleDrive,
        size: AppSize.tileSmall,
        radius: AppRadius.tileSmall,
        // Set here rather than through `HawkRow.iconColor`, which only
        // applies to the row's own `icon:` and is ignored once `leading:` is
        // given a widget of its own.
        foreground: account.state.needsAttention ? p.danger : p.textPrimary,
        strokeWidth: 1.7,
      ),
      trailing: settled && !isDevice ? const LiveDot() : null,
      // The device vault keeps its chevron even when it is perfectly healthy:
      // unlike a provider account there *is* more in there — the files picked
      // on this phone — and the storage screen is where they are managed.
      onTap: settled && !isDevice
          ? null
          : () => context.pushNamed(ConnectStoragePage.manageRouteName),
    );
  }

  /// "CONNECTED · 842 INDEXED", or the state that matters more than the count.
  ///
  /// The state wins over the number for the same reason [StorageAccount]'s own
  /// `statusLine` puts it first: somebody whose Drive access was revoked needs
  /// to read that, not how much of it used to work.
  static String _meta(StorageAccount account) {
    final indexed = '${groupedCount(account.fileCount)} indexed';

    return switch (account.state) {
      ConnectorState.revoked => 'Access revoked · $indexed',
      ConnectorState.error => 'Needs attention · $indexed',
      ConnectorState.paused => 'Paused · $indexed',
      ConnectorState.syncing => 'Indexing… · $indexed',
      // The phone vault has no connection to report, so its second fact is
      // the one thing a local pile of files has that a remote one does not:
      // the space it takes on the device.
      ConnectorState.connected
          when account.provider == StorageProvider.internal =>
        account.bytes > 0 ? '$indexed · ${byteLabel(account.bytes)}' : indexed,
      ConnectorState.connected => 'Connected · $indexed',
    };
  }
}

/// Nothing is connected yet.
///
/// A dim card rather than an empty [RowGroup], which would render as a
/// hairline-thin sliver of card and read as a rendering bug. It says what is
/// missing and leaves the fix to the accented button below it, which is
/// already the loudest thing on the screen.
class _NoSources extends StatelessWidget {
  const _NoSources({required this.hasFiles});

  /// Files are already in the vault — added from this phone — even though
  /// no source is connected. "No sources yet" under a card counting them
  /// would read as the vault being empty.
  final bool hasFiles;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return HawkCard(
      tone: CardTone.dim,
      child: Row(
        children: [
          IconTile(
            icon: HawkIcons.vault,
            size: AppSize.tileSmall,
            radius: AppRadius.tileSmall,
            foreground: p.textMuted,
            strokeWidth: 1.7,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              hasFiles
                  ? 'Files added from this phone are counted above. Add a '
                        'source to index a whole Drive without moving it.'
                  : 'No sources yet. Add one and Hawk indexes it without '
                        'moving anything.',
              style: AppTypography.footnote.copyWith(color: p.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

class _SourcesPlaceholder extends StatelessWidget {
  const _SourcesPlaceholder();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      height: 128,
      decoration: BoxDecoration(
        color: p.cardDim,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
    );
  }
}

/// The design breaks the total into documents, recordings and images.
///
/// Those counts now exist: `account_summary` returns `counts.byKind`, three
/// Firestore aggregations over the memory types grouped the way a person
/// names them. Grouping happens server-side so the pipeline's eleven types
/// map to three words in one place rather than two.
///
/// The state breakdown — total, searchable, dormant — is the fallback for a
/// server older than that field, and for a vault whose kinds are all zero.
/// It is the same shape doing the same job: the total divided into parts
/// the user can act on. Either way every number is one the server sent.
///
/// A zero group is omitted rather than printed as "0 recordings", because a
/// chip reporting the absence of something is noise on a card whose whole
/// point is the number above it.
List<String> chipsFor(AccountOverview? overview) {
  if (overview == null) return const [];
  const order = ['documents', 'recordings', 'images'];
  final kinds = [
    for (final kind in order)
      if ((overview.byKind[kind] ?? 0) > 0)
        '${groupedCount(overview.byKind[kind]!)} $kind',
  ];
  // Dormant memories are in the total above — retention demotes, it does
  // not delete — but cannot be asked about on this plan. Said beside the
  // kinds, so the total never reads as more than can be answered.
  if (kinds.isNotEmpty) {
    return [
      ...kinds,
      if (overview.dormant > 0) '${groupedCount(overview.dormant)} dormant',
    ];
  }

  return [
    if (overview.memories >= 0) '${groupedCount(overview.memories)} memories',
    if (overview.indexed >= 0) '${groupedCount(overview.indexed)} searchable',
    if (overview.dormant > 0) '${groupedCount(overview.dormant)} dormant',
  ];
}
