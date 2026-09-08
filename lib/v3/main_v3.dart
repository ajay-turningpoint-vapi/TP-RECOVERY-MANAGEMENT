import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';
import 'package:salesman_mobile/v2/screens/main_scaffold.dart';
import 'package:salesman_mobile/v2/screens/login_screen.dart';
import 'package:salesman_mobile/v2/theme/app_theme.dart';
import 'package:salesman_mobile/v3/screens/re_scaffold_v3.dart';
import 'package:salesman_mobile/v3/screens/manager_scaffold_v3.dart';
import 'package:salesman_mobile/v2/screens/mobile_frame.dart';
import 'package:salesman_mobile/v2/screens/sync_freeze_overlay.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppStore()..restoreSession()),
      ],
      child: const TPRMSV3App(),
    ),
  );
}

class TPRMSV3App extends StatelessWidget {
  const TPRMSV3App({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();

    Widget getHomeScreen() {
      // Checking for a persisted (refresh-token-backed) session — see
      // AppStore.restoreSession. Brief on a warm process, but real on a
      // genuine cold start, so it needs an actual screen rather than a
      // blank frame.
      if (store.sessionLoading) {
        return const _SessionRestoringScreen();
      }
      if (!store.isLoggedIn) {
        return const LoginScreen();
      }
      if (store.userRole == 'RECOVERY_EXECUTIVE') return const ReScaffoldV3();
      if (store.userRole == 'MANAGEMENT') return const ManagerScaffoldV3();
      return const MainScaffold();
    }

    return MaterialApp(
      title: 'TP-RMS V3',
      theme: AppTheme.lightTheme,
      home: getHomeScreen(),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
          child: SyncFreezeOverlay(child: MobileFrame(child: child!)),
        );
      },
    );
  }
}

/// Shown for the brief window while [AppStore.restoreSession] checks a
/// persisted session against the server (or silently refreshes it) — see
/// main(). Deliberately branded rather than a bare spinner, since a
/// genuinely still-logged-in user sees this on every cold start.
class _SessionRestoringScreen extends StatelessWidget {
  const _SessionRestoringScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.primaryBlue,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: 56),
            const SizedBox(height: 20),
            const Text(
              'TP-RMS',
              style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 1.2),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5, valueColor: AlwaysStoppedAnimation(Colors.white.withOpacity(0.85))),
            ),
          ],
        ),
      ),
    );
  }
}
