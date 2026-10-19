import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/tab_shell.dart';
import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/config/legal_links.dart';
import '../../../../core/di/injector.dart';
import '../../../../core/error/error_mapper.dart';
import '../../../../core/feedback/snack.dart';
import '../../../../core/feedback/snack_controller.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../../../core/widgets/app_screen.dart';
import '../../../../core/widgets/hawk_icons.dart';
import '../../../../core/widgets/hawk_kit.dart';
import '../../../../core/widgets/plan_gate.dart';
import '../../../auth/domain/entities/auth_session.dart';
import '../../../auth/domain/entities/auth_user.dart';
import '../../../auth/domain/repositories/auth_repository.dart';
import '../../../auth/presentation/bloc/session_cubit.dart';
import '../../../auth/presentation/widgets/auth_header.dart';
import '../../../billing/domain/entities/store_product.dart';
import '../../../billing/domain/entities/subscription.dart';
import '../../../billing/domain/repositories/billing_repository.dart';
import '../../../billing/presentation/bloc/subscription_cubit.dart';
import '../../../billing/presentation/pages/billing_page.dart';
import '../../../billing/presentation/pages/paywall_page.dart';
import '../../../billing/presentation/widgets/plan_alert_actions.dart';
import '../../../billing/presentation/widgets/plan_alerts.dart';
import '../../data/privacy_settings.dart';
import '../../domain/entities/account_overview.dart';
import '../../domain/repositories/account_repository.dart';
import '../bloc/profile_cubit.dart';
import '../widgets/profile_pieces.dart';
import 'vault_page.dart';

/// Screen 1Q — PROFILE. The third tab.
///
/// Four blocks, ordered by how often each is wanted: who you are, what your
/// plan gives you, the three things you can change, and the ways out. The
/// exits are last and quietest — a destructive action does not need to be easy
/// to find, it needs to be impossible to take by accident.
///
/// **Storage lives here now.** v2 reached connected storage from a bottom-nav
/// dock, which gave a setup screen permanent equal billing with the two things
/// people do daily. v3 took it out of the nav entirely and put it behind
/// Vault, one row down — see [VaultPage]. The nav has three tabs and one of
/// them is this screen.
///
/// **The accent is the avatar.** It is the only accented thing on the screen
/// bar one: the design also sets the current "How you ask" value in accent
/// mono, because that row reports a live setting rather than offering an
/// action, and it is the only row of the three that has anything to say. The
/// plan card is white — the one thing on 1Q that matters — so its own action
/// is ink, never the accent.
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  static const routeName = 'profile';
  static const routePath = '/profile';

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<ProfileCubit>()..load(),
      child: const _ProfileView(),
    );
  }
}

class _ProfileView extends StatelessWidget {
  const _ProfileView();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ProfileCubit, ProfileState>(
      listenWhen: (a, b) =>
          (a.isDeleted != b.isDeleted && b.isDeleted) ||
          (a.error != b.error && b.error != null),
      listener: (context, state) async {
        final error = state.error;
        if (error != null) {
          // A snack rather than a panel in the layout. The screen's numbers
          // are all optional — a failed summary means a plan card with dashes
          // in it, not a screen that cannot be used — and an error block
          // between the avatar and the plan would push the whole design down
          // to report something the user cannot act on.
          getIt<SnackController>().show(
            Snack.detail(
              title: 'Could not load your account',
              mark: SnackMark.failure,
              subtitle: error.displayMessage,
            ),
          );
          context.read<ProfileCubit>().dismissError();
          return;
        }

        // The account is gone; the session is now a token for a user that
        // does not exist. Ending it here rather than in the cubit keeps the
        // ordering visible: delete first, *then* sign out, because the delete
        // call needs the session that the sign-out destroys.
        await context.read<SessionCubit>().signOut();
      },
      builder: (context, state) {
        final overview = state.overview;
        final deactivated = overview?.isDeactivated ?? false;

        return AppScreen(
          // v3 has no wash.
          ambientOpacity: 0,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _Identity(overview: overview),
              const SizedBox(height: AppSpacing.lg),

              const _PlanCard(),
              const _ProfileAlert(),
              const SizedBox(height: AppSpacing.group),

              RowGroup(
                children: [
                  SettingRow(
                    icon: HawkIcons.vault,
                    title: 'Vault and storage',
                    onTap: () => context.pushNamed(VaultPage.routeName),
                  ),
                  const _HowYouAskRow(),
                  // Screen 2J. Shown on every plan, not only paid ones:
                  // somebody whose subscription lapsed back to free still
                  // has receipts, and is the person most likely to look.
                  SettingRow(
                    icon: HawkIcons.file,
                    title: 'Billing and receipts',
                    onTap: () => context.pushNamed(BillingPage.routeName),
                  ),
                  ...paidPlanRows(context),
                  SettingRow(
                    icon: HawkIcons.shield,
                    title: 'Privacy and data',
                    onTap: () => _showPrivacy(context),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.group),

              if (deactivated) ...[
                const InfoNote(
                  'This account is deactivated. Nothing is being indexed and '
                  'storage is disconnected — every memory is still here.',
                  tone: CardTone.dark,
                ),
                const SizedBox(height: AppSpacing.gap),
              ],

              PillButton(
                label: 'Sign out',
                tone: PillTone.secondary,
                height: AppSize.buttonSmall,
                onPressed: state.isInteractive
                    ? () => context.read<SessionCubit>().signOut()
                    : null,
              ),
              const SizedBox(height: AppSpacing.gap),
              Row(
                children: [
                  Expanded(
                    child: PillButton(
                      label: deactivated ? 'Reactivate' : 'Deactivate',
                      // Quieter than its neighbour: the pair must not read as
                      // two equally-weighted destructive actions.
                      tone: PillTone.tertiary,
                      height: AppSize.buttonSmall,
                      isBusy:
                          state.action == AccountAction.deactivating ||
                          state.action == AccountAction.reactivating,
                      onPressed: state.isInteractive
                          ? () => deactivated
                                ? context.read<ProfileCubit>().reactivate()
                                : _confirmDeactivate(context)
                          : null,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.gap),
                  Expanded(
                    child: PillButton(
                      label: 'Delete account',
                      // Red ink on its own tinted bed, never a red fill: a
                      // filled red button is the easiest thing on a screen to
                      // press by accident, and this is the one action on 1Q
                      // that cannot be walked back.
                      tone: PillTone.danger,
                      height: AppSize.buttonSmall,
                      isBusy: state.action == AccountAction.deleting,
                      onPressed: state.isInteractive
                          ? () => _confirmDelete(context)
                          : null,
                    ),
                  ),
                ],
              ),

              // 1Q is a tab root, so the floating nav pill runs over the
              // bottom of it. The last thing in the body reserves the room.
              const SizedBox(height: navClearance),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmDeactivate(BuildContext context) async {
    final cubit = context.read<ProfileCubit>();
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _DeactivateSheet(),
    );
    if (confirmed ?? false) await cubit.deactivate();
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final cubit = context.read<ProfileCubit>();
    final plan = context.read<SubscriptionCubit>().state;
    final phrase = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _DeleteSheet(
        // Read here, not inside the sheet: the sheet is pushed on the root
        // navigator and does not inherit this screen's providers.
        memories: cubit.state.overview?.indexed ?? 0,
        // Null on a free plan, where there is no subscription to end and a
        // line claiming one would be the screen inventing a loss.
        plan: plan.tier == Tier.free ? null : plan.tier.label,
      ),
    );
    // The cubit checks the phrase again. The sheet's check is a courtesy —
    // it keeps the button dead until the word is right — and the cubit's is
    // the rule, so a future caller that skips the sheet still cannot delete
    // anything by passing an empty string.
    if (phrase != null) await cubit.delete(phrase);
  }

  static Future<void> _showPrivacy(BuildContext context) {
    // Read here: the sheet is its own route, above this page's providers.
    final cubit = context.read<ProfileCubit>();
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _PrivacySheet(
        marketing: cubit.state.overview?.marketingOptIn ?? true,
        onMarketing: (optIn) => cubit.setMarketing(optIn: optIn),
      ),
    );
  }
}

/// Avatar, name, address.
///
/// The name comes from the summary when it has arrived and from the session
/// otherwise, so the screen is never blank while a callable is in flight —
/// the session has been in memory since launch and already knows both.
class _Identity extends StatelessWidget {
  const _Identity({required this.overview});

  final AccountOverview? overview;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return BlocBuilder<SessionCubit, AuthStatus>(
      builder: (context, status) {
        final user = switch (status) {
          AuthAuthenticated(:final user) => user,
          AuthOnboarding(:final user) => user,
          _ => null,
        };
        final name = overview?.name?.trim().isNotEmpty ?? false
            ? overview!.name!.trim()
            : (user?.displayName ?? '');
        final email = overview?.email ?? user?.email ?? '';

        return Row(
          children: [
            Container(
              width: AppSize.avatarLarge,
              height: AppSize.avatarLarge,
              decoration: BoxDecoration(
                // The screen's one accent. v2 gave the avatar a two-hue
                // gradient, which was the only gradient in the product and the
                // first thing v3 deleted: a flat accent circle says "this is
                // you" at least as well and does not need a second colour to
                // do it.
                color: p.accent,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                initialsOf(name.isEmpty ? email.split('@').first : name),
                style: AppTypography.display18.copyWith(color: p.onAccent),
              ),
            ),
            const SizedBox(width: AppSpacing.group),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name.isEmpty ? 'Your vault' : name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.display24.copyWith(
                      color: p.textPrimary,
                    ),
                  ),
                  if (email.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    MetaText(email),
                  ],
                  if (overview?.isTestAccount ?? false) ...[
                    const SizedBox(height: 4),
                    // Deliberately loud, and deliberately not the accent:
                    // this account is being given the top tier without paying,
                    // and a privileged path that says nothing about itself is
                    // one that ships to production.
                    MetaText('Test account', color: p.danger),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The white card: the tier, the way up, and what the plan is spending.
///
/// Read from `SubscriptionCubit` rather than from the account summary, which
/// also reports a tier and both allowances. Two live copies of the same fact
/// is how two screens come to disagree about what a plan permits — and the
/// subscription is the one that *streams*, so a purchase made on another
/// device lands here without reopening the screen.
class _PlanCard extends StatelessWidget {
  const _PlanCard();

  @override
  Widget build(BuildContext context) {
    final paper = AppPalette.onPaper;
    final plan = context.plan;

    return HawkCard(
      tone: CardTone.paper,
      padding: const EdgeInsets.all(AppSpacing.cardWide),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MetaText('Your plan', wide: true, color: paper.muted),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Headline(plan.tier.label, size: 32, color: paper.ink),
                        // 1U's trial chip. Only while actually in a trial,
                        // and only with a real end date to count to — a
                        // "TRIAL" badge with no number is the kind of thing
                        // people read as "you are about to be charged, we
                        // won't say when".
                        if (plan.status == SubscriptionStatus.inTrial &&
                            _trialDaysLeft(plan) != null) ...[
                          const SizedBox(width: AppSpacing.sm),
                          InlineChip(
                            label: 'TRIAL · ${_trialDaysLeft(plan)} DAYS',
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              // Hidden on the top tier. An upgrade button that cannot upgrade
              // anything is the app selling something it has already sold.
              if (plan.canUpgrade)
                PaperAction(
                  label: 'Upgrade',
                  onPressed: () => context.pushNamed(PaywallPage.routeName),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.card),
          PaperMeter(
            label: 'Storage',
            value: _size(plan.index),
            fraction: plan.index.isUnlimited ? null : plan.index.fraction,
          ),
          const SizedBox(height: AppSpacing.inset),
          PaperMeter(
            // The design's string is "Asks this month". The meter shows the
            // *week*, which is the allowance that runs out and stays out —
            // the two-hour window refills by itself — and the label says the
            // period the number is actually for.
            label: 'Answers this week',
            value: plan.week.isUnlimited
                ? 'Unlimited'
                : '${plan.week.used} / ${plan.week.limit}',
            fraction: plan.week.isUnlimited ? null : plan.week.fraction,
          ),
          const SizedBox(height: AppSpacing.inset),
          Text(
            // 1U prints "Renews 29 Sep 2026 at $96. Memories kept forever."
            // The price is missing on purpose: it lives on the StoreProduct,
            // not on the subscription, and fetching the catalogue to print
            // one number would make the profile wait on the store. The date
            // is the half that matters and it is the half we hold.
            [_renewal(plan), _retention(plan)].whereType<String>().join(' '),
            style: AppTypography.footnote.copyWith(color: paper.muted),
          ),
        ],
      ),
    );
  }

  /// Whole days until the trial ends, or null when there is no end date to
  /// count to.
  static int? _trialDaysLeft(Subscription plan, {DateTime? now}) {
    final end = plan.currentPeriodEnd;
    if (end == null) return null;
    final left = end.difference(now ?? DateTime.now()).inDays;
    return left > 0 ? left : null;
  }

  /// "Renews 29 Sep 2026." — or nothing at all.
  ///
  /// Silent on a plan that is not renewing, which is the case that matters:
  /// somebody who has cancelled must not read a renewal date, and somebody
  /// on free has nothing to renew.
  static String? _renewal(Subscription plan) {
    final end = plan.currentPeriodEnd;
    if (!plan.autoRenewing || end == null || plan.tier == Tier.free) {
      return null;
    }
    return 'Renews ${_day(end)}.';
  }

  /// "29 Sep 2026". Spelled out rather than 29/09/2026, which reads as a
  /// different date entirely to half the world.
  static String _day(DateTime date) {
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
    final local = date.toLocal();
    return '${local.day} ${months[local.month - 1]} ${local.year}';
  }

  static String _size(Allowance index) {
    final limit = index.limit;
    if (limit == null) return 'Unlimited';
    return byteRatio(index.used, limit);
  }

  /// Built from the plan rather than written out, because the sentence is a
  /// *fact about this account* and the design's copy is the free tier's
  /// version of it. Someone on Premium reading "kept 30 days on Free" would
  /// have no way to tell whether it applied to them.
  static String _retention(Subscription plan) {
    final days = plan.memoryWindowDays;
    if (days == null) {
      return 'Memories are kept forever on ${plan.tier.label}.';
    }
    return 'Memories are kept $days days on ${plan.tier.label}, forever on '
        '${Tier.premium.label}.';
  }
}

/// The one row on 1Q that both reports a setting and changes it.
///
/// Its own widget because it is the only part of the screen that watches the
/// session: the value is read from `SessionCubit`, which is fed by a Firestore
/// snapshot listener on the user's own document. So the write below does not
/// need to emit anything — it changes the document, the listener fires, and
/// this row redraws with the new value. The same path a change made on another
/// device takes.
class _HowYouAskRow extends StatelessWidget {
  const _HowYouAskRow();

  @override
  Widget build(BuildContext context) {
    final preference = switch (context.watch<SessionCubit>().state) {
      AuthAuthenticated(:final user) => user.inputPreference,
      AuthOnboarding(:final user) => user.inputPreference,
      _ => InputPreference.voice,
    };

    return SettingRow(
      icon: preference == InputPreference.voice
          ? HawkIcons.mic
          : HawkIcons.type,
      title: 'How you ask',
      value: preference == InputPreference.voice ? 'Voice' : 'Typing',
      onTap: () => _change(context, preference),
    );
  }

  static Future<void> _change(
    BuildContext context,
    InputPreference current,
  ) async {
    final chosen = await showModalBottomSheet<InputPreference>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _HowYouAskSheet(current: current),
    );
    if (chosen == null || chosen == current) return;

    try {
      // Written straight to the user's own document. `firestore.rules` allows
      // the owner exactly four keys here and pins this one to 'voice' or
      // 'typing', so the validation that matters is already server-side and a
      // callable would be a round trip to set a string.
      await getIt<AuthRepository>().setInputPreference(chosen);
      getIt<SnackController>().show(
        Snack.confirmation(
          message: chosen == InputPreference.voice
              ? 'Home opens to the orb'
              : 'Home opens to a thread',
        ),
      );
    } catch (error, stackTrace) {
      getIt<SnackController>().show(
        Snack.detail(
          title: 'Not saved',
          mark: SnackMark.failure,
          subtitle: ErrorMapper.map(error, stackTrace).displayMessage,
        ),
      );
    }
  }
}

/// The picker behind "How you ask".
///
/// Two rows, not a toggle. The choice decides which screen the app opens to,
/// and each option needs a sentence to say so — a switch labelled "Voice"
/// would make the consequence invisible, which is exactly what screen 1F
/// spends a whole onboarding step avoiding.
class _HowYouAskSheet extends StatelessWidget {
  const _HowYouAskSheet({required this.current});

  final InputPreference current;

  @override
  Widget build(BuildContext context) => PaperSheet(
    headline: 'How will you\nmostly ask?',
    footnote: 'This sets what home opens to. Change it any time.',
    children: [
      _Option(
        icon: HawkIcons.mic,
        title: 'Speak',
        subtitle: 'Home is the orb. Hold, ask, let go.',
        selected: current == InputPreference.voice,
        onTap: () => Navigator.of(context).pop(InputPreference.voice),
      ),
      const SizedBox(height: AppSpacing.gap),
      _Option(
        icon: HawkIcons.type,
        title: 'Type',
        subtitle: 'Home is a chat thread, keyboard first.',
        selected: current == InputPreference.typing,
        onTap: () => Navigator.of(context).pop(InputPreference.typing),
      ),
    ],
  );
}

/// One option on paper.
///
/// Screen 1F draws the same two choices on the ground, where the selected one
/// goes white. Inside a white sheet there is no whiter surface to go to, so
/// selection is carried by the ink dot on the right and the inset grey bed —
/// the same inversion `SegmentedTabs` makes for the same reason.
class _Option extends StatelessWidget {
  const _Option({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final paper = AppPalette.onPaper;

    return Semantics(
      button: true,
      selected: selected,
      label: '$title. $subtitle',
      excludeSemantics: true,
      child: Material(
        color: selected ? paper.chip : paper.surface,
        borderRadius: BorderRadius.circular(AppRadius.row),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.inset),
            child: Row(
              children: [
                AppIcon(icon, size: 19, color: paper.ink, strokeWidth: 1.9),
                const SizedBox(width: AppSpacing.group),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: AppTypography.titleMedium.copyWith(
                          color: paper.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: AppTypography.footnote.copyWith(
                          color: paper.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: selected ? paper.ink : Colors.transparent,
                    shape: BoxShape.circle,
                    border: selected
                        ? null
                        : Border.all(color: paper.handle, width: 2),
                  ),
                  alignment: Alignment.center,
                  child: selected
                      ? AppIcon(HawkIcons.check, size: 12, color: paper.surface)
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// What Hawk holds, said once in full.
///
/// A sheet rather than a screen because there is nothing on it to do. It
/// exists so the "Privacy and data" row leads somewhere — a settings row with
/// a chevron and no destination is the most common small lie in a settings
/// screen, and the promise this one makes is the product's central claim.
class _PrivacySheet extends StatefulWidget {
  const _PrivacySheet({required this.marketing, required this.onMarketing});

  /// Offers and news by email, as the server last reported it.
  final bool marketing;

  /// Saves the choice. False when the server refused it.
  final Future<bool> Function(bool optIn) onMarketing;

  @override
  State<_PrivacySheet> createState() => _PrivacySheetState();
}

/// Screen 2K — PRIVACY AND DATA.
///
/// Rebuilt from three paragraphs of prose into the design's list of
/// switches, with one rule applied throughout: **a control that does nothing
/// is worse than no control**. A privacy screen is the exact place a user
/// checks whether the app is telling the truth, so a switch that stores a
/// preference nothing honours would poison the one screen that cannot afford
/// to be decorative.
///
/// So each row is either live or visibly not ready, in the same way
/// `CaptureKind.scan` refuses to pretend. Crash reports and offers and news
/// by email are live (the second is recorded on the server by
/// `set_marketing_consent`), and the rest carry what they are waiting for:
///
/// * **Lock with Face ID** — needs `local_auth` and the platform usage
///   strings; a dependency decision, not an afternoon.
/// * **Index on Wi-Fi only** — the sync runs *server-side*
///   (`connector_sync.py`), so a client-held preference cannot gate it. It
///   has to travel to the server before the switch can mean anything.
/// * **Export my data** and **Clear the index** — neither callable exists;
///   `delete_account` is a different, heavier thing.
/// * **Privacy policy** and **Terms of service** are live: they open the
///   landing site's `/privacy` and `/terms` pages ([LegalLinks]).
class _PrivacySheetState extends State<_PrivacySheet> {
  late bool _crash = PrivacySettings.crashReportsEnabled;
  late bool _marketing = widget.marketing;

  Future<void> _setMarketing(bool next) async {
    setState(() => _marketing = next);
    final saved = await widget.onMarketing(next);
    if (saved || !mounted) return;
    setState(() => _marketing = !next);
    getIt<SnackController>().show(
      const Snack.detail(
        title: "Couldn't save that",
        subtitle: 'Try again in a moment.',
        mark: SnackMark.failure,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final paper = AppPalette.onPaper;

    return PaperSheet(
      // Said the way the privacy policy says it. The design's headline was
      // "Everything is indexed on this device", and it is not: the index is
      // built on Hawk's servers and files are read by Gemini. This screen
      // links to the policy two rows down, so the two must not disagree —
      // and a privacy screen is the one place an overstatement is a lie.
      headline: 'What Hawk\nkeeps, and\nwhere',
      footnote: 'Clearing the index never deletes your original files.',
      children: [
        const _Para(
          'Files in your Google Drive stay in your Drive — Hawk keeps the '
          'text it reads and a pointer back, not a copy. What you capture in '
          'the app is kept in your Hawk account, so it opens on any device. '
          'The search index itself — the vectors made from that text — is '
          'kept on this phone, not in the cloud. To read files and answer '
          "questions, text is sent to Google's Gemini API.",
        ),
        const SizedBox(height: AppSpacing.card),

        _PrivacySwitch(
          title: 'Crash reports',
          subtitle: 'Anonymous, no file names',
          value: _crash,
          onChanged: (next) {
            setState(() => _crash = next);
            unawaited(PrivacySettings.setCrashReports(enabled: next));
          },
        ),
        const SizedBox(height: AppSpacing.gap),
        _PrivacySwitch(
          title: 'Offers and news by email',
          subtitle: 'Occasional, unsubscribe any time',
          value: _marketing,
          onChanged: (next) => unawaited(_setMarketing(next)),
        ),
        const SizedBox(height: AppSpacing.gap),
        const _PrivacySwitch(
          title: 'Lock with Face ID',
          subtitle: 'Required to open Hawk',
          value: false,
          pending: true,
        ),
        const SizedBox(height: AppSpacing.gap),
        const _PrivacySwitch(
          title: 'Index on Wi-Fi only',
          subtitle: 'Applies to Drive sync',
          value: false,
          pending: true,
        ),

        const SizedBox(height: AppSpacing.card),
        const _PrivacyAction(title: 'Export my data', pending: true),
        const SizedBox(height: AppSpacing.gap),
        const _PrivacyAction(title: 'Clear the index', pending: true),
        const SizedBox(height: AppSpacing.gap),
        _PrivacyAction(
          title: 'Privacy policy',
          onTap: () => unawaited(LegalLinks.open(LegalLinks.privacy)),
        ),
        const SizedBox(height: AppSpacing.gap),
        _PrivacyAction(
          title: 'Terms of service',
          onTap: () => unawaited(LegalLinks.open(LegalLinks.terms)),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Deactivating disconnects storage and stops indexing. Every memory '
          'stays, and signing in again brings it all back.',
          style: AppTypography.footnote.copyWith(color: paper.muted),
        ),
      ],
    );
  }
}

/// A 2K switch. [pending] means the mechanism behind it does not exist yet,
/// which is said on the row rather than hidden behind a dead toggle.
class _PrivacySwitch extends StatelessWidget {
  const _PrivacySwitch({
    required this.title,
    required this.subtitle,
    required this.value,
    this.onChanged,
    this.pending = false,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final paper = AppPalette.onPaper;

    return Opacity(
      opacity: pending ? 0.45 : 1,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.bodyMedium.copyWith(
                    fontWeight: FontWeight.w700,
                    color: paper.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  pending ? 'Not available yet' : subtitle,
                  style: AppTypography.bodySmall.copyWith(color: paper.muted),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: pending ? null : onChanged,
            activeThumbColor: paper.ink,
          ),
        ],
      ),
    );
  }
}

/// A 2K row that performs something rather than toggling it.
///
/// Carries no `onTap` yet, and deliberately: all three of the design's
/// actions — export, clear the index, terms — are waiting on something that
/// does not exist, so a tap handler here would have nothing to call. It
/// grows one the moment the first of them lands.
class _PrivacyAction extends StatelessWidget {
  const _PrivacyAction({required this.title, this.pending = false, this.onTap});

  final String title;
  final bool pending;

  /// Where the row goes. A row with somewhere to go says so with an arrow;
  /// one without says it is not ready, never neither.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final paper = AppPalette.onPaper;

    return Semantics(
      button: onTap != null,
      label: title,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: pending ? null : onTap,
        behavior: HitTestBehavior.opaque,
        child: Opacity(
          opacity: pending ? 0.45 : 1,
          child: Padding(
            // The text is 14.5px; the target is not.
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: AppTypography.bodyMedium.copyWith(
                      fontWeight: FontWeight.w700,
                      color: paper.ink,
                    ),
                  ),
                ),
                if (pending)
                  Text(
                    'Not available yet',
                    style: AppTypography.bodySmall.copyWith(color: paper.muted),
                  )
                else if (onTap != null)
                  AppIcon(HawkIcons.arrowUpRight, size: 16, color: paper.ink),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Para extends StatelessWidget {
  const _Para(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: AppTypography.bodySmall.copyWith(color: AppPalette.onPaper.body),
  );
}

/// The reversible exit, asked as a question with the answer in it.
class _DeactivateSheet extends StatelessWidget {
  const _DeactivateSheet();

  @override
  Widget build(BuildContext context) => PaperSheet(
    headline: 'Deactivate\nthis account?',
    children: [
      const _Para(
        'Your connected storage is disconnected and indexing stops. Every '
        'memory you have saved stays exactly where it is, and signing in '
        'again brings it all back — you will just need to reconnect storage.',
      ),
      const SizedBox(height: AppSpacing.card),
      _InkButton(
        label: 'Deactivate',
        onPressed: () => Navigator.of(context).pop(true),
      ),
      const SizedBox(height: AppSpacing.gap),
      _GhostButton(
        label: 'Keep it active',
        onPressed: () => Navigator.of(context).pop(false),
      ),
    ],
  );
}

/// The final exit. Typed, not tapped.
///
/// A confirmation dialog is one tap from the button that opened it, and that
/// button is one tap from a scroll. Requiring the word makes deletion
/// something a person *decides* rather than something a thumb does — and the
/// server demands the same phrase, so a client that skipped this still could
/// not delete anything.
class _DeleteSheet extends StatefulWidget {
  const _DeleteSheet({required this.memories, required this.plan});

  /// Indexed memories this will erase. Zero is a real answer and the line is
  /// dropped rather than reading "0 indexed memories".
  final int memories;

  /// The paid plan's name, or null on free.
  final String? plan;

  @override
  State<_DeleteSheet> createState() => _DeleteSheetState();
}

class _DeleteSheetState extends State<_DeleteSheet> {
  final _controller = TextEditingController();

  bool get _matches =>
      _controller.text.trim().toUpperCase() == AccountRepository.deletePhrase;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final paper = AppPalette.onPaper;

    return PaperSheet(
      headline: 'Delete your\naccount?',
      footnote: 'This cannot be undone.',
      children: [
        const _Para(
          'This removes your profile, subscription and the entire index. '
          'Your original files and Drive stay untouched.',
        ),
        const SizedBox(height: AppSpacing.inset),

        // Screen 2L's ledger. The sheet's whole argument is that deleting an
        // account is not one undifferentiated loss: two things end, one
        // thing does not, and the last line is the one that changes minds.
        // Each entry is a fact this screen can actually check — a count it
        // was handed, a plan it can name — so nothing here is a guess.
        DeleteLedger(memories: widget.memories, plan: widget.plan),
        const SizedBox(height: AppSpacing.card),
        MetaText(
          'Type ${AccountRepository.deletePhrase} to confirm',
          color: paper.muted,
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _controller,
          autocorrect: false,
          enableSuggestions: false,
          textCapitalization: TextCapitalization.characters,
          onChanged: (_) => setState(() {}),
          style: AppTypography.numeral.copyWith(fontSize: 16, color: paper.ink),
          decoration: InputDecoration(
            filled: true,
            fillColor: paper.chip,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.inset,
              vertical: AppSpacing.inset,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.row),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.card),
        _InkButton(
          label: 'Delete account',
          danger: true,
          onPressed: _matches
              ? () => Navigator.of(context).pop(_controller.text.trim())
              : null,
        ),
        const SizedBox(height: AppSpacing.gap),
        _GhostButton(
          label: 'Keep my account',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

/// Screen 2L's ledger — what this delete ends, and what it does not.
///
/// The sheet's whole argument is that deleting an account is not one
/// undifferentiated loss. Two things end; one thing does not; and the last
/// line is the one that changes minds, because "my files are gone" is the
/// fear and it is not true — §36 again, from the other direction.
///
/// Every entry is a fact this screen was handed, never a guess. A zero count
/// drops its line rather than reading "0 indexed memories", and a free plan
/// has no subscription line at all: inventing a loss to make the warning
/// heavier would be the one dishonest thing a delete confirmation can do.
class DeleteLedger extends StatelessWidget {
  const DeleteLedger({required this.memories, required this.plan, super.key});

  final int memories;
  final String? plan;

  @override
  Widget build(BuildContext context) {
    final paper = AppPalette.onPaper;
    final loses = <String>[
      if (memories > 0) '${grouped(memories)} indexed memories',
      if (plan != null) '$plan subscription, effective now',
    ];

    return Container(
      decoration: BoxDecoration(
        color: paper.chip,
        borderRadius: BorderRadius.circular(AppRadius.panel),
      ),
      padding: const EdgeInsets.all(AppSpacing.inset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in loses) ...[
            _Loses(text: line),
            const SizedBox(height: 10),
          ],
          const _Keeps(text: 'Your files and Drive are kept'),
        ],
      ),
    );
  }

  /// 1516 -> 1,516. An ungrouped four-figure count in a sentence about loss
  /// reads as a reference number rather than as an amount.
  @visibleForTesting
  static String grouped(int n) => n.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (m) => '${m[1]},',
  );
}

/// A line in 2L's ledger: something this delete ends.
class _Loses extends StatelessWidget {
  const _Loses({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => _LedgerLine(
    icon: HawkIcons.close,
    // Ink, not red. The red in this sheet is spent once, on the button that
    // performs the deletion; a list of red crosses reads as an error report
    // about something that has already gone wrong.
    color: AppPalette.onPaper.ink,
    text: text,
  );
}

/// A line in 2L's ledger: something this delete does **not** touch.
class _Keeps extends StatelessWidget {
  const _Keeps({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => _LedgerLine(
    icon: HawkIcons.check,
    color: const Color(0xFF5A8F6B),
    text: text,
    muted: true,
  );
}

class _LedgerLine extends StatelessWidget {
  const _LedgerLine({
    required this.icon,
    required this.color,
    required this.text,
    this.muted = false,
  });

  final String icon;
  final Color color;
  final String text;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final paper = AppPalette.onPaper;
    return Row(
      children: [
        AppIcon(icon, size: 16, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: AppTypography.bodySmall.copyWith(
              fontWeight: FontWeight.w600,
              color: muted ? paper.body : paper.ink,
            ),
          ),
        ),
      ],
    );
  }
}

/// A sheet's primary action.
///
/// [PillButton] is the screen's button and it paints itself from the dark
/// palette; on paper its `secondary` tone is a near-black fill on white, which
/// is right, but its `primary` is the accent and its `danger` is a red wash
/// tuned for #0c0c0d. So the sheet has its own, in ink and in red-on-paper.
///
/// Candidate for the kit alongside `InlineChip.paper`: one `onPaper` flag on
/// `PillButton` would cover both.
///
/// The destructive pair is hard-coded here because [AppPalette.onPaper] has no
/// red. `danger`/`dangerWash` are tuned for #0c0c0d — #ff6a5a on white is a
/// pale coral that fails contrast at button size, and #241516 on white is a
/// bruise. These two keep the design's rule intact on the other surface: red
/// ink on its own tinted bed, never a red fill. They want to be
/// `onPaper.danger` and `onPaper.dangerWash`; see the report.
class _InkButton extends StatelessWidget {
  const _InkButton({required this.label, this.onPressed, this.danger = false});

  final String label;
  final VoidCallback? onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final paper = AppPalette.onPaper;
    final enabled = onPressed != null;
    final dangerInk = paper.danger;
    final dangerBed = paper.dangerWash;

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Material(
        color: enabled ? (danger ? dangerBed : paper.ink) : paper.chip,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            height: AppSize.buttonMedium,
            child: Center(
              child: Text(
                label,
                style: AppTypography.button.copyWith(
                  color: enabled
                      ? (danger ? dangerInk : paper.surface)
                      : paper.muted,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The way out of a sheet. A labelled action, not a greyed-out hint: backing
/// out of deleting your account is a real choice and the most likely one.
class _GhostButton extends StatelessWidget {
  const _GhostButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onPressed,
    style: TextButton.styleFrom(
      minimumSize: const Size.fromHeight(AppSize.buttonSmall),
      shape: const StadiumBorder(),
    ),
    child: Text(
      label,
      style: AppTypography.button.copyWith(color: AppPalette.onPaper.muted),
    ),
  );
}

/// Screen 1X's profile slot: payment trouble, the trial strip, or a pending
/// downgrade — whichever applies, and only one.
///
/// Stateful for one reason: the trial strip names the amount ("$96 on
/// 29 Sep unless cancelled"), and the amount is the store's. The catalogue
/// is fetched once, and only while a trial is actually running — nobody
/// else's profile waits on the store.
class _ProfileAlert extends StatefulWidget {
  const _ProfileAlert();

  @override
  State<_ProfileAlert> createState() => _ProfileAlertState();
}

class _ProfileAlertState extends State<_ProfileAlert> {
  Future<List<StoreProduct>>? _catalogue;

  @override
  Widget build(BuildContext context) {
    final plan = context.plan;
    if (plan.status == SubscriptionStatus.inTrial) {
      _catalogue ??= getIt<BillingRepository>().products().catchError(
        (Object _) => const <StoreProduct>[],
      );
    }

    return FutureBuilder<List<StoreProduct>>(
      future: _catalogue,
      builder: (context, snap) {
        String? price;
        for (final p in snap.data ?? const <StoreProduct>[]) {
          if (p.productId == plan.productId) price = p.price;
        }
        final alert = profileAlert(plan, price: price);
        if (alert == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.md),
          child: PlanAlertCard(
            alert: alert,
            onAction: () => onPlanAlert(context, alert),
          ),
        );
      },
    );
  }
}
