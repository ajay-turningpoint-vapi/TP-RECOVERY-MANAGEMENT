import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:salesman_mobile/widgets/app_message.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';
import 'package:salesman_mobile/v2/theme/app_theme.dart';
import 'package:salesman_mobile/v2/screens/mobile_frame.dart';
import 'package:salesman_mobile/v3/screens/admin_scaffold_v3.dart';
import 'package:salesman_mobile/v3/screens/admin_login_screen.dart';

/// Separate entry point, separate installable app (see
/// android/app/build.gradle's `admin` flavor — distinct applicationId, own
/// icon on the home screen). Only ever shows the admin sign-in and
/// AdminScaffoldV3 — no RE/Manager/Salesperson code, and critically no
/// maintenance-mode blocking screen, since this app is how an admin turns
/// maintenance back off. Build with:
///   flutter build apk --release --flavor admin -t lib/main_admin.dart
void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

    final priorOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      priorOnError?.call(details);
      FlutterError.presentError(details);
      if (!_isNoisyFrameworkError(details)) {
        showGlobalError('Something went wrong. Please try again.');
      }
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      debugPrint('Uncaught error: $error\n$stack');
      showGlobalError('Something went wrong. Please try again.');
      return true;
    };

    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AppStore()..restoreSession()),
        ],
        child: const TPRMSAdminApp(),
      ),
    );
  }, (error, stack) {
    debugPrint('Uncaught zone error: $error\n$stack');
    showGlobalError('Something went wrong. Please try again.');
  });
}

/// Framework-level noise that's a real bug to fix but never something the
/// user can act on — mirrors main_v3.dart's filter of the same name.
bool _isNoisyFrameworkError(FlutterErrorDetails details) {
  final text = details.exception.toString();
  return text.contains('overflowed by') ||
      text.contains('RenderFlex') ||
      text.contains('Incorrect use of ParentDataWidget') ||
      text.contains('ParentDataWidget') ||
      // Purely cosmetic — a ListTile without a Material ancestor still
      // renders and responds to taps, it just may not show its background
      // color / ink splash. Fix these at the source when found, but never
      // block the user on it.
      text.contains('background color or ink splashes may be invisible') ||
      details.library == 'image resource service';
}

class TPRMSAdminApp extends StatelessWidget {
  const TPRMSAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();

    Widget getHomeScreen() {
      if (store.sessionLoading) return const _SessionRestoringScreen();
      if (!store.isLoggedIn) return const AdminLoginScreen();
      if (store.userRole == 'ADMIN') return const AdminScaffoldV3();
      // A non-admin account somehow ended up logged in here (e.g. a
      // leftover session) — this app has no screen for any other role.
      return const AdminLoginScreen();
    }

    return MaterialApp(
      title: 'TP-RMS Admin',
      debugShowCheckedModeBanner: false,
      navigatorKey: appNavigatorKey,
      theme: AppTheme.lightTheme,
      home: getHomeScreen(),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
          child: MobileFrame(child: child!),
        );
      },
    );
  }
}

class _SessionRestoringScreen extends StatelessWidget {
  const _SessionRestoringScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0052CC),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.admin_panel_settings_rounded, color: Colors.white, size: 56),
            const SizedBox(height: 20),
            const Text(
              'TP-RMS ADMIN',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 1.2),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5, valueColor: AlwaysStoppedAnimation(Colors.white.withValues(alpha: 0.85))),
            ),
          ],
        ),
      ),
    );
  }
}
