import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/tab_shell.dart';
import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/di/injector.dart';
import '../../../../core/feedback/snack.dart';
import '../../../../core/feedback/snack_controller.dart';
import '../../../../core/files/original_actions.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../../../core/widgets/app_screen.dart';
import '../../../../core/widgets/error_view.dart';
import '../../../../core/widgets/hawk_icons.dart';
import '../../../../core/widgets/hawk_kit.dart';
import '../../../../core/widgets/plan_gate.dart';
import '../../../account/presentation/pages/vault_page.dart';
import '../../../account/presentation/widgets/profile_pieces.dart';
import '../../../billing/domain/entities/subscription.dart';
import '../../../billing/presentation/bloc/subscription_cubit.dart';
import '../../../billing/presentation/pages/paywall_page.dart';
import '../../../capture/presentation/bloc/capture_cubit.dart';
import '../../../capture/presentation/bloc/upload_center.dart';
import '../../../capture/presentation/bloc/upload_intake.dart';
import '../../../capture/presentation/pages/capture_page.dart';
import '../../../capture/presentation/pages/indexing_page.dart';
import '../../../capture/presentation/pages/speak_capture_page.dart';
import '../../../capture/presentation/upload_flow.dart';
import '../../../capture/presentation/widgets/indexing_parts.dart';
import '../../../capture/presentation/widgets/upload_button.dart';
import '../../../capture/presentation/widgets/upload_icons.dart';
import '../../../capture/presentation/widgets/upload_sheets.dart';
import '../../../chat/presentation/widgets/result_file.dart';
import '../../../connectors/presentation/pages/connect_storage_page.dart';
import '../../domain/entities/library_filter.dart';
import '../../domain/entities/memory.dart';
import '../bloc/drive_files_cubit.dart';
import '../bloc/memory_list_bloc.dart';
import '../bloc/pending_removals.dart';
import '../widgets/drive_file_row.dart';
import '../widgets/library_filter_row.dart';
import '../widgets/memory_icon.dart';
import '../widgets/memory_row.dart';
import 'file_viewer_page.dart';

/// Screens 1K and 1L — LIBRARY.
///
/// **One screen with two tabs, not two screens.** On device and Drive answer
/// the same question — what do I have — about two places, and the header, the
/// search and the tab control are literally the same pixels in both designs.
/// Splitting them into two routes would mean two copies of that chrome and
/// two chances for them to drift.
///
/// **One Upload button, not six tiles.** The first v3 cut put six quick-add
/// tiles above the list, which made the Library read as a set of filters.
/// The redesign (`Hawk Library.dc.html`, section 4) replaces them with one
/// blue button under the tabs — "the one blue thing on screen" — and moves
/// the six onto the sheet it opens. Upload → pick a type → pick from the
/// device → indexing → back to an updated list.
///
/// **The list is the uploads' too.** A file on its way up is a row at the
/// top of the list from the moment it is picked — uploading, queued offline,
/// being read — with the same ring the island shows. The rows come from
/// `UploadCenter` until the memory is in the list the bloc loaded, and the
/// bloc's copy is overridden with the center's live one while it is still
/// being followed, because the bloc fetches pages and never listens.
class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});

  static const routeName = 'library';
  static const routePath = '/library';

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<MemoryListBloc>(
          lazy: false,
          create: (_) =>
              getIt<MemoryListBloc>()..add(const MemoryListEvent.started()),
        ),
        // App-wide, and not closed here: uploads outlive this screen.
        BlocProvider<UploadCenter>.value(value: getIt<UploadCenter>()),
        // Deliberately lazy. Building it subscribes to the connector
        // catalogue and then calls `list_provider_files`, and neither is
        // worth doing for somebody who never opens the Drive tab.
        BlocProvider<DriveFilesCubit>(create: (_) => getIt<DriveFilesCubit>()),
      ],
      child: const _LibraryView(),
    );
  }
}

class _LibraryView extends StatefulWidget {
  const _LibraryView();

  @override
  State<_LibraryView> createState() => _LibraryViewState();
}

class _LibraryViewState extends State<_LibraryView> {
  final _deviceScroll = ScrollController();

  /// 0 = on device, 1 = Drive.
  ///
  /// Screen state, not cubit state: nothing outside this widget needs to know
  /// which tab is showing, and the tab shell already keeps the branch alive
  /// so it survives a trip to Home and back.
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _deviceScroll.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _deviceScroll
      ..removeListener(_maybeLoadMore)
      ..dispose();
    super.dispose();
  }

  /// Fetch the next page a screenful before the bottom, so scrolling never
  /// visibly stalls waiting on the network.
  ///
  /// Called on scroll *and* after every state change. The bloc drops repeated
  /// requests while one is in flight, which means the dropped ones must be
  /// re-asked by someone — and a `ScrollPosition` notifies on offset changes,
  /// not on the content growing. Without the post-state re-check, a list that
  /// happened to fit its viewport after appending would stall with no scroll
  /// event left to wake it.
  void _maybeLoadMore() {
    if (!_deviceScroll.hasClients) return;
    final position = _deviceScroll.position;
    if (position.pixels >= position.maxScrollExtent - 400) {
      context.read<MemoryListBloc>().add(
        const MemoryListEvent.nextPageRequested(),
      );
    }
  }

  /// Upload → the type sheet → whatever the chosen tile leads to.
  ///
  /// A full vault answers first (E10): the locked button opens the storage
  /// sheet, because the upload it would start could not be indexed.
  Future<void> _upload() async {
    final plan = context.read<SubscriptionCubit>().state;
    final lock = plan.indexLock;
    if (lock != null) {
      final choice = await showStorageSheet(
        context,
        reason: lock.reason,
        upgradeable: lock.upgradeable,
      );
      if (!mounted) return;
      switch (choice) {
        case StorageChoice.upgrade:
          unawaited(context.pushNamed(PaywallPage.routeName));
        case StorageChoice.freeUp:
          unawaited(context.pushNamed(VaultPage.routeName));
        case null:
          break;
      }
      return;
    }

    final intake = getIt<UploadIntake>();
    final choice = await showUploadSheet<TypeChoice>(
      context,
      TypeSheet(onPick: intake.pick),
    );
    if (choice == null || !mounted) return;

    switch (choice.kind) {
      case CaptureKind.links:
        unawaited(context.pushNamed(AddLinkSheet.routeName));
      case CaptureKind.speak:
        // A voice note, kept — not the orb, which asks. Keeping and asking
        // are opposite directions, so they get different screens.
        unawaited(context.pushNamed(SpeakCapturePage.routeName));
      case _:
        final picked = choice.intake;
        if (picked == null) return;
        await UploadFlow.handle(
          context,
          picked,
          windowDays: plan.memoryWindowDays,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final indexLock = context.plan.indexLock;

    return MultiBlocListener(
      listeners: [
        BlocListener<MemoryListBloc, MemoryListState>(
          // After the list changes, re-ask. The bloc dropped every request
          // that arrived while a fetch was in flight, and only a scroll event
          // would otherwise wake it again.
          listener: (context, state) => WidgetsBinding.instance
              .addPostFrameCallback((_) => _maybeLoadMore()),
        ),
        BlocListener<UploadCenter, UploadCenterState>(
          // A memory was made, or one finished. Reload quietly — the rows on
          // screen are right, and the list underneath is catching up with
          // them — so that when the center lets go of a job, its row is
          // already in the bloc's list rather than vanishing.
          listenWhen: (a, b) =>
              !setEquals(_madeIds(a), _madeIds(b)) ||
              !setEquals(_settledIds(a), _settledIds(b)),
          listener: (context, _) => context.read<MemoryListBloc>().add(
            const MemoryListEvent.started(refresh: true),
          ),
        ),
      ],
      child: AppScreen(
        // v3 has no wash. The library is the screen where that matters most:
        // it is a list of white-on-near-black rows, and a gradient behind
        // them made the bottom third look like a different surface.
        ambientOpacity: 0,
        scrollable: false,
        // No bottom inset here — each tab's list reserves `navClearance`
        // itself, so rows scroll *behind* the floating nav rather than
        // stopping short of it.
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenSide,
          AppSpacing.screenTop,
          AppSpacing.screenSide,
          0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _LibraryHeader(),
            const SizedBox(height: AppSpacing.group),
            SegmentedTabs(
              labels: const ['On device', 'Drive'],
              selected: _tab,
              onChanged: (index) => setState(() => _tab = index),
              // The design's live dot. It marks Drive as the tab with
              // something in it you have not decided about yet — which is
              // what an unindexed file is. Drawn unconditionally until
              // `list_provider_files` exists to count them; bind it to
              // `totalCount - indexedCount > 0` the moment it does.
              dotOn: 1,
            ),
            const SizedBox(height: AppSpacing.group),
            Expanded(
              child: _tab == 0
                  ? _OnDeviceTab(
                      scroll: _deviceScroll,
                      indexLock: indexLock,
                      onUpload: () => unawaited(_upload()),
                    )
                  : const _DriveTab(),
            ),
          ],
        ),
      ),
    );
  }

  static Set<String> _madeIds(UploadCenterState s) => {
    for (final j in s.jobs)
      if (j.memory case final m?) m.id,
  };

  static Set<String> _settledIds(UploadCenterState s) => {
    for (final j in s.jobs)
      if (j.isSettled) j.id,
  };
}

/// The title and the one header button.
///
/// v2 put four controls up here — search, sort, and a theme toggle — beside a
/// 39px title and a subtitle counting the memories. v3 keeps the title and a
/// single circle: sort is a preference nobody set, and the theme toggle has
/// nothing left to toggle now that there is one theme.
class _LibraryHeader extends StatelessWidget {
  const _LibraryHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Headline('Library', size: 28)),
        const SizedBox(width: AppSpacing.md),
        CircleButton(
          icon: HawkIcons.search,
          semanticLabel: 'Search your library',
          // Asking *is* the search in this product — "save it, ask for it
          // later in your own words" — so the magnifier opens the home
          // screen, where a question is spoken or typed. There is no
          // filter box, and the user chose to keep it that way.
          onPressed: () => context.go('/'),
        ),
      ],
    );
  }
}

// ===========================================================================
// 1K — on device
// ===========================================================================

class _OnDeviceTab extends StatelessWidget {
  const _OnDeviceTab({
    required this.scroll,
    required this.onUpload,
    this.indexLock,
  });

  final ScrollController scroll;
  final VoidCallback onUpload;
  final PlanLock? indexLock;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // E10. Under the tabs and directly over the button it explains:
        // the card says why, the button says what that means for it.
        if (indexLock != null) ...[
          _StorageFull(lock: indexLock!),
          const SizedBox(height: AppSpacing.md),
        ],
        BlocSelector<UploadCenter, UploadCenterState, int>(
          selector: (state) => state.uploading,
          builder: (context, uploading) => UploadButton(
            uploading: uploading,
            locked: indexLock != null,
            onPressed: onUpload,
          ),
        ),
        const SizedBox(height: AppSpacing.card),

        // Screen 1V's lower half. The condition is *retention*, not
        // storage: a memory goes dormant on its own timetable whether or not
        // the vault is full, and hiding the countdown until it is full would
        // surface it exactly when it is too late to act on.
        const _ExpiringSoon(),

        const _RecentHeading(),
        const SizedBox(height: 10),
        const _Kinds(),
        const SizedBox(height: 10),
        Expanded(
          // Rebuilt when a removal starts, is undone, or lands (2E): the row
          // leaves the moment Remove is tapped, and comes back on Undo.
          child: ListenableBuilder(
            listenable: getIt<PendingRemovals>(),
            builder: (context, _) =>
                BlocBuilder<UploadCenter, UploadCenterState>(
                  builder: (context, uploads) =>
                      BlocBuilder<MemoryListBloc, MemoryListState>(
                        builder: (context, state) {
                          final loaded = state is MemoryListLoaded
                              ? state.memories
                              : const <Memory>[];
                          final hidden = getIt<PendingRemovals>().hidden;
                          final rows = _LibraryRows.merge(uploads, [
                            for (final m in loaded)
                              if (!hidden.contains(m.id)) m,
                          ]);

                          return switch (state) {
                            _ when rows.isNotEmpty => _MemoryList(
                              rows: rows,
                              online: uploads.online,
                              isAppending:
                                  state is MemoryListLoaded &&
                                  state.isAppending,
                              controller: scroll,
                            ),
                            MemoryListInitial() ||
                            MemoryListLoading() => const _RowsPlaceholder(),
                            MemoryListFailure(:final exception) => ErrorView(
                              exception: exception,
                              onRetry: () => context.read<MemoryListBloc>().add(
                                const MemoryListEvent.retried(),
                              ),
                            ),
                            _ => _EmptyLibrary(filter: state.filter),
                          };
                        },
                      ),
                ),
          ),
        ),
      ],
    );
  }
}

/// One row of the On device list: an upload with no memory yet, or a memory
/// with — perhaps — the job that is still following it.
typedef _LibraryRow = ({UploadJob? job, Memory? memory});

abstract final class _LibraryRows {
  /// Uploads first, newest first, then the loaded list with each memory a
  /// job is still following swapped for the job's live copy.
  static List<_LibraryRow> merge(
    UploadCenterState uploads,
    List<Memory> loaded,
  ) {
    final listed = {for (final m in loaded) m.id};
    return [
      for (final job in uploads.jobs)
        if (job.memory == null && !job.quiet)
          (job: job, memory: null)
        else if (job.memory case final m? when !listed.contains(m.id))
          (job: job, memory: m),
      for (final memory in loaded)
        switch (uploads.jobForMemory(memory.id)) {
          final job? => (job: job, memory: job.memory),
          null => (job: null, memory: memory),
        },
    ];
  }
}

/// Screen 1V's lower half — memories close to falling out of the window.
///
/// **"GOES DORMANT", not "DELETED".** The design writes "DELETED IN 2 DAYS";
/// §36 demotes rather than deletes, and `Memory.retentionLabel` already had
/// the decision written into it. The file stays on the user's own storage and
/// an upgrade brings it back into the index intact — so a deletion countdown
/// would be frightening somebody into paying for a loss that does not happen.
/// The wording is the product's; the urgency is the design's.
///
/// **Keep goes to the upgrade**, because that is the only thing that keeps
/// it. There is no pin: retention is a property of the plan, not of the
/// memory, so a per-row "keep this one" would be a promise nothing in the
/// backend can hold.
class _ExpiringSoon extends StatelessWidget {
  const _ExpiringSoon();

  /// A week. Long enough to act on, short enough that the section is not a
  /// second copy of the library on a plan where everything expires.
  static const horizon = 7;

  @override
  Widget build(BuildContext context) {
    final window = context.plan.memoryWindowDays;
    // No ceiling, nothing to count down.
    if (window == null) return const SizedBox.shrink();

    return BlocBuilder<MemoryListBloc, MemoryListState>(
      builder: (context, state) {
        final loaded = state is MemoryListLoaded
            ? state.memories
            : const <Memory>[];

        final soon = [
          for (final m in loaded)
            if ((m.daysUntilDormant(windowDays: window) ?? horizon + 1) <=
                horizon)
              m,
        ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));

        if (soon.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                const Expanded(child: Headline('Expiring soon', size: 15)),
                MetaText('${soon.length} ITEM${soon.length == 1 ? '' : 'S'}'),
              ],
            ),
            const SizedBox(height: 10),
            RowGroup(
              children: [
                for (final m in soon)
                  HawkRow(
                    icon: hawkIconForMemory(m.type),
                    title: m.displayTitle,
                    meta: m.dormancyLabel(windowDays: window),
                    trailing: PillButton(
                      label: 'Keep',
                      tone: PillTone.paper,
                      height: 32,
                      onPressed: () => context.pushNamed(PaywallPage.routeName),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.card),
          ],
        );
      },
    );
  }
}

/// E10 — the vault is full.
///
/// The one white card the library is allowed, and it only exists while the
/// plan's index is actually full. It sits directly over the Upload button,
/// which it explains: the card says why, the greyed button says what that
/// means. The two ways out are one tap further, on the sheet the locked
/// button opens — a card with its own buttons over a button that also
/// opened them was the same choice offered twice.
class _StorageFull extends StatelessWidget {
  const _StorageFull({required this.lock});

  final PlanLock lock;

  @override
  Widget build(BuildContext context) {
    final paper = AppPalette.onPaper;
    final index = context.plan.index;

    return HawkCard(
      tone: CardTone.paper,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.card,
        vertical: AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  'Storage full',
                  style: AppTypography.display18.copyWith(color: paper.ink),
                ),
              ),
              // Omitted rather than invented when the plan reports no
              // ceiling: "15 / null GB" is the kind of thing that ships.
              if (index.limit != null)
                Text(
                  byteRatio(index.used, index.limit!),
                  style: AppTypography.meta.copyWith(
                    fontSize: 13,
                    letterSpacing: 0,
                    color: paper.ink,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          ProgressTrack.onPaper(value: index.fraction),
          const SizedBox(height: AppSpacing.md),
          Text(
            // The plan's own sentence, not the design's free-tier one. A
            // Premium user reading "move to Pro for 1 TB" would be told to
            // buy what they already have.
            lock.reason,
            style: AppTypography.bodySmall.copyWith(
              fontSize: 13,
              height: 1.55,
              color: paper.body,
            ),
          ),
        ],
      ),
    );
  }
}

/// "Recent", and the one number under the Upload button.
///
/// The design prints "1,516 INDEXED · 9.1 GB". Only the first half is drawn
/// here, and that is a correction rather than an omission: Firestore has no
/// cheap `COUNT(*)` — the same reason `MemoryPage` carries `hasMore` instead
/// of a total (QA-004) — so the client knows how many rows it has *loaded*,
/// not how many exist, and it never sees a byte total at all. A "9.1 GB" made
/// up from twenty loaded rows would be a number that changes as you scroll.
///
/// So it says "20+ INDEXED" until the last page lands and then says the truth.
class _RecentHeading extends StatelessWidget {
  const _RecentHeading();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Recent',
          style: AppTypography.titleLarge.copyWith(
            fontSize: 15,
            color: p.textPrimary,
          ),
        ),
        BlocBuilder<MemoryListBloc, MemoryListState>(
          builder: (context, state) => MetaText(switch (state) {
            MemoryListLoaded(:final total, :final hasMore) =>
              '${_grouped(total)}${hasMore ? '+' : ''} indexed',
            MemoryListEmpty() => 'nothing yet',
            MemoryListFailure() => 'unavailable',
            _ => 'loading',
          }),
        ),
      ],
    );
  }
}

/// The kinds row. Every state carries the filter, so the row stays put
/// through the loading state a change causes instead of snapping to All.
class _Kinds extends StatelessWidget {
  const _Kinds();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MemoryListBloc, MemoryListState>(
      builder: (context, state) => LibraryFilterRow(
        selected: state.filter,
        onChanged: (filter) => context.read<MemoryListBloc>().add(
          MemoryListEvent.filterChanged(filter),
        ),
      ),
    );
  }
}

class _MemoryList extends StatelessWidget {
  const _MemoryList({
    required this.rows,
    required this.online,
    required this.isAppending,
    required this.controller,
  });

  final List<_LibraryRow> rows;
  final bool online;
  final bool isAppending;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    final plan = context.plan;
    final dormant = plan.memoriesDormant;

    return ListView.separated(
      controller: controller,
      // Clearance for the shell's nav pill, which floats over this list
      // rather than sitting under it — see `navClearance`.
      padding: const EdgeInsets.only(bottom: navClearance),
      itemCount: rows.length + (isAppending ? 1 : 0) + (dormant > 0 ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.gap),
      itemBuilder: (context, index) {
        if (index < rows.length) {
          final (:job, :memory) = rows[index];
          if (memory == null) return _UploadRow(job: job!, online: online);
          return _row(context, memory, job, plan.memoryWindowDays);
        }

        if (isAppending && index == rows.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.card),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }

        // What the plan is costing them, stated as a restoration rather than
        // a loss — retention demotes, never deletes (§36), so these memories
        // are still here and upgrading genuinely brings them back.
        return GestureDetector(
          onTap: () => context.pushNamed(PaywallPage.routeName),
          behavior: HitTestBehavior.opaque,
          child: InfoNote(
            '$dormant memories are older than ${plan.memoryWindowDays} days. '
            'Still here — upgrading makes them answerable again.',
            icon: HawkIcons.shield,
          ),
        );
      },
    );
  }

  Widget _row(
    BuildContext context,
    Memory memory,
    UploadJob? job,
    int? windowDays,
  ) {
    // Still being followed and not finished: the row goes back to the
    // Indexing screen it came from, which says more than a half-read file
    // viewer would. Links and notes never had one.
    final toIndexing = job != null && !job.quiet && !job.isSettled;
    return MemoryRow(
      memory: memory,
      windowDays: windowDays,
      progress: job == null || job.quiet ? null : progressOf(job),
      justIndexed:
          job != null &&
          job.outcome == JobOutcome.ready &&
          DateTime.now().difference(job.addedAt) < const Duration(minutes: 2),
      // Into the viewer, not straight out to another app. v2 opened the
      // original in whatever the OS chose, which meant the row for a 90 MB
      // PDF fetched it from the vault before showing anything. 1M reads
      // from the index, which is already here.
      onTap: () => toIndexing
          ? context.pushNamed(
              IndexingPage.routeName,
              pathParameters: {'batchId': job.batchId},
            )
          : context.pushNamed(
              FileViewerPage.routeName,
              pathParameters: {'memoryId': memory.id},
            ),
    );
  }
}

/// A file picked through Upload that is not a memory yet — uploading,
/// queued behind another or waiting for a network (E5), or stopped (E6).
///
/// Drawn like every other row so the list does not jump when the memory
/// replaces it; only the mono line and the right-hand mark differ.
class _UploadRow extends StatelessWidget {
  const _UploadRow({required this.job, required this.online});

  final UploadJob job;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final stopped = job.phase == UploadPhase.stopped;
    final offline =
        !online &&
        (job.phase == UploadPhase.waiting ||
            job.phase == UploadPhase.uploading);

    return HawkRow(
      title: job.name,
      meta: 'JUST NOW · ${stateWordOf(job, online: online)}',
      metaColor: stopped ? p.danger : null,
      icon: iconForMemoryType(job.memoryType),
      onTap: () => context.pushNamed(
        IndexingPage.routeName,
        pathParameters: {'batchId': job.batchId},
      ),
      trailing: stopped
          ? Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: p.danger,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: AppIcon(
                UploadIcons.bang,
                size: 14,
                color: p.onAccent,
                strokeWidth: 3,
              ),
            )
          : offline
          ? AppIcon(
              UploadIcons.offline,
              size: 18,
              color: p.textMuted,
              strokeWidth: 2,
            )
          : ProgressRing(fraction: progressOf(job)),
    );
  }
}

/// Nothing captured yet.
///
/// Addressed to the button directly above it, because it is the answer. v2's
/// empty state was a vault glyph and two lines of copy on a screen with no way
/// to act on them — the capture screen was somewhere else entirely.
class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({this.filter = LibraryFilter.all});

  /// A narrowed list that is empty says which kind is missing, not that the
  /// vault is — the rows are still there under All.
  final LibraryFilter filter;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final narrowed = !filter.isAll;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.card),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Headline(
              narrowed
                  ? 'No ${filter.label.toLowerCase()} yet.'
                  : 'Nothing kept yet.',
              size: 22,
              align: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              narrowed
                  ? 'Nothing of that kind is kept. Switch back to All.'
                  : 'Upload a file, a photo or a link. '
                        'Ask for it later in your own words.',
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(color: p.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}

/// Three empty rows at the real height, rather than a spinner.
///
/// The list is the screen; a centred spinner where it will be makes the
/// layout jump when the rows land. Used on both tabs.
class _RowsPlaceholder extends StatelessWidget {
  const _RowsPlaceholder();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.gap),
          Container(
            height: 70,
            decoration: BoxDecoration(
              color: p.cardDim,
              borderRadius: BorderRadius.circular(AppRadius.row),
            ),
          ),
        ],
      ],
    );
  }
}

// ===========================================================================
// 1L — Drive
// ===========================================================================

/// The Drive tab.
///
/// The one screen in the product where a tap *removes* something, so it is
/// also the one that has to say what it removes. The note under the list is
/// not reassurance copy — it is the difference between "Index" being a
/// one-tap toggle and it needing a confirmation dialogue.
class _DriveTab extends StatelessWidget {
  const _DriveTab();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<DriveFilesCubit, DriveFilesState>(
      // A new error, or one more file out of the index. Not an error being
      // cleared — that is the cubit tidying up, and it is not news.
      listenWhen: (a, b) =>
          (b.exception != null && a.exception != b.exception) ||
          b.unindexed > a.unindexed,
      listener: (context, state) {
        final error = state.exception;
        if (error == null) {
          // The one removal where the file really is somewhere else and
          // really is untouched — so the design's sentence is literally
          // true here.
          getIt<SnackController>().show(
            const Snack.confirmation(
              message: 'Removed from your index. The file is untouched.',
            ),
          );
          return;
        }
        getIt<SnackController>().show(
          Snack.detail(
            title: 'Could not change that file',
            mark: SnackMark.failure,
            subtitle: error.displayMessage,
          ),
        );
        context.read<DriveFilesCubit>().dismissError();
      },
      builder: (context, state) {
        if (!state.isConnected && !state.isLoading) {
          return const _DriveNotConnected();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DriveAccountCard(state: state),
            const SizedBox(height: AppSpacing.lg),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Drive files',
                  style: AppTypography.titleLarge.copyWith(
                    fontSize: 15,
                    color: context.palette.textPrimary,
                  ),
                ),
                MetaText(state.countLine),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: state.isLoading
                  ? const _RowsPlaceholder()
                  : _DriveFileList(state: state),
            ),
          ],
        );
      },
    );
  }
}

class _DriveAccountCard extends StatelessWidget {
  const _DriveAccountCard({required this.state});

  final DriveFilesState state;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final account = state.account;

    return HawkCard(
      child: Row(
        children: [
          IconTile(
            icon: HawkIcons.googleDrive,
            size: AppSize.tileLarge,
            radius: 15,
            strokeWidth: 1.7,
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  account?.email ?? account?.displayName ?? 'Google Drive',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.titleLarge.copyWith(
                    color: p.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                MetaText(state.accountLine),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          // The design's live dot — the one accent on this tab. Present only
          // while the connection is healthy; a revoked account is not live,
          // and an accent dot beside "ACCESS REVOKED" would say it was.
          if (state.isConnected)
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: p.accent,
                shape: BoxShape.circle,
              ),
            ),
        ],
      ),
    );
  }
}

class _DriveFileList extends StatelessWidget {
  const _DriveFileList({required this.state});

  final DriveFilesState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<DriveFilesCubit>();
    // The note is the last item in the list rather than a pinned footer: it
    // is read once and then never again, and a permanent strip would spend a
    // row of the list saying it forever.
    final extras = (state.hasMore ? 1 : 0) + 1;

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: navClearance),
      itemCount: state.files.length + extras,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.gap),
      itemBuilder: (context, index) {
        if (index < state.files.length) {
          final file = state.files[index];
          return DriveFileRow(
            file: file,
            isBusy: state.pending.contains(file.id),
            onAction: () => file.indexed
                // An indexed Drive file opens in Drive, not in 1M: what we
                // hold is an index of it, and the document itself lives
                // where the user put it.
                //
                // The Drive file id stands in for `memoryId` because this row
                // has no memory of its own — the memory the indexer wrote is
                // a separate document with its own id, which the listing does
                // not carry. `OriginalAccess.resolve` looks for a kept local
                // copy under that id, finds none, and falls through to the
                // url, which is the intended route here.
                ? openOriginal((
                    memoryId: file.id,
                    title: file.name,
                    url:
                        'https://drive.google.com/open?id='
                        '${Uri.encodeQueryComponent(file.id)}',
                    storagePath: null,
                    fallback: null,
                  ))
                : cubit.toggleIndexed(file),
          );
        }

        if (state.hasMore && index == state.files.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: PillButton(
              label: state.isAppending ? 'Loading' : 'Show more',
              tone: PillTone.secondary,
              height: AppSize.buttonSmall,
              isBusy: state.isAppending,
              onPressed: cubit.loadMore,
            ),
          );
        }

        return const InfoNote(
          'Removing here only deletes the index. Drive files are never '
          'touched.',
          icon: HawkIcons.info,
        );
      },
    );
  }
}

/// No Drive account. A way in, not an apology.
class _DriveNotConnected extends StatelessWidget {
  const _DriveNotConnected();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HawkCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              IconTile(
                icon: HawkIcons.googleDrive,
                size: AppSize.tileLarge,
                radius: 15,
                strokeWidth: 1.7,
              ),
              const SizedBox(height: AppSpacing.inset),
              const Headline('Nothing connected', size: 18),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Connect Google Drive and pick which files Hawk reads. '
                'Originals stay where they live.',
                style: AppTypography.bodyMedium.copyWith(color: p.textTertiary),
              ),
              const SizedBox(height: AppSpacing.lg),
              PillButton(
                label: 'Connect Drive',
                icon: HawkIcons.arrowRight,
                onPressed: () =>
                    context.pushNamed(ConnectStoragePage.manageRouteName),
              ),
            ],
          ),
        ),
        const Spacer(),
        const SizedBox(height: navClearance),
      ],
    );
  }
}

String _grouped(int value) => value.toString().replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+$)'),
  (m) => '${m[1]},',
);
