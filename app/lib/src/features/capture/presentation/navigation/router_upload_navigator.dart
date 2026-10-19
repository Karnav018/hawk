import 'package:injectable/injectable.dart';

import '../../../../app/router/app_router.dart';
import '../../../voice/presentation/pages/home_page.dart';
import '../bloc/upload_center.dart';
import '../pages/indexing_page.dart';

/// The island's actions, through the app's one router.
///
/// The island lives above every route, so it has no `BuildContext` of its
/// own to navigate with; the router is the thing that is always there.
@LazySingleton(as: UploadNavigator)
class RouterUploadNavigator implements UploadNavigator {
  RouterUploadNavigator(this._router);

  final AppRouter _router;

  @override
  void openBatch(String batchId) => _router.config.pushNamed(
    IndexingPage.routeName,
    pathParameters: {'batchId': batchId},
  );

  /// Asking *is* the search in this product, and it lives on Home. There is
  /// no "ask about this one file" mode to open yet, so Ask goes to the
  /// question field; the file is freshly indexed and the first to be found.
  @override
  void ask() => _router.config.go(HomePage.routePath);
}
