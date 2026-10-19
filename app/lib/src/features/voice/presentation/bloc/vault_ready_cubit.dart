import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/bloc/safe_emit.dart';
import '../../../account/domain/repositories/account_repository.dart';

/// How many memories are searchable right now — the home screen's one number.
///
/// The design puts `1,516 MEMORIES READY` under the greeting, and it is doing
/// real work there: it is the only evidence on the home screen that the vault
/// is not empty, which is the question somebody silently asks before they
/// bother holding the orb.
///
/// **Nothing in the app already knew this number.** `Subscription` carries
/// `memoriesDormant` (for the paywall) but not the live total, and the
/// library's list bloc holds a page rather than a count. The one place the
/// server answers it is `AccountOverview`, which the profile screen fetches —
/// so this borrows that call rather than adding an endpoint. One read when
/// home mounts, no subscription, no polling.
///
/// Not `@injectable` on purpose: registering it would mean regenerating
/// `injector.config.dart`, and this cubit has exactly one call site. It takes
/// its repository from `getIt` at that call site instead.
///
/// The state is `int?` because "we have not asked yet" and "none" are
/// different facts, and only one of them should render as an empty vault. A
/// failed call stays null — the greeting then shows an em dash, which is what
/// [AccountOverview.count] already does everywhere else a count is unknown.
class VaultReadyCubit extends Cubit<int?> with SafeEmit<int?> {
  VaultReadyCubit(this._accounts) : super(null) {
    load();
  }

  final AccountRepository _accounts;

  Future<void> load() async {
    // Yesterday's count first, so the greeting has a number the moment home
    // opens instead of an em dash for the length of a Cloud Function call.
    // The fresh count replaces it a beat later.
    try {
      final cached = await _accounts.cachedOverview();
      if (cached != null && cached.indexed >= 0) emit(cached.indexed);
    } on Object {
      // A cache miss or a broken entry is simply no head start.
    }
    try {
      final overview = await _accounts.overview();
      // Indexed, not total. "Ready" is a promise about what an answer can be
      // drawn from, and a file that is still being read cannot be asked
      // about yet — counting it would make the first question look broken.
      final ready = overview.indexed;
      emit(ready < 0 ? null : ready);
    } catch (_) {
      // Swallowed. A greeting is not the place to report that a count call
      // failed: the orb still works, every other screen still works, and the
      // honest rendering of "we could not count" is the em dash the null
      // already produces — unless a cached count is already showing, which
      // is a better answer than a dash.
      if (state == null) emit(null);
    }
  }
}
