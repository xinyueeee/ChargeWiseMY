import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';

const _remindersChannelId = 'charging_reminders_v2';
const _remindersChannelName = 'Charging Reminders';
const _remindersChannelDescription = 'Reminders to charge your EV';
const _reminderTaskName = 'chargingReminderTask';

/// Runs in a background isolate whenever a WorkManager task fires (app
/// foreground, background, or fully killed). Must stay a top-level function.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == _reminderTaskName && inputData != null) {
      final plugin = FlutterLocalNotificationsPlugin();
      const androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      await plugin.initialize(
        const InitializationSettings(android: androidSettings),
      );
      final notificationId = inputData['notificationId'] as int? ?? 0;
      final title = inputData['title'] as String? ?? 'Charging Reminder';
      final body = inputData['body'] as String? ?? 'Time to charge your EV.';
      await plugin.show(
        notificationId,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _remindersChannelId,
            _remindersChannelName,
            channelDescription: _remindersChannelDescription,
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );
    }
    return true;
  });
}

class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidSettings);
    await _plugin.initialize(settings);
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final notificationsGranted = await android?.requestNotificationsPermission();
    debugPrint(
      'NotificationService.init: notificationsPermissionGranted=$notificationsGranted',
    );

    await Workmanager().initialize(callbackDispatcher);
    _initialized = true;
  }

  int notificationIdFor(String reminderId) => reminderId.hashCode & 0x7FFFFFFF;

  /// Schedules a one-time reminder notification for [dateTime].
  ///
  /// Delivery goes through WorkManager (JobScheduler) rather than a raw
  /// AlarmManager broadcast + BroadcastReceiver. On some Samsung devices the
  /// OS accepts an AlarmManager broadcast and logs it as delivered but never
  /// actually dispatches it to the receiver (confirmed via `dumpsys activity
  /// broadcasts`: dispatchClockTime never advances past epoch), so the
  /// notification silently never fires. JobScheduler-backed work is honored
  /// reliably on the same device. The tradeoff is that delivery is
  /// best-effort/approximate rather than exact-to-the-second.
  Future<void> scheduleReminder({
    required String reminderId,
    required String title,
    required String body,
    required DateTime dateTime,
  }) async {
    await init();
    final now = DateTime.now();
    var delay = dateTime.difference(now);
    if (delay.isNegative) {
      delay = const Duration(seconds: 5);
    }

    debugPrint(
      'NotificationService.scheduleReminder: id=$reminderId, fireIn=$delay',
    );
    await Workmanager().registerOneOffTask(
      reminderId,
      _reminderTaskName,
      initialDelay: delay,
      existingWorkPolicy: ExistingWorkPolicy.replace,
      inputData: {
        'notificationId': notificationIdFor(reminderId),
        'title': title,
        'body': body,
      },
    );
  }

  Future<void> cancel(String reminderId) async {
    await Workmanager().cancelByUniqueName(reminderId);
    await _plugin.cancel(notificationIdFor(reminderId));
  }
}
