import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

/// Thin wrapper around local (on-device) notification display and the
/// Android 13+ POST_NOTIFICATIONS runtime permission it requires. There is
/// no push (FCM) backend in this app — notifications are raised locally,
/// client-side, when [AppStore]'s foreground polling (see
/// `_pollForNewNotifications` in app_store.dart) notices new unread items
/// from `/api/notifications`, so a salesperson sees an OS-level alert
/// (banner/sound) rather than only the in-app bell badge.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const _channel = AndroidNotificationChannel(
    'tp_rms_alerts',
    'TP-RMS Alerts',
    description: 'Task, PTP, and account alerts from TP-RMS',
    importance: Importance.high,
  );

  Future<void> init() async {
    if (_initialized) return;
    // A dedicated small monochrome (white-on-transparent) icon, not the
    // full-color launcher icon — Android can't render a full-color image
    // properly in the status bar/tray and silently falls back to a
    // generic icon, which is what showed up here before this existed.
    const androidSettings = AndroidInitializationSettings('@drawable/ic_notif_alert');
    const iosSettings = DarwinInitializationSettings(requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false);
    await _plugin.initialize(const InitializationSettings(android: androidSettings, iOS: iosSettings));
    await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(_channel);
    _initialized = true;
  }

  /// Requests notification permission — Android 13+'s POST_NOTIFICATIONS
  /// (a no-op resolving to already-granted on older Android) and iOS's
  /// alert/badge/sound authorization (via permission_handler, enabled by
  /// the `PERMISSION_NOTIFICATIONS` macro in ios/Podfile's post_install).
  /// Safe to call repeatedly — the system only ever prompts the user once
  /// per install/App Store update; later calls just return the existing
  /// (or denied) status without re-prompting.
  Future<bool> requestPermission() async {
    final status = await Permission.notification.request();
    return status.isGranted;
  }

  /// [icon] is a `@drawable/ic_notif_*` resource name (see [iconFor]) —
  /// defaults to the generic alert bell when the caller doesn't know/care
  /// which category this notification belongs to.
  Future<void> show({required int id, required String title, required String body, String icon = 'ic_notif_alert'}) async {
    if (!_initialized) await init();
    await _plugin.show(
      id,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'TP-RMS Alerts',
          channelDescription: 'Task, PTP, and account alerts from TP-RMS',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@drawable/$icon',
        ),
      ),
    );
  }

  /// Picks a notification-tray icon from the alert's own text — mirrors
  /// the same keyword-categorization pattern customer_360_screen.dart's
  /// `_auditVisuals` already uses for the in-app history timeline, just
  /// applied to a notification's title/body since NotificationItem carries
  /// no explicit category of its own. First match wins.
  static String iconFor(String title, String body) {
    final t = '$title $body'.toLowerCase();
    if (t.contains('dispute')) return 'ic_notif_dispute';
    if (t.contains('escalat')) return 'ic_notif_alert';
    if (t.contains('sla') || t.contains('past its') || t.contains('deadline') || t.contains('background job')) {
      return 'ic_notif_clock';
    }
    if (t.contains('verif') || t.contains('pending') || t.contains('awaiting')) return 'ic_notif_waiting';
    if (t.contains('ptp') || t.contains('payment') || t.contains('outcome') || t.contains('correction')) {
      return 'ic_notif_ptp';
    }
    if (t.contains('task') || t.contains('visit') || t.contains('assign') || t.contains('reschedul')) {
      return 'ic_notif_call';
    }
    return 'ic_notif_alert';
  }

  static const _channelId = 'tp_rms_alerts';
}
