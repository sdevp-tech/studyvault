import 'package:flutter/material.dart';
import '../../services/connectivity_service.dart';

/// A thin, app-wide banner that appears at the top of the screen whenever the
/// device loses network connectivity. Wired in via [MaterialApp.builder] so it
/// overlays every screen without any per-screen code.
class ConnectivityBanner extends StatelessWidget {
  final Widget child;
  const ConnectivityBanner({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ConnectivityService().isOnline,
      builder: (context, online, _) {
        return Directionality(
          textDirection: Directionality.maybeOf(context) ?? TextDirection.rtl,
          child: Stack(
            children: [
              Positioned.fill(child: child),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                top: online ? -60 : 0,
                left: 0,
                right: 0,
                child: _OfflineBar(),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _OfflineBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: SafeArea(
        bottom: false,
        child: Container(
          width: double.infinity,
          color: const Color(0xFFB00020),
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.wifi_off, color: Colors.white, size: 16),
              SizedBox(width: 8),
              Flexible(
                child: Text(
                  'لا يوجد اتصال بالإنترنت — سيتم حفظ تغييراتك ومزامنتها لاحقاً',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
