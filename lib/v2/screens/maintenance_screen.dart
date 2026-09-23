import 'package:flutter/material.dart';

const _kAmber = Color(0xFFF59E0B);

/// The one and only "server under maintenance" UI in the app — a genuine
/// full screen, never a popup/curtain floating over other content. Used
/// both pre-login (LoginScreen, for everyone while [AppStore.maintenanceMode]
/// is on) and post-login (SyncFreezeOverlay, for an already-signed-in
/// non-Admin whose session gets blocked the instant Admin flips the switch
/// on — see server's maintenanceService.js). No live elapsed counter — just
/// a fixed, conservative "back by" time so this never depends on
/// [AppStore.maintenanceSince] to render correctly.
class MaintenanceScreen extends StatelessWidget {
  const MaintenanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1220),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Spacer(flex: 3),
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(color: _kAmber.withValues(alpha: 0.14), shape: BoxShape.circle),
                child: const Icon(Icons.construction_rounded, color: _kAmber, size: 48),
              ),
              const SizedBox(height: 28),
              const Text(
                'Server Under Maintenance',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.3),
              ),
              const SizedBox(height: 14),
              const Text(
                "We're performing scheduled maintenance on Clock.\n"
                'This page will refresh automatically once access is restored.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14.5, height: 1.6, color: Color(0xFFA9B4C8)),
              ),
              const SizedBox(height: 22),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(20)),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.schedule_rounded, size: 14, color: Color(0xFFA9B4C8)),
                    SizedBox(width: 6),
                    Text('Expected back online by 12:00 AM tomorrow', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFFA9B4C8))),
                  ],
                ),
              ),
              const Spacer(flex: 4),
              const Text('Clock', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF4B5A75), letterSpacing: 1.5)),
              const SizedBox(height: 18),
            ],
          ),
        ),
      ),
    );
  }
}
