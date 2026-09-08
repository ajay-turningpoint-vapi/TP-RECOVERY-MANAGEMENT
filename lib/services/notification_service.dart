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
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false);
    await _plugin.initialize(const InitializationSettings(android: androidSettings, iOS: iosSettings));
    await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(_channel);
    _initialized = true;
  }

  /// Requests the Android 13+ POST_NOTIFICATIONS permission (a no-op that
  /// resolves to already-granted on older Android and on iOS's separate
  /// alert-permission model, which this app doesn't request since it has
  /// no iOS notification content today). Safe to call repeatedly — the
  /// system only ever prompts the user once per install.
  Future<bool> requestPermission() async {
    final status = await Permission.notification.request();
    return status.isGranted;
  }

  Future<void> show({required int id, required String title, required String body}) async {
    if (!_initialized) await init();
    await _plugin.show(
      id,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'TP-RMS Alerts',
          channelDescription: 'Task, PTP, and account alerts from TP-RMS',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }

  static const _channelId = 'tp_rms_alerts';
}
