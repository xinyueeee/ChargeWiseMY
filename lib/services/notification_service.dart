import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmanager/workmanager.dart';

const _remindersChannelId = 'charging_reminders_v2';
const _remindersChannelName = 'Charging Reminders';
const _remindersChannelDescription = 'Reminders to charge your EV';
const _reminderTaskName = 'chargingReminderTask';

const _supabaseUrl = 'https://ffqtkpoeuqjuihqdzmsc.supabase.co';
const _supabasePublishableKey =
    'sb_publishable_RZVErCEwcPADZuWBWqGtKg_BxkWHRj1';

/// The next time this reminder should fire, strictly after [anchor].
/// [repeatDays] holds `DateTime.weekday` values (1=Monday..7=Sunday) and only
/// applies to 'weekly' - when empty, weekly falls back to a flat 7-day step.
DateTime nextReminderOccurrence(
  DateTime anchor,
  String repeatFrequency, {
  List<int> repeatDays = const [],
}) {
  switch (repeatFrequency) {
    case 'daily':
      return anchor.add(const Duration(days: 1));
    case 'weekly':
      if (repeatDays.isEmpty) return anchor.add(const Duration(days: 7));
      for (var i = 1; i <= 7; i++) {
        final candidate = anchor.add(Duration(days: i));
        if (repeatDays.contains(candidate.weekday)) return candidate;
      }
      return anchor.add(const Duration(days: 7));
    default:
      return anchor;
  }
}

/// Rolls a possibly-past anchor forward to the next occurrence that is still
/// in the future, so a recurring reminder anchored at a time earlier today
/// still schedules correctly instead of firing almost immediately.
///
/// For 'weekly', the search always starts from today (not from whatever
/// date [anchor] happens to carry, which the UI hides once weekly is
/// picked), at [anchor]'s time-of-day, and only accepts a day that is both
/// one of [repeatDays] and still in the future - so it can never return a
/// day that wasn't actually selected just because that moment happens to be
/// in the future.
DateTime rollReminderToFuture(
  DateTime anchor,
  String repeatFrequency, {
  List<int> repeatDays = const [],
}) {
  if (repeatFrequency == 'once') return anchor;
  final now = DateTime.now();
  if (repeatFrequency == 'weekly') {
    if (repeatDays.isEmpty) {
      return anchor.isAfter(now) ? anchor : anchor.add(const Duration(days: 7));
    }
    for (var i = 0; i <= 7; i++) {
      final candidate = DateTime(
        now.year,
        now.month,
        now.day,
        anchor.hour,
        anchor.minute,
      ).add(Duration(days: i));
      if (repeatDays.contains(candidate.weekday) && candidate.isAfter(now)) {
        return candidate;
      }
    }
    return anchor;
  }
  var next = anchor;
  while (!next.isAfter(now)) {
    next = nextReminderOccurrence(
      next,
      repeatFrequency,
      repeatDays: repeatDays,
    );
  }
  return next;
}

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

      final repeatFrequency = inputData['repeatFrequency'] as String? ?? 'once';
      final reminderId = inputData['reminderId'] as String?;
      final scheduledAtRaw = inputData['scheduledAt'] as String?;
      final repeatDays = (inputData['repeatDays'] as List<Object?>?)
              ?.map((e) => e as int)
              .toList() ??
          const <int>[];

      if (repeatFrequency == 'once' && reminderId != null) {
        // A one-time reminder has nothing left to reschedule; turn its
        // toggle off so it doesn't sit there looking "on" after it already
        // fired.
        try {
          await Supabase.initialize(
            url: _supabaseUrl,
            publishableKey: _supabasePublishableKey,
          );
          await Supabase.instance.client
              .from('charging_reminders')
              .update({'enabled': false}).eq('id', reminderId);
        } catch (error) {
          debugPrint(
            'callbackDispatcher: could not disable fired reminder '
            '$reminderId: $error',
          );
        }
      }

      if (repeatFrequency != 'once' &&
          reminderId != null &&
          scheduledAtRaw != null) {
        final scheduledAt = DateTime.parse(scheduledAtRaw);
        final next = nextReminderOccurrence(
          scheduledAt,
          repeatFrequency,
          repeatDays: repeatDays,
        );
        var delay = next.difference(DateTime.now());
        if (delay.isNegative) delay = const Duration(seconds: 5);

        await Workmanager().registerOneOffTask(
          reminderId,
          _reminderTaskName,
          initialDelay: delay,
          existingWorkPolicy: ExistingWorkPolicy.replace,
          inputData: {
            'notificationId': notificationId,
            'title': title,
            'body': body,
            'reminderId': reminderId,
            'repeatFrequency': repeatFrequency,
            'repeatDays': repeatDays,
            'scheduledAt': next.toIso8601String(),
          },
        );

        try {
          await Supabase.initialize(
            url: _supabaseUrl,
            publishableKey: _supabasePublishableKey,
          );
          await Supabase.instance.client.from('charging_reminders').update({
            'reminder_date': '${next.year.toString().padLeft(4, '0')}-'
                '${next.month.toString().padLeft(2, '0')}-'
                '${next.day.toString().padLeft(2, '0')}',
            'reminder_time': '${next.hour.toString().padLeft(2, '0')}:'
                '${next.minute.toString().padLeft(2, '0')}:00',
          }).eq('id', reminderId);
        } catch (error) {
          debugPrint(
            'callbackDispatcher: could not sync next occurrence for '
            '$reminderId: $error',
          );
        }
      }
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

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidSettings);
    await _plugin.initialize(settings);
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final notificationsGranted =
        await android?.requestNotificationsPermission();
    debugPrint(
      'NotificationService.init: notificationsPermissionGranted=$notificationsGranted',
    );

    await Workmanager().initialize(callbackDispatcher);
    _initialized = true;
  }

  int notificationIdFor(String reminderId) => reminderId.hashCode & 0x7FFFFFFF;

  /// Schedules a reminder notification for [dateTime]. When
  /// [repeatFrequency] isn't 'once', the reminder reschedules itself for the
  /// next occurrence (daily/weekly on [repeatDays]/monthly) each time it
  /// fires, and keeps the reminder's stored date/time in sync with that next
  /// occurrence.
  Future<void> scheduleReminder({
    required String reminderId,
    required String title,
    required String body,
    required DateTime dateTime,
    String repeatFrequency = 'once',
    List<int> repeatDays = const [],
  }) async {
    await init();
    final now = DateTime.now();
    var delay = dateTime.difference(now);
    if (delay.isNegative) {
      delay = const Duration(seconds: 5);
    }

    debugPrint(
      'NotificationService.scheduleReminder: id=$reminderId, fireIn=$delay, '
      'repeat=$repeatFrequency, days=$repeatDays',
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
        'reminderId': reminderId,
        'repeatFrequency': repeatFrequency,
        'repeatDays': repeatDays,
        'scheduledAt': dateTime.toIso8601String(),
      },
    );
  }

  Future<void> cancel(String reminderId) async {
    // init() is idempotent and now started in the background from main(),
    // not awaited before the first frame; every public method here must
    // still guarantee it has completed before touching the plugin, exactly
    // as scheduleReminder() already does.
    await init();
    await Workmanager().cancelByUniqueName(reminderId);
    await _plugin.cancel(notificationIdFor(reminderId));
  }
}
