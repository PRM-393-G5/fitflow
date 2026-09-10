import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

/// Schedules weekly repeating workout reminders as local notifications.
class ReminderService {
  final _plugin = FlutterLocalNotificationsPlugin();

  static const _channel = NotificationDetails(
    android: AndroidNotificationDetails(
      'workout_reminders',
      'Workout reminders',
      channelDescription: 'Weekly reminders on your training days',
      importance: Importance.high,
    ),
    iOS: DarwinNotificationDetails(),
  );

  Future<void> init() async {
    tz.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (e) {
      debugPrint('Could not resolve local timezone, using UTC: $e');
      tz.setLocalLocation(tz.UTC);
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
    );
  }

  Future<bool> requestPermission() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await android?.requestNotificationsPermission() ?? true;
  }

  /// Replaces all scheduled reminders. [days] uses weekday numbering
  /// (1 = Monday … 7 = Sunday), [minutes] is minutes since midnight.
  // ponytail: inexact scheduling avoids the USE_EXACT_ALARM permission review;
  // alarms may fire a few minutes late and do not survive a device reboot.
  Future<void> reschedule({
    required bool enabled,
    required int minutes,
    required Set<int> days,
  }) async {
    await _plugin.cancelAll();
    if (!enabled) return;
    final hour = minutes ~/ 60;
    final minute = minutes % 60;
    var id = 0;
    for (final day in days) {
      await _plugin.zonedSchedule(
        id: id++,
        title: 'Time to train',
        body: 'Your workout is waiting for you.',
        scheduledDate: _nextInstance(day, hour, minute),
        notificationDetails: _channel,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
    }
  }

  tz.TZDateTime _nextInstance(int weekday, int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    while (scheduled.weekday != weekday || !scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }
}
