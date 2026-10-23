import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

/// Schedules weekly repeating workout reminders as local notifications,
/// and the one-off alert when a rest or timed set ends in the background.
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

  /// Weekly reminders use ids 1–7 (weekday); the timer alert sits apart.
  static const _timerId = 100;

  static const _timerChannel = NotificationDetails(
    android: AndroidNotificationDetails(
      'workout_timer',
      'Workout timer',
      channelDescription:
          'When a rest or timed set ends while FitFlow is in the background',
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.alarm,
    ),
    iOS: DarwinNotificationDetails(
      interruptionLevel: InterruptionLevel.timeSensitive,
    ),
  );

  Future<void> init() async {
    tz.initializeTimeZones();
    tz.setLocalLocation(await _resolveLocation());
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        // Ask on iOS only when the user turns reminders on, not at launch.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
  }

  /// The device timezone; when it can't be resolved, a fixed-offset zone
  /// matching the current UTC offset so reminders still fire at local time.
  Future<tz.Location> _resolveLocation() async {
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      return tz.getLocation(info.identifier);
    } catch (e) {
      final offset = DateTime.now().timeZoneOffset;
      debugPrint('Could not resolve local timezone ($e), offset $offset');
      if (offset.inMinutes % 60 == 0) {
        // Etc/GMT names invert the sign: UTC+7 is "Etc/GMT-7".
        final hours = -offset.inHours;
        final name = hours == 0
            ? 'Etc/UTC'
            : 'Etc/GMT${hours > 0 ? '+' : ''}$hours';
        try {
          return tz.getLocation(name);
        } catch (_) {}
      }
      return tz.UTC;
    }
  }

  Future<bool> requestPermission() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      return await ios.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }
    return true;
  }

  /// Replaces all scheduled reminders. [days] uses weekday numbering
  /// (1 = Monday … 7 = Sunday), [minutes] is minutes since midnight.
  // ponytail: inexact scheduling avoids the USE_EXACT_ALARM permission review;
  // alarms may fire a few minutes late. Reboots are covered by the plugin's
  // boot receiver (AndroidManifest) plus a reschedule on every app start.
  Future<void> reschedule({
    required bool enabled,
    required int minutes,
    required Set<int> days,
  }) async {
    // Only the weekly ids: a rest alert pending right now must survive.
    for (var day = 1; day <= 7; day++) {
      await _plugin.cancel(id: day);
    }
    if (!enabled) return;
    final hour = minutes ~/ 60;
    final minute = minutes % 60;
    for (final day in days) {
      await _plugin.zonedSchedule(
        // Stable per-weekday ids, so overlapping reschedules overwrite
        // rather than duplicate.
        id: day,
        title: 'Time to train',
        body: 'Your workout is waiting for you.',
        scheduledDate: nextInstance(
          tz.TZDateTime.now(tz.local),
          day,
          hour,
          minute,
        ),
        notificationDetails: _channel,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
    }
  }

  /// Alerts at [at] that a rest or timed set is over. Replaces any earlier
  /// one. Exact when Android allows it ("Alarms & reminders"); otherwise
  /// inexact, which may come late but still comes.
  Future<void> scheduleTimerAlert(
    DateTime at, {
    required String title,
    required String body,
  }) async {
    await cancelTimerAlert();
    if (!at.isAfter(DateTime.now())) return;
    // A missing alert must never break the workout it belongs to.
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final exact = await android?.canScheduleExactNotifications() ?? true;
      await _plugin.zonedSchedule(
        id: _timerId,
        title: title,
        body: body,
        scheduledDate: tz.TZDateTime.from(at, tz.local),
        notificationDetails: _timerChannel,
        androidScheduleMode: exact
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (e) {
      debugPrint('Could not schedule the timer alert: $e');
    }
  }

  Future<void> cancelTimerAlert() async {
    try {
      await _plugin.cancel(id: _timerId);
    } catch (e) {
      debugPrint('Could not cancel the timer alert: $e');
    }
  }

  /// Next [weekday] at [hour]:[minute] wall-clock time after [now]. Built
  /// from calendar fields, not by adding 24h steps, so a DST change in
  /// between cannot shift the hour.
  @visibleForTesting
  static tz.TZDateTime nextInstance(
    tz.TZDateTime now,
    int weekday,
    int hour,
    int minute,
  ) {
    for (var offset = 0; offset <= 7; offset++) {
      final candidate = tz.TZDateTime(
        now.location,
        now.year,
        now.month,
        now.day + offset,
        hour,
        minute,
      );
      if (candidate.weekday == weekday && candidate.isAfter(now)) {
        return candidate;
      }
    }
    throw StateError('unreachable: a weekday recurs within 8 days');
  }
}
