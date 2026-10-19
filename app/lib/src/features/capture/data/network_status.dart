import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:injectable/injectable.dart';

/// Whether the phone has a network at all — for E5, "queued, uploads when
/// back".
///
/// **A radio, not a reachability check.** connectivity_plus reports whether
/// Wi-Fi or cellular is up, not whether Firebase answers. That is the right
/// question here: the upload already retries through a flaky connection on
/// its own, and what it cannot do is make progress with no radio, which is
/// exactly the case worth telling somebody about. A captive portal reads as
/// online; the upload then stalls and, eventually, stops (E6) — which is
/// what it is.
abstract interface class NetworkStatus {
  Future<bool> isOnline();

  /// Distinct values only.
  Stream<bool> get changes;
}

@LazySingleton(as: NetworkStatus)
class DeviceNetworkStatus implements NetworkStatus {
  final _connectivity = Connectivity();

  static bool _online(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);

  @override
  Future<bool> isOnline() async =>
      _online(await _connectivity.checkConnectivity());

  @override
  Stream<bool> get changes =>
      _connectivity.onConnectivityChanged.map(_online).distinct();
}
