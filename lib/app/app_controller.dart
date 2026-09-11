import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/reminder_service.dart';
import '../domain/models/body_weight_entry.dart';
import '../domain/models/workout.dart';
import '../domain/models/workout_session.dart';
import '../domain/repositories/workout_repository.dart';

class AppController extends ChangeNotifier {
  AppController(this.repository, this.preferences, {this.reminders});

  static const _themeKey = 'theme_mode';
  static const _unitKey = 'unit_system';
  static const _weightsKey = 'body_weights_v1';
  static const _reminderKey = 'reminder_v1';
  static const _profileKey = 'body_profile_v1';
  static const _scheduleKey = 'schedule_v1';
  static const _onboardingKey = 'onboarding_v1';
  static const _weeklyGoalKey = 'weekly_goal_v1';
  final WorkoutRepository repository;
  final SharedPreferences preferences;
  final ReminderService? reminders;

  List<Workout> workouts = [];
  List<WorkoutSession> sessions = [];
  List<BodyWeightEntry> weightEntries = [];
  ThemeMode themeMode = ThemeMode.system;
  bool useMetric = true;
  bool loading = true;
  String? error;

  bool reminderEnabled = false;
  int reminderMinutes = 18 * 60;
  Set<int> reminderDays = {1, 3, 5};

  double? heightCm;
  int? age;
  bool isMale = true;
  int activityLevel = 1;

  Map<int, String> schedule = {};

  bool onboardingDone = false;
  String? goal;
  String? level;

  int weeklyGoal = 3;

  Future<void> load() async {
    loading = true;
    error = null;
    try {
      workouts = await repository.getWorkouts();
      sessions = await repository.getRecentSessions();
      themeMode = ThemeMode.values.firstWhere(
        (mode) => mode.name == preferences.getString(_themeKey),
        orElse: () => ThemeMode.system,
      );
      useMetric = preferences.getBool(_unitKey) ?? true;
      weightEntries = _decodeWeights();
      _decodeReminder();
      _decodeProfile();
      _decodeSchedule();
      _decodeOnboarding();
      weeklyGoal = preferences.getInt(_weeklyGoalKey) ?? 3;
    } catch (_) {
      error = 'Could not load your local data.';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  List<BodyWeightEntry> _decodeWeights() {
    final raw = preferences.getString(_weightsKey);
    if (raw == null) return [];
    try {
      final entries = (jsonDecode(raw) as List)
          .map((item) => BodyWeightEntry.fromJson(item as Map<String, dynamic>))
          .toList();
      entries.sort((a, b) => a.date.compareTo(b.date));
      return entries;
    } on FormatException {
      return [];
    }
  }

  Future<void> addSession(WorkoutSession session) async {
    await repository.saveSession(session);
    sessions = await repository.getRecentSessions();
    notifyListeners();
  }

  Future<void> saveWorkout(Workout workout) async {
    await repository.saveWorkout(workout);
    workouts = await repository.getWorkouts();
    notifyListeners();
  }

  Future<void> addWeightEntry(double weightKg, DateTime date) async {
    weightEntries.removeWhere(
      (item) =>
          item.date.year == date.year &&
          item.date.month == date.month &&
          item.date.day == date.day,
    );
    weightEntries.add(BodyWeightEntry(date: date, weightKg: weightKg));
    weightEntries.sort((a, b) => a.date.compareTo(b.date));
    await preferences.setString(
      _weightsKey,
      jsonEncode(weightEntries.map((item) => item.toJson()).toList()),
    );
    notifyListeners();
  }

  Future<void> removeWeightEntry(BodyWeightEntry entry) async {
    weightEntries.remove(entry);
    await preferences.setString(
      _weightsKey,
      jsonEncode(weightEntries.map((item) => item.toJson()).toList()),
    );
    notifyListeners();
  }

  Map<String, dynamic>? _decode(String key) {
    final raw = preferences.getString(key);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } on FormatException {
      return null;
    }
  }

  void _decodeReminder() {
    final json = _decode(_reminderKey);
    if (json == null) return;
    reminderEnabled = json['enabled'] as bool? ?? false;
    reminderMinutes = json['minutes'] as int? ?? 18 * 60;
    reminderDays = {for (final day in json['days'] as List? ?? []) day as int};
  }

  Future<void> setReminder({
    bool? enabled,
    int? minutes,
    Set<int>? days,
  }) async {
    reminderEnabled = enabled ?? reminderEnabled;
    reminderMinutes = minutes ?? reminderMinutes;
    reminderDays = days ?? reminderDays;
    if (reminderEnabled) {
      reminderEnabled = await reminders?.requestPermission() ?? false;
    }
    await reminders?.reschedule(
      enabled: reminderEnabled,
      minutes: reminderMinutes,
      days: reminderDays,
    );
    await preferences.setString(
      _reminderKey,
      jsonEncode({
        'enabled': reminderEnabled,
        'minutes': reminderMinutes,
        'days': reminderDays.toList()..sort(),
      }),
    );
    notifyListeners();
  }

  Future<void> setWeeklyGoal(int value) async {
    weeklyGoal = value;
    await preferences.setInt(_weeklyGoalKey, value);
    notifyListeners();
  }

  void _decodeProfile() {
    final json = _decode(_profileKey);
    if (json == null) return;
    heightCm = (json['heightCm'] as num?)?.toDouble();
    age = json['age'] as int?;
    isMale = json['isMale'] as bool? ?? true;
    activityLevel = json['activityLevel'] as int? ?? 1;
  }

  Future<void> saveBodyProfile({
    required double heightCm,
    required int age,
    required bool isMale,
    required int activityLevel,
  }) async {
    this.heightCm = heightCm;
    this.age = age;
    this.isMale = isMale;
    this.activityLevel = activityLevel;
    await preferences.setString(
      _profileKey,
      jsonEncode({
        'heightCm': heightCm,
        'age': age,
        'isMale': isMale,
        'activityLevel': activityLevel,
      }),
    );
    notifyListeners();
  }

  void _decodeSchedule() {
    final json = _decode(_scheduleKey);
    if (json == null) return;
    schedule = {
      for (final entry in json.entries)
        int.parse(entry.key): entry.value as String,
    };
  }

  Future<void> setScheduleDay(int weekday, String? workoutId) async {
    if (workoutId == null) {
      schedule.remove(weekday);
    } else {
      schedule[weekday] = workoutId;
    }
    await preferences.setString(
      _scheduleKey,
      jsonEncode(schedule.map((day, id) => MapEntry('$day', id))),
    );
    notifyListeners();
  }

  Workout? scheduledWorkout(int weekday) {
    final id = schedule[weekday];
    if (id == null) return null;
    for (final workout in workouts) {
      if (workout.id == id) return workout;
    }
    return null;
  }

  /// The workout to feature on Home: today's scheduled plan, else the first
  /// plan matching the onboarding goal category, else the first plan.
  Workout? suggestedWorkout() {
    if (workouts.isEmpty) return null;
    final scheduled = scheduledWorkout(DateTime.now().weekday);
    if (scheduled != null) return scheduled;
    final currentGoal = goal;
    if (currentGoal != null) {
      for (final workout in workouts) {
        if (workout.category == currentGoal) return workout;
      }
    }
    return workouts.first;
  }

  void _decodeOnboarding() {
    final json = _decode(_onboardingKey);
    if (json == null) return;
    onboardingDone = json['done'] as bool? ?? false;
    goal = json['goal'] as String?;
    level = json['level'] as String?;
  }

  Future<void> completeOnboarding({String? goal, String? level}) async {
    onboardingDone = true;
    this.goal = goal;
    this.level = level;
    await preferences.setString(
      _onboardingKey,
      jsonEncode({'done': true, 'goal': goal, 'level': level}),
    );
    notifyListeners();
  }

  String exportJson() => const JsonEncoder.withIndent('  ').convert({
    'exportedAt': DateTime.now().toIso8601String(),
    'workouts': workouts.map((item) => item.toJson()).toList(),
    'sessions': sessions.map((item) => item.toJson()).toList(),
    'weightEntries': weightEntries.map((item) => item.toJson()).toList(),
    'schedule': schedule.map((day, id) => MapEntry('$day', id)),
  });

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode = mode;
    await preferences.setString(_themeKey, mode.name);
    notifyListeners();
  }

  Future<void> setMetric(bool value) async {
    useMetric = value;
    await preferences.setBool(_unitKey, value);
    notifyListeners();
  }
}
