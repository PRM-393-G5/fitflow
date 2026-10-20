import 'dart:async';
import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/backend_auth_service.dart';
import '../data/sync_merge.dart';
import '../data/local_workout_repository.dart';
import '../data/reminder_service.dart';
import '../data/remote_workout_repository.dart';
import '../domain/meal_plan.dart';
import '../domain/models/body_weight_entry.dart';
import '../domain/models/workout.dart';
import '../domain/models/workout_session.dart';
import '../domain/repositories/workout_repository.dart';

class AppController extends ChangeNotifier {
  AppController(this.repository, this.preferences, {this.reminders, this.auth});

  static const _themeKey = 'theme_mode';
  static const _unitKey = 'unit_system';
  static const _weightsKey = 'body_weights_v1';
  static const _reminderKey = 'reminder_v1';
  static const _profileKey = 'body_profile_v1';
  static const _scheduleKey = 'schedule_v1';
  static const _onboardingKey = 'onboarding_v1';
  static const _weeklyGoalKey = 'weekly_goal_v1';
  static const _metaTsKey = 'meta_updated_at';
  static const _syncUidKey = 'sync_uid';
  static const _metaPulledKey = 'meta_pulled_uid';
  static const _skipSignInKey = 'sign_in_skipped_v1';

  /// Feature-owned keys holding per-user data (nutrition cache and food
  /// log); wiped with the rest of the user's data on account changes.
  static const _foodLogKey = 'food_log_v1';
  static const featureUserKeys = ['meal_plan_v1', _foodLogKey];

  /// Schedule value marking a deliberate rest day (vs. an unassigned day).
  static const restDay = 'rest';

  static const _userKeys = [
    _weightsKey,
    _profileKey,
    _scheduleKey,
    _onboardingKey,
    _weeklyGoalKey,
    _metaTsKey,
    _metaPulledKey,
    ...featureUserKeys,
  ];

  final WorkoutRepository repository;
  final SharedPreferences preferences;
  final ReminderService? reminders;
  final BackendAuthService? auth;

  List<Workout> workouts = [];
  List<WorkoutSession> sessions = [];
  List<BodyWeightEntry> weightEntries = [];

  /// Meals logged per day (last [FoodLog.keepDays] days), each synced
  /// as one `meals` doc.
  FoodLog foodLog = FoodLog();
  ThemeMode themeMode = ThemeMode.system;
  bool useMetric = true;
  bool loading = true;
  String? error;

  /// True while a background cloud merge runs; onboarding waits for it so
  /// a returning user's cloud profile arrives before deciding to show it.
  bool syncing = false;

  /// When the last sync reached every collection; null until one has.
  DateTime? lastSyncedAt;

  /// The last sync stopped early or skipped a collection (e.g. offline).
  bool lastSyncFailed = false;

  /// Bumped whenever the user's data is wiped (sign-out, account switch,
  /// import) so pages caching feature data can reload it.
  int dataEpoch = 0;

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

  /// The user chose to use the app without an account.
  bool get signInSkipped => preferences.getBool(_skipSignInKey) ?? false;

  bool get signedIn {
    final repo = repository;
    return repo is RemoteWorkoutRepository && repo.signedIn;
  }

  Future<void>? _loadChain;
  Future<void>? _reminderChain;

  /// Loads everything from local storage, then merges with the cloud in
  /// the background. Calls are serialized — an auth change can trigger a
  /// load while another one is still running.
  Future<void> load() {
    final next = (_loadChain ?? Future<void>.value()).then((_) => _load());
    _loadChain = next.catchError((Object _) {});
    return next;
  }

  Future<void> _load() async {
    loading = true;
    error = null;
    try {
      await _guardAccountSwitch();
    } catch (e) {
      debugPrint('Account switch check failed: $e');
    }
    // Settings and per-user state decode independently of the workout
    // data, so a bad record in one cannot reset the others.
    themeMode = ThemeMode.values.firstWhere(
      (mode) => mode.name == preferences.getString(_themeKey),
      orElse: () => ThemeMode.system,
    );
    useMetric = preferences.getBool(_unitKey) ?? true;
    _decodeReminder();
    try {
      workouts = await repository.getWorkouts();
      sessions = await repository.getRecentSessions();
    } catch (e) {
      debugPrint('Local load failed: $e');
      error = 'Could not load your local data.';
    }
    _decodeSyncedLists();
    _decodeUserState();
    loading = false;
    notifyListeners();
    unawaited(_restoreReminders());
    unawaited(sync());
  }

  /// Reads the synced per-entry lists (weights, food log) from storage.
  /// An older food-log format is rewritten at once, so the ids it was
  /// given stay the ones that sync.
  void _decodeSyncedLists() {
    weightEntries = _decodeWeights();
    final raw = preferences.getString(_foodLogKey);
    foodLog = FoodLog.decode(raw)..prune(clock.now());
    if (raw != null && !FoodLog.isCurrentFormat(raw)) {
      unawaited(_saveFoodLog());
    }
  }

  /// Resets the per-user fields to defaults, then decodes stored values.
  void _decodeUserState() {
    heightCm = null;
    age = null;
    isMale = true;
    activityLevel = 1;
    schedule = {};
    onboardingDone = false;
    goal = null;
    level = null;
    for (final decode in [_decodeProfile, _decodeSchedule, _decodeOnboarding]) {
      try {
        decode();
      } catch (e) {
        debugPrint('Skipping malformed stored state: $e');
      }
    }
    // Imports and remote meta store whatever they carry; read it back
    // within the range the picker offers.
    weeklyGoal = (preferences.getInt(_weeklyGoalKey) ?? 3).clamp(1, 7);
  }

  /// Wipes the user's local data (not settings) and the in-memory copy.
  Future<void> _clearUserData() async {
    for (final key in _userKeys) {
      await preferences.remove(key);
    }
    final repo = repository;
    if (repo is RemoteWorkoutRepository) {
      await repo.clearLocalData();
    } else if (repo is LocalWorkoutRepository) {
      await repo.clearAll();
    }
    sessions = [];
    lastSyncedAt = null;
    lastSyncFailed = false;
    _decodeSyncedLists();
    _decodeUserState();
    dataEpoch++;
  }

  /// When the signed-in account changes on this device, drop the previous
  /// account's synced local data first — otherwise it would merge into and
  /// upload to the new account's cloud. Sign-out flushes and clears data
  /// itself, so this only catches switches that bypassed it.
  Future<void> _guardAccountSwitch() async {
    final repo = repository;
    if (repo is! RemoteWorkoutRepository) return;
    final uid = repo.uid;
    if (uid == null) return;
    final lastUid = preferences.getString(_syncUidKey);
    if (lastUid == uid) return;
    if (lastUid != null) await _clearUserData();
    // lastUid == null → data created signed out (guest): keep it so it
    // uploads to this account. Its sessions/plans/weights merge by id; an
    // existing cloud profile wins (see [_mergeMeta]).
    await preferences.setString(_syncUidKey, uid);
  }

  /// Background cloud merge of workouts, sessions, weights and meta.
  /// Each network step is followed by a check that the account (and its
  /// data) is still the one the sync started for — a sign-out or account
  /// switch mid-sync must not write the old account's data back. Results
  /// are reconciled with edits made in the meantime, then stored.
  Future<void> sync() async {
    final repo = repository;
    if (repo is! RemoteWorkoutRepository || !repo.signedIn || syncing) {
      return;
    }
    final uid = repo.uid;
    final epoch = dataEpoch;
    bool stale() => dataEpoch != epoch || repo.uid != uid;
    syncing = true;
    var finished = false;
    // Only a meta push made by this sync counts towards its outcome.
    repo.metaPushFailed = false;
    notifyListeners();
    try {
      await repo.refreshTemplates();
      if (stale()) return;

      final customBefore = workouts.where(isCustomWorkout).toList();
      final mergedWorkouts = await repo.syncDocs(
        'workouts',
        customBefore.map((item) => item.toJson()).toList(),
      );
      if (stale()) return;
      final custom = mergedWorkouts == null
          ? workouts.where(isCustomWorkout).toList()
          : SyncMerge.reconcile(
              LocalWorkoutRepository.decodeList(
                jsonEncode(mergedWorkouts),
                Workout.fromJson,
              ),
              customBefore,
              workouts.where(isCustomWorkout).toList(),
              (item) => item.id,
            );
      final templates = await repo.getWorkouts();
      if (stale()) return;
      await repo.storeCustomWorkouts(custom);
      workouts = [
        ...templates.where((item) => !isCustomWorkout(item)),
        ...custom,
      ];

      final sessionsBefore = List.of(sessions);
      final mergedSessions = await repo.syncDocs(
        'sessions',
        sessionsBefore.map((item) => item.toJson()).toList(),
      );
      if (stale()) return;
      if (mergedSessions != null) {
        sessions = SyncMerge.reconcile(
          LocalWorkoutRepository.decodeList(
            jsonEncode(mergedSessions),
            WorkoutSession.fromJson,
          ),
          sessionsBefore,
          sessions,
          (item) => item.id,
        )..sort((a, b) => b.completedAt.compareTo(a.completedAt));
        await repo.storeSessions(sessions);
      }

      final weightsBefore = List.of(weightEntries);
      final mergedWeights = await repo.syncDocs(
        'weights',
        weightsBefore.map((item) => item.toJson()).toList(),
      );
      if (stale()) return;
      if (mergedWeights != null) {
        weightEntries = SyncMerge.reconcile(
          LocalWorkoutRepository.decodeList(
            jsonEncode(mergedWeights),
            BodyWeightEntry.fromJson,
          ),
          weightsBefore,
          weightEntries,
          (item) => item.id,
        )..sort((a, b) => a.date.compareTo(b.date));
        await _saveWeights();
      }

      final entriesBefore = foodLog.entries.toList();
      final mergedEntries = await repo.syncDocs('meals', [
        for (final entry in entriesBefore) entry.toJson(),
      ], since: FoodLog.oldestKept(clock.now()));
      if (stale()) return;
      if (mergedEntries != null) {
        final remoteEntries = <FoodEntry>[];
        for (final json in mergedEntries) {
          try {
            remoteEntries.add(FoodEntry.fromJson(json));
          } on FormatException {
            // Skip a malformed entry rather than failing the sync.
          }
        }
        foodLog = FoodLog.fromEntries(
          SyncMerge.reconcile(
            remoteEntries,
            entriesBefore,
            foodLog.entries.toList(),
            (entry) => entry.id,
          ),
        )..prune(clock.now());
        await _saveFoodLog();
      }

      final remote = await repo.pullMeta();
      if (stale()) return;
      await _mergeMeta(repo, remote);
      final complete =
          !repo.metaPushFailed &&
          [
            mergedWorkouts,
            mergedSessions,
            mergedWeights,
            mergedEntries,
          ].every((merged) => merged != null);
      lastSyncFailed = !complete;
      if (complete) lastSyncedAt = clock.now();
      finished = true;
    } catch (e) {
      debugPrint('Sync failed: $e');
      lastSyncFailed = true;
      finished = true;
    } finally {
      // Stopped early because the account or its data changed: this run
      // says nothing about the (new) data, so claim no failure either.
      if (!finished) lastSyncFailed = false;
      syncing = false;
      notifyListeners();
    }
  }

  /// Last-write-wins meta sync (profile, schedule, onboarding, weekly goal)
  /// against `/api/me/meta`. Until this device has pulled the doc
  /// once for the account, the cloud copy wins outright: local values are
  /// then only defaults or a guest's data, and must not overwrite an
  /// existing profile.
  Future<void> _mergeMeta(
    RemoteWorkoutRepository repo,
    Map<String, dynamic>? remote,
  ) async {
    final firstPull = preferences.getString(_metaPulledKey) != repo.uid;
    await preferences.setString(_metaPulledKey, repo.uid!);
    final localTs = preferences.getInt(_metaTsKey) ?? 0;
    final remoteTs = remote?['updatedAt'] as int? ?? 0;
    if (remote != null && (firstPull || remoteTs > localTs)) {
      await _applyRemoteMeta(remote);
    } else if (remoteTs < localTs || remote == null) {
      // Awaited so the sync knows whether the profile reached the cloud.
      await _pushMeta(wait: true);
    }
  }

  Map<String, Object?> _metaSnapshot() => {
    'profile': {
      'heightCm': heightCm,
      'age': age,
      'isMale': isMale,
      'activityLevel': activityLevel,
    },
    'schedule': schedule.map((day, id) => MapEntry('$day', id)),
    'onboarding': {'done': onboardingDone, 'goal': goal, 'level': level},
    'weeklyGoal': weeklyGoal,
  };

  Future<void> _applyRemoteMeta(Map<String, dynamic> remote) async {
    // Older app versions kept weights in the meta doc — merge them in
    // rather than replace (they now sync per entry).
    final legacyWeights = remote['weights'];
    if (legacyWeights is List && legacyWeights.isNotEmpty) {
      final legacy = LocalWorkoutRepository.decodeList(
        jsonEncode(legacyWeights),
        BodyWeightEntry.fromJson,
      );
      // Local entries win: they are newer than the legacy blob.
      weightEntries = SyncMerge.mergeById(
        legacy,
        weightEntries,
        (item) => item.id,
      )..sort((a, b) => a.date.compareTo(b.date));
      await _saveWeights();
    }
    await preferences.setString(
      _profileKey,
      jsonEncode(remote['profile'] ?? {}),
    );
    await preferences.setString(
      _scheduleKey,
      jsonEncode(remote['schedule'] ?? {}),
    );
    await preferences.setString(
      _onboardingKey,
      jsonEncode(remote['onboarding'] ?? {}),
    );
    await preferences.setInt(_weeklyGoalKey, remote['weeklyGoal'] as int? ?? 3);
    await preferences.setInt(_metaTsKey, remote['updatedAt'] as int? ?? 0);
    _decodeUserState();
    // Re-push once so the legacy weights field is removed from the cloud.
    if (legacyWeights is List && legacyWeights.isNotEmpty) await _pushMeta();
  }

  /// Stamps the meta change and pushes it to the cloud in the background
  /// (when signed in) — the UI never waits on the network.
  Future<void> _pushMeta({bool wait = false}) async {
    final ts = clock.now().millisecondsSinceEpoch;
    await preferences.setInt(_metaTsKey, ts);
    final repo = repository;
    if (repo is RemoteWorkoutRepository &&
        repo.signedIn &&
        preferences.getString(_metaPulledKey) == repo.uid) {
      final uid = repo.uid;
      final epoch = dataEpoch;
      final push = repo.pushMeta(_metaSnapshot(), ts).then((newer) async {
        // Another device wrote a newer profile meanwhile: adopt it,
        // unless the account, local data or meta changed since, or a
        // sync is merging meta right now (it will pick the newer copy).
        if (newer == null || repo.uid != uid || dataEpoch != epoch) return;
        if (preferences.getInt(_metaTsKey) != ts || syncing) return;
        try {
          await _applyRemoteMeta(newer);
          notifyListeners();
        } catch (e) {
          debugPrint('Could not apply newer profile: $e');
        }
      });
      if (wait) {
        await push;
      } else {
        unawaited(push);
      }
    }
  }

  List<BodyWeightEntry> _decodeWeights() {
    final entries = LocalWorkoutRepository.decodeList(
      preferences.getString(_weightsKey),
      BodyWeightEntry.fromJson,
    );
    entries.sort((a, b) => a.date.compareTo(b.date));
    return entries;
  }

  Future<void> _saveWeights() => preferences.setString(
    _weightsKey,
    jsonEncode(weightEntries.map((item) => item.toJson()).toList()),
  );

  /// Saves [session], replacing any session with the same id — also how
  /// an edited session is stored (and synced).
  Future<void> addSession(WorkoutSession session) async {
    await repository.saveSession(session);
    sessions = [session, ...sessions.where((item) => item.id != session.id)]
      ..sort((a, b) => b.completedAt.compareTo(a.completedAt));
    notifyListeners();
  }

  Future<void> deleteSession(String id) async {
    await repository.deleteSession(id);
    sessions = sessions.where((item) => item.id != id).toList();
    notifyListeners();
  }

  Future<void> saveWorkout(Workout workout) async {
    await repository.saveWorkout(workout);
    final index = workouts.indexWhere((item) => item.id == workout.id);
    workouts = [...workouts];
    if (index < 0) {
      workouts.add(workout);
    } else {
      workouts[index] = workout;
    }
    notifyListeners();
  }

  /// User-created plans (builder or AI) can be edited and deleted;
  /// templates cannot.
  static bool isCustomWorkout(Workout workout) =>
      workout.id.startsWith('custom-');

  Future<void> deleteWorkout(String id) async {
    await repository.deleteWorkout(id);
    workouts = workouts.where((item) => item.id != id).toList();
    if (schedule.containsValue(id)) {
      schedule.removeWhere((_, workoutId) => workoutId == id);
      await _saveSchedule();
    }
    notifyListeners();
  }

  /// Logs [weightKg] for [date]'s calendar day, replacing that day's entry.
  Future<void> addWeightEntry(double weightKg, DateTime date) async {
    final entry = BodyWeightEntry(date: date, weightKg: weightKg);
    weightEntries.removeWhere((item) => item.id == entry.id);
    weightEntries.add(entry);
    weightEntries.sort((a, b) => a.date.compareTo(b.date));
    await _saveWeights();
    final repo = repository;
    if (repo is RemoteWorkoutRepository) {
      repo.putDoc('weights', entry.id, entry.toJson());
    }
    notifyListeners();
  }

  /// Adds [meal] to [day]'s food log.
  Future<void> logMeal(DateTime day, Meal meal) async {
    final entry = foodLog.add(day, meal);
    await _saveFoodLog();
    _putMealEntry(entry);
    notifyListeners();
  }

  /// Replaces logged entry [id]; a no-op when it is no longer there.
  Future<void> replaceMeal(String id, Meal meal) async {
    final entry = foodLog.replace(id, meal);
    if (entry == null) return;
    await _saveFoodLog();
    _putMealEntry(entry);
    notifyListeners();
  }

  /// Removes logged entry [id]; a no-op when it is no longer there.
  Future<void> removeMeal(String id) async {
    if (foodLog.remove(id) == null) return;
    await _saveFoodLog();
    final repo = repository;
    if (repo is RemoteWorkoutRepository) repo.deleteDoc('meals', id);
    notifyListeners();
  }

  void _putMealEntry(FoodEntry entry) {
    final repo = repository;
    if (repo is RemoteWorkoutRepository) {
      repo.putDoc('meals', entry.id, entry.toJson());
    }
  }

  Future<void> _saveFoodLog() async {
    try {
      await preferences.setString(_foodLogKey, jsonEncode(foodLog.toJson()));
    } catch (e) {
      debugPrint('Saving the food log failed: $e');
    }
  }

  Future<void> removeWeightEntry(BodyWeightEntry entry) async {
    weightEntries.removeWhere((item) => item.id == entry.id);
    await _saveWeights();
    final repo = repository;
    if (repo is RemoteWorkoutRepository) {
      repo.deleteDoc('weights', entry.id);
    }
    notifyListeners();
  }

  Map<String, dynamic>? _decode(String key) {
    final raw = preferences.getString(key);
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw);
      return json is Map<String, dynamic> ? json : null;
    } on FormatException {
      return null;
    }
  }

  void _decodeReminder() {
    try {
      final json = _decode(_reminderKey);
      if (json == null) return;
      reminderEnabled = json['enabled'] as bool? ?? false;
      reminderMinutes = json['minutes'] as int? ?? 18 * 60;
      reminderDays = {
        for (final day in json['days'] as List? ?? []) day as int,
      };
    } catch (e) {
      debugPrint('Skipping malformed reminder settings: $e');
    }
  }

  /// Scheduled notifications don't survive force-stop or some OEM reboots;
  /// re-register them on every start. Queued with [setReminder] so it can't
  /// re-schedule after the user has just turned reminders off.
  Future<void> _restoreReminders() => _queueReminder(() async {
    if (!reminderEnabled || reminderDays.isEmpty) return true;
    try {
      await reminders?.reschedule(
        enabled: true,
        minutes: reminderMinutes,
        days: reminderDays,
      );
    } catch (e) {
      debugPrint('Could not restore reminders: $e');
    }
    return true;
  });

  Future<bool> _queueReminder(Future<bool> Function() task) {
    final next = (_reminderChain ?? Future<void>.value()).then((_) => task());
    _reminderChain = next.catchError((Object _) => true);
    return next;
  }

  /// Adds or removes [weekday] from the reminder days. The new set is
  /// computed when the queued update runs, so rapid taps compose.
  Future<void> toggleReminderDay(int weekday) => _queueReminder(() {
    final days = {...reminderDays};
    if (!days.remove(weekday)) days.add(weekday);
    return _setReminder(days: days);
  });

  /// Updates reminder settings. Returns false when turning reminders on
  /// failed because notification permission was denied. Calls are
  /// serialized so rapid taps cannot interleave cancel/schedule.
  Future<bool> setReminder({bool? enabled, int? minutes, Set<int>? days}) =>
      _queueReminder(
        () => _setReminder(enabled: enabled, minutes: minutes, days: days),
      );

  Future<bool> _setReminder({
    bool? enabled,
    int? minutes,
    Set<int>? days,
  }) async {
    final wantEnabled = enabled ?? reminderEnabled;
    var granted = true;
    if (wantEnabled && enabled == true && reminders != null) {
      granted = await reminders!.requestPermission();
    }
    reminderEnabled = wantEnabled && granted;
    reminderMinutes = minutes ?? reminderMinutes;
    reminderDays = days ?? reminderDays;
    await reminders?.reschedule(
      enabled: reminderEnabled && reminderDays.isNotEmpty,
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
    return granted;
  }

  /// Sessions per week, 1–7.
  Future<void> setWeeklyGoal(int value) async {
    weeklyGoal = value.clamp(1, 7);
    await preferences.setInt(_weeklyGoalKey, weeklyGoal);
    await _pushMeta();
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
    await _pushMeta();
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

  Future<void> _saveSchedule() async {
    await preferences.setString(
      _scheduleKey,
      jsonEncode(schedule.map((day, id) => MapEntry('$day', id))),
    );
    await _pushMeta();
  }

  /// Assigns [workoutId] to [weekday]; [restDay] marks a rest day, null
  /// clears the day.
  Future<void> setScheduleDay(int weekday, String? workoutId) async {
    if (workoutId == null) {
      schedule.remove(weekday);
    } else {
      schedule[weekday] = workoutId;
    }
    await _saveSchedule();
    notifyListeners();
  }

  bool isRestDay(int weekday) => schedule[weekday] == restDay;

  Workout? scheduledWorkout(int weekday) {
    final id = schedule[weekday];
    if (id == null || id == restDay) return null;
    for (final workout in workouts) {
      if (workout.id == id) return workout;
    }
    return null;
  }

  /// The workout to feature on Home: today's scheduled plan, else the
  /// first plan matching the onboarding goal (preferring the chosen level),
  /// else the first plan. Null on a scheduled rest day.
  Workout? suggestedWorkout() {
    if (workouts.isEmpty) return null;
    final today = clock.now().weekday;
    if (isRestDay(today)) return null;
    final scheduled = scheduledWorkout(today);
    if (scheduled != null) return scheduled;
    final currentGoal = goal;
    final currentLevel = level;
    if (currentGoal != null) {
      final matches = workouts.where((item) => item.category == currentGoal);
      for (final workout in matches) {
        if (currentLevel == null || workout.level == currentLevel) {
          return workout;
        }
      }
      if (matches.isNotEmpty) return matches.first;
    }
    if (currentLevel != null) {
      for (final workout in workouts) {
        if (workout.level == currentLevel) return workout;
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
    await _pushMeta();
    notifyListeners();
  }

  /// Updates the training goal/level later on (e.g. from Profile).
  Future<void> setGoal({String? goal, String? level}) =>
      completeOnboarding(goal: goal, level: level);

  static const _exportVersion = 2;

  /// The user's own data as JSON — a backup [importJson] can restore.
  /// Templates are left out; they ship with the app.
  String exportJson() => const JsonEncoder.withIndent('  ').convert({
    'app': 'FitFlow',
    'version': _exportVersion,
    'exportedAt': clock.now().toIso8601String(),
    'workouts': workouts
        .where(isCustomWorkout)
        .map((item) => item.toJson())
        .toList(),
    'sessions': sessions.map((item) => item.toJson()).toList(),
    'weightEntries': weightEntries.map((item) => item.toJson()).toList(),
    ..._metaSnapshot(),
    'settings': {
      'useMetric': useMetric,
      'themeMode': themeMode.name,
      'reminder': {
        'enabled': reminderEnabled,
        'minutes': reminderMinutes,
        'days': reminderDays.toList()..sort(),
      },
    },
  });

  /// Restores an [exportJson] backup, merging by id: imported sessions,
  /// plans and weights are added or replace same-id ones; profile, schedule
  /// and goals are replaced when present. Throws [FormatException] when
  /// [raw] is not a FitFlow export. Returns the number of records imported.
  Future<int> importJson(String raw) async {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      throw const FormatException('Not valid JSON.');
    }
    if (decoded is! Map<String, dynamic> ||
        (decoded['sessions'] is! List && decoded['workouts'] is! List)) {
      throw const FormatException('Not a FitFlow export.');
    }
    final imported = LocalWorkoutRepository.decodeList(
      jsonEncode(decoded['sessions'] ?? []),
      WorkoutSession.fromJson,
    );
    final plans = LocalWorkoutRepository.decodeList(
      jsonEncode(decoded['workouts'] ?? []),
      Workout.fromJson,
    ).where(isCustomWorkout).toList();
    final weights = LocalWorkoutRepository.decodeList(
      jsonEncode(decoded['weightEntries'] ?? []),
      BodyWeightEntry.fromJson,
    );
    for (final session in imported) {
      await repository.saveSession(session);
    }
    for (final plan in plans) {
      await repository.saveWorkout(plan);
    }
    for (final entry in weights) {
      await addWeightEntry(entry.weightKg, entry.date);
    }
    final profile = decoded['profile'];
    if (profile is Map<String, dynamic>) {
      await preferences.setString(_profileKey, jsonEncode(profile));
    }
    final importedSchedule = decoded['schedule'];
    if (importedSchedule is Map<String, dynamic>) {
      await preferences.setString(_scheduleKey, jsonEncode(importedSchedule));
    }
    final onboarding = decoded['onboarding'];
    if (onboarding is Map<String, dynamic>) {
      await preferences.setString(_onboardingKey, jsonEncode(onboarding));
    }
    final importedGoal = decoded['weeklyGoal'];
    if (importedGoal is int) {
      await preferences.setInt(_weeklyGoalKey, importedGoal);
    }
    final settings = decoded['settings'];
    if (settings is Map<String, dynamic>) {
      if (settings['useMetric'] case final bool metric) await setMetric(metric);
      if (settings['themeMode'] case final String mode) {
        await setThemeMode(
          ThemeMode.values.firstWhere(
            (item) => item.name == mode,
            orElse: () => themeMode,
          ),
        );
      }
      final reminder = settings['reminder'];
      if (reminder is Map<String, dynamic>) {
        await setReminder(
          enabled: reminder['enabled'] as bool? ?? false,
          minutes: reminder['minutes'] as int? ?? reminderMinutes,
          days: {
            for (final day in reminder['days'] as List? ?? [])
              if (day is int && day >= 1 && day <= 7) day,
          },
        );
      }
    }
    workouts = await repository.getWorkouts();
    sessions = await repository.getRecentSessions();
    _decodeUserState();
    await _pushMeta();
    dataEpoch++;
    notifyListeners();
    return imported.length + plans.length + weights.length;
  }

  /// Marks that the user continues without an account (local-only).
  Future<void> skipSignIn() async {
    await preferences.setBool(_skipSignInKey, true);
    notifyListeners();
  }

  /// Signs out and removes the account's data from this device (it stays
  /// in the cloud). Returns false without signing out when some changes
  /// have not reached the server yet, unless [force] — signing out would
  /// drop them.
  Future<bool> signOut({bool force = false}) async {
    final repo = repository;
    if (repo is RemoteWorkoutRepository) {
      final uid = repo.uid;
      if (!await repo.flushPendingWrites()) {
        if (!force) return false;
        // Forced: undelivered writes must not reach the account later.
        if (uid != null) await repo.discardPendingWrites(uid);
      }
    }
    await auth?.signOut();
    await _clearUserData();
    await preferences.remove(_syncUidKey);
    await preferences.remove(_skipSignInKey);
    await load();
    return true;
  }

  /// Permanently deletes the account. Re-authenticates first, so a
  /// cancelled or failed Google prompt aborts before anything is deleted;
  /// then the API deletes the account with all its cloud data (fails
  /// offline, leaving the account intact), then local data goes.
  Future<void> deleteAccount() async {
    final auth = this.auth;
    final uid = auth?.currentUser?.id;
    if (auth == null || uid == null) {
      throw StateError('Not signed in');
    }
    final idToken = await auth.reauthenticate();
    await auth.deleteAccount(idToken);
    final repo = repository;
    if (repo is RemoteWorkoutRepository) await repo.discardPendingWrites(uid);
    await _clearUserData();
    await preferences.remove(_syncUidKey);
    await preferences.remove(_skipSignInKey);
    await load();
  }

  /// Deletes all data on this device while signed out (guest mode).
  Future<void> clearLocalData() async {
    await _clearUserData();
    await load();
  }

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
