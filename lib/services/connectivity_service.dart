import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// App-wide online/offline state.
///
/// Exposes a [ValueNotifier] that the global connectivity banner listens to,
/// and fires [onReconnected] callbacks so the app can flush pending work
/// (e.g. re-send chat messages that failed while offline).
class ConnectivityService {
  ConnectivityService._internal();
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;

  final Connectivity _connectivity = Connectivity();

  /// `true` when the device has any network connection.
  final ValueNotifier<bool> isOnline = ValueNotifier<bool>(true);

  StreamSubscription<ConnectivityResult>? _sub;
  final List<VoidCallback> _reconnectListeners = [];

  Future<void> init() async {
    try {
      final result = await _connectivity.checkConnectivity();
      isOnline.value = result != ConnectivityResult.none;
    } catch (_) {
      // Assume online on failure so we never block the user.
      isOnline.value = true;
    }

    _sub = _connectivity.onConnectivityChanged.listen((result) {
      final online = result != ConnectivityResult.none;
      final wasOffline = !isOnline.value;
      isOnline.value = online;

      if (online && wasOffline) {
        for (final cb in List<VoidCallback>.from(_reconnectListeners)) {
          try {
            cb();
          } catch (e) {
            debugPrint('⚠️ onReconnected callback failed: $e');
          }
        }
      }
    });
  }

  /// Registers a callback fired every time the device transitions
  /// offline → online.
  void onReconnected(VoidCallback callback) {
    _reconnectListeners.add(callback);
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
    _reconnectListeners.clear();
  }
}
