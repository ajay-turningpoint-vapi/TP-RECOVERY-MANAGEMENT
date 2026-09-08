import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';

/// Wraps the whole app (see v3/main_v3.dart's MaterialApp.builder) and, for
/// as long as AppStore.isSyncing is true, blocks every screen behind a
/// full-screen scrim with a real explanation — the daily BUSY sync is
/// rewriting customer/PTP/task data server-side, so any read or write
/// during that window could see (or silently lose) a half-synced state.
/// AbsorbPointer, not just a visual overlay, so no tap/scroll underneath
/// can reach the frozen screen while this is up.
class SyncFreezeOverlay extends StatelessWidget {
  final Widget child;
  const SyncFreezeOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    return Stack(
      children: [
        child,
        if (store.isSyncing)
          Positioned.fill(
            child: AbsorbPointer(
              absorbing: true,
              child: Container(
                color: Colors.black.withOpacity(0.55),
                alignment: Alignment.center,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 36),
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 30),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 24, offset: const Offset(0, 8))],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 40,
                        height: 40,
                        child: CircularProgressIndicator(strokeWidth: 3.5, color: Color(0xFF0052CC)),
                      ),
                      const SizedBox(height: 20),
                      const Text('Syncing with BUSY',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1B2B48))),
                      const SizedBox(height: 8),
                      const Text(
                        'Customer balances, PTPs, and tasks are being updated from BUSY right now. The app is frozen until this finishes — please wait, this only takes a few minutes.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12.5, color: Color(0xFF5A6B87), height: 1.4),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
