import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:salesman_mobile/services/api_client.dart';
import 'package:salesman_mobile/widgets/app_message.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';
import 'package:salesman_mobile/v2/screens/main_scaffold.dart';
import 'package:salesman_mobile/v2/screens/login_screen.dart';
import 'package:salesman_mobile/v2/theme/app_theme.dart';
import 'package:salesman_mobile/v3/screens/re_scaffold_v3.dart';
import 'package:salesman_mobile/v3/screens/manager_scaffold_v3.dart';
import 'package:salesman_mobile/v3/screens/admin_scaffold_v3.dart';
import 'package:salesman_mobile/v2/screens/mobile_frame.dart';
import 'package:salesman_mobile/v2/screens/sync_freeze_overlay.dart';

void main() {
  // Everything runs inside one guarded zone so that *any* failure the app
  // doesn't catch itself — an uncaught async error, a framework error, a
  // bad server response nobody handled — surfaces as a proper popup dialog
  // (see showGlobalError) instead of a red error screen or silence.
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();

    // Portrait only — matches the Android manifest / iOS Info.plist
    // orientation locks (which cover the brief window before this Dart call
    // runs), so the app never rotates into landscape on any platform.
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);

    // Framework-level (build/layout/paint) errors.
    final priorOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      priorOnError?.call(details);
      FlutterError.presentError(details);
      if (!_isNoisyFrameworkError(details)) {
        showGlobalError(_friendlyMessage(details.exception));
      }
    };

    // Uncaught errors that bubble out of the platform dispatcher
    // (un-awaited futures, platform channels, gestures).
    PlatformDispatcher.instance.onError = (error, stack) {
      debugPrint('Uncaught error: $error\n$stack');
      showGlobalError(_friendlyMessage(error));
      return true;
    };

    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AppStore()..restoreSession()),
        ],
        child: const TPRMSV3App(),
      ),
    );
  }, (error, stack) {
    debugPrint('Uncaught zone error: $error\n$stack');
    showGlobalError(_friendlyMessage(error));
  });
}

/// Turns whatever was thrown into a sentence a user can read. Known
/// server/network failures already carry a friendly message; anything
/// else gets a generic line rather than a raw exception / stack trace.
String _friendlyMessage(Object error) {
  if (error is ApiException) {
    // statusCode 0 == a client-side network failure (server unreachable /
    // request timed out). Say plainly that it's a connection problem and
    // that the app recovers on its own — the data/sync layer retries every
    // reconnect, so the user doesn't need to do anything.
    if (error.statusCode == 0 || _looksLikeConnectionError(error.message)) {
      return "Can't reach the server right now — your connection may be down. "
          'The app will keep trying and refresh automatically once it’s back.';
    }
    return error.message;
  }
  if (_looksLikeConnectionError(error.toString())) {
    return "Can't reach the server right now — your connection may be down. "
        'The app will keep trying and refresh automatically once it’s back.';
  }
  return 'Something went wrong and the last action could not be completed. '
      'Please try again — the app keeps retrying in the background, so this often clears on its own.';
}

bool _looksLikeConnectionError(String text) {
  final t = text.toLowerCase();
  return t.contains('reach the server') ||
      t.contains('taking too long to respond') ||
      t.contains('socketexception') ||
      t.contains('timeoutexception') ||
      t.contains('connection') && (t.contains('closed') || t.contains('refused') || t.contains('reset') || t.contains('failed')) ||
      t.contains('network is unreachable') ||
      t.contains('failed host lookup');
}

/// Layout-overflow stripes and similar debug-only framework noise are
/// "errors" but shouldn't throw a modal in the user's face — let the
/// console keep them, skip the popup.
bool _isNoisyFrameworkError(FlutterErrorDetails details) {
  final text = details.exception.toString();
  return text.contains('overflowed by') ||
      text.contains('RenderFlex') ||
      // Dev-time widget-tree assertions — real bugs to fix, but never
      // something an end user can act on, so don't throw a modal for them.
      text.contains('Incorrect use of ParentDataWidget') ||
      text.contains('ParentDataWidget') ||
      details.library == 'image resource service';
}

class TPRMSV3App extends StatefulWidget {
  const TPRMSV3App({super.key});

  @override
  State<TPRMSV3App> createState() => _TPRMSV3AppState();
}

class _TPRMSV3AppState extends State<TPRMSV3App> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A salesperson foregrounding the app after regaining signal — don't
    // make them wait for SSE's own reconnect backoff (up to 30s) before a
    // queued offline action flushes.
    if (state == AppLifecycleState.resumed) {
      context.read<AppStore>().onAppResumed();
    }
  }

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
      if (store.userRole == 'ADMIN') return const AdminScaffoldV3();
      return const MainScaffold();
    }

    return MaterialApp(
      title: 'TP-RMS V3',
      navigatorKey: appNavigatorKey,
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
