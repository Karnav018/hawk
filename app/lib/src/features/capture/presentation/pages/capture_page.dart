import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/pop_or.dart';
import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/di/injector.dart';
import '../../../../core/feedback/snack.dart';
import '../../../../core/feedback/snack_controller.dart';
import '../../../../core/validation/validators.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../../../core/widgets/hawk_icons.dart';
import '../../../../core/widgets/hawk_kit.dart';
import '../../../billing/presentation/bloc/subscription_cubit.dart';
import '../../../billing/presentation/pages/paywall_page.dart';
import '../../../memory/presentation/pages/library_page.dart';
import '../bloc/capture_cubit.dart';
import '../bloc/upload_center.dart';
import '../widgets/saved_snack.dart';
import '../widgets/upload_icons.dart';
import '../widgets/upload_sheets.dart';

/// SAVE A LINK — F4·3, and its error, E8.
///
/// **Dark, like every sheet in the Upload flow.** The first v3 cut drew this
/// on white paper; the Library redesign puts every step of adding something
/// on the same #191a1b sheet, so the link does not look like it came from a
/// different app halfway through the flow.
///
/// **The clipboard goes in first.** Most links arrive by copy: somebody was
/// reading the page a moment ago. If the clipboard holds a url it is already
/// in the field, marked as pasted, and saving is one tap. Anything else on
/// the clipboard is left alone.
///
/// **Errors stay in the sheet (E8).** The url is still there to fix, so a
/// failure is a red line under the field, not an island that would have to
/// be read somewhere else and then acted on here.
///
/// Links skip the Indexing screen (F4·4): the sheet closes, the row appears
/// at the top of the Library reading, and the island says so once.
class AddLinkSheet extends StatefulWidget {
  const AddLinkSheet({super.key});

  static const routeName = 'addLink';
  static const routePath = '/add-link';

  @override
  State<AddLinkSheet> createState() => _AddLinkSheetState();
}

class _AddLinkSheetState extends State<AddLinkSheet> {
  final _url = TextEditingController();
  final _focus = FocusNode();
  bool _fromClipboard = false;

  @override
  void initState() {
    super.initState();
    _prefill();
  }

  /// `hasStrings` first: it asks without reading, so a clipboard with no
  /// text in it never triggers the system's paste prompt.
  Future<void> _prefill() async {
    try {
      if (!await Clipboard.hasStrings()) return;
      final text = (await Clipboard.getData(
        Clipboard.kTextPlain,
      ))?.text?.trim();
      if (!mounted || text == null || _url.text.isNotEmpty) return;
      final uri = Uri.tryParse(text);
      final isWeb =
          uri != null &&
          (uri.scheme == 'http' || uri.scheme == 'https') &&
          uri.host.isNotEmpty;
      if (!isWeb || !Validators.captureUrl(text).isValid) return;
      _url.text = text;
      context.read<CaptureCubit>().urlPasted(text);
      setState(() => _fromClipboard = true);
    } on PlatformException {
      // No clipboard access is the same as an empty clipboard.
    }
  }

  @override
  void dispose() {
    _url.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _close() => context.popOrGo(LibraryPage.routeName);

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final cubit = context.read<CaptureCubit>();
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;

    return BlocConsumer<CaptureCubit, CaptureState>(
      listenWhen: (a, b) =>
          a.captured != b.captured ||
          (b.exception != null && a.exception != b.exception),
      listener: (context, state) {
        final error = state.exception;
        if (error != null) {
          // The save itself failed — the design's "Could not save that
          // link". The sheet stays up with the url in it, so trying again is
          // one tap.
          getIt<SnackController>().show(
            Snack.detail(
              title: 'Could not save that link',
              subtitle: error.displayMessage,
              mark: SnackMark.failure,
            ),
          );
          cubit.dismissError();
          return;
        }
        final memory = state.captured;
        if (memory == null) return;
        cubit.acknowledge();
        getIt<UploadCenter>().follow(memory, kind: CaptureKind.links);
        getIt<SnackController>().show(
          savedSnack(
            context.read<SubscriptionCubit>().state,
            count: 1,
            onKeep: () => context.pushNamed(PaywallPage.routeName),
          ),
        );
        _close();
      },
      builder: (context, state) {
        // Inline only for the url itself (E8): a save that failed is news,
        // and goes to the island above.
        final error = state.urlError;

        return Material(
          type: MaterialType.transparency,
          child: Stack(
            children: [
              // The dim, and a way out by tapping it.
              Positioned.fill(
                child: GestureDetector(
                  onTap: _close,
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.64),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: keyboard,
                child: UploadSheet(
                  bottom: keyboard > 0 ? AppSpacing.lg : AppSpacing.xxl,
                  children: [
                    const SheetHeader(title: 'Save a link'),
                    const SizedBox(height: AppSpacing.inset),
                    _UrlField(
                      controller: _url,
                      focus: _focus,
                      hasError: error != null,
                      onChanged: (value) {
                        if (_fromClipboard) {
                          setState(() => _fromClipboard = false);
                        }
                        cubit.urlChanged(value);
                      },
                      onBlur: cubit.urlBlurred,
                      onSubmitted: (_) => cubit.saveLink(),
                    ),
                    const SizedBox(height: 10),
                    if (error != null)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: AppIcon(
                              UploadIcons.alert,
                              size: 15,
                              color: p.danger,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              error,
                              style: AppTypography.caption.copyWith(
                                fontSize: 12.5,
                                color: p.danger,
                              ),
                            ),
                          ),
                        ],
                      )
                    else
                      MetaText(
                        _fromClipboard
                            ? 'Pasted from clipboard'
                            : 'Pages behind a login won’t work',
                        color: p.textFaint,
                      ),
                    const SizedBox(height: AppSpacing.inset),
                    PillButton(
                      label: 'Save link',
                      height: AppSize.buttonSmall,
                      isBusy: state.isSubmitting,
                      onPressed: state.canSaveLink ? cubit.saveLink : null,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The `/capture` route, until the router drops it.
///
/// Kept only because the answer screen's dock still navigates to `/capture`.
/// It renders the sheet, so the destination is at least the right one.
class CapturePage extends StatelessWidget {
  const CapturePage({super.key});

  static const routeName = 'capture';
  static const routePath = '/capture';

  @override
  Widget build(BuildContext context) => const AddLinkSheet();
}

/// The url field: raised grey, a link glyph, and a 2px ring — accent while
/// typing, red when the url is wrong.
class _UrlField extends StatefulWidget {
  const _UrlField({
    required this.controller,
    required this.focus,
    required this.hasError,
    required this.onChanged,
    required this.onBlur,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final bool hasError;
  final ValueChanged<String> onChanged;
  final VoidCallback onBlur;
  final ValueChanged<String> onSubmitted;

  @override
  State<_UrlField> createState() => _UrlFieldState();
}

class _UrlFieldState extends State<_UrlField> {
  bool _focused = true;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final ring = widget.hasError
        ? p.danger
        : _focused
        ? p.accent
        : Colors.transparent;

    return Focus(
      onFocusChange: (hasFocus) {
        setState(() => _focused = hasFocus);
        if (!hasFocus) widget.onBlur();
      },
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.group),
        decoration: BoxDecoration(
          color: p.raised,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: ring, width: 2),
        ),
        child: Row(
          children: [
            AppIcon(
              HawkIcons.link,
              size: 17,
              color: p.textMuted,
              strokeWidth: 2,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: widget.controller,
                focusNode: widget.focus,
                autofocus: true,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.done,
                textCapitalization: TextCapitalization.none,
                autocorrect: false,
                // A url typed into a phone keyboard is the single most
                // autocorrect-damaged string in the product.
                inputFormatters: [
                  FilteringTextInputFormatter.deny(RegExp(r'\s')),
                ],
                onChanged: widget.onChanged,
                onSubmitted: widget.onSubmitted,
                cursorColor: p.accent,
                cursorWidth: 2,
                style: AppTypography.bodyMedium.copyWith(
                  height: 1.2,
                  fontWeight: FontWeight.w500,
                  fontVariations: const [FontVariation('wght', 500)],
                  color: p.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: 'https://…',
                  hintStyle: AppTypography.bodyMedium.copyWith(
                    height: 1.2,
                    color: p.textFaint,
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
