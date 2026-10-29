# FitFlow

FitFlow is a Flutter workout-tracking MVP. It ships with built-in workout plans, guides a workout session, and records progress. A Google account is required: the app opens on the sign-in page, and every account's data is backed up and synced across devices through the FitFlow API. Data is cached on the device so reads are instant and edits made offline are kept until they reach the server.

## Toolchain

- Flutter stable with Dart compatible with `sdk: ^3.13.2` in `pubspec.yaml`
- Verified with Flutter 3.47.2 and Dart 3.13.2
- Android builds: Android SDK, an accepted Android SDK license set, and a JDK compatible with the Flutter/Gradle toolchain
- iOS builds (macOS only): Xcode and CocoaPods as required by Flutter

Check the local installation with:

```sh
flutter doctor -v
```

## Setup and run

```sh
flutter pub get
cp .env.example .env   # then put your OPENAI_API_KEY inside
flutter run
```

`.env` is gitignored and bundled as an asset — without it the build
fails on the missing asset entry, so create it even if empty.
`--dart-define=OPENAI_API_KEY=sk-...` also works.

The app needs the FitFlow API running (see **Backend API** below): signing
in goes through it. Once signed in, a lost connection only delays sync.

Select a target explicitly when needed, for example `flutter run -d <device-id>`. Android and iOS currently use the existing `com.zcode9211.prm` application identifier.

## Quality checks and tests

Run the same checks used for handoff:

```sh
flutter pub get
dart format --set-exit-if-changed .
flutter analyze
flutter test
flutter build apk --debug
```

The debug Android APK is generated at:

```text
build/app/outputs/flutter-apk/app-debug.apk
```

End-to-end tests on a real phone are separate: see **End-to-end tests**.

For a distributable Android release, configure a production application ID and release signing before running `flutter build apk --release` or `flutter build appbundle --release`.

## MVP features

- Home dashboard with weekly workout statistics and quick start
- Browse and filter bundled workout plans by category
- Workout details with exercise, set, repetition, and rest guidance
- Active workout flow with set completion, rest countdown, and finish confirmation
- Progressive-overload hints per exercise: double progression with the 2-for-2 rule, load steps rounded to real plates/dumbbells, deloads after three misses, lighter restarts after a break
- Local workout history and progress summaries
- Activity heatmap, weekly minutes chart, and personal records
- Muscle map: front/back anatomy colored by this week's sets for 15 muscles (from exercise names, helpers count half). Major muscles are judged against a weekly target set by training level (beginner 6–12, intermediate 10–20, advanced 12–22); smaller ones that grow from compound lifts have no target. Each muscle shows its change vs the same point last week; tap a muscle for the exercises behind it. Workout detail highlights the muscles a plan trains (body art from [react-native-body-highlighter](https://github.com/HichamELBSI/react-native-body-highlighter), MIT)
- Weekly streak (consecutive weeks reaching the weekly goal; rest days never break it) and achievements derived from it, volume, and session counts; camera form checks are not counted as workouts
- Custom workout builder for user-created plans
- AI workout generator that builds a plan from a text prompt (OpenAI, needs `OPENAI_API_KEY` via `--dart-define`)
- Nutrition tab with a TDEE+goal calorie target, AI-suggested daily meal plans, food-photo analysis, and a local daily intake log vs target (same OpenAI key)
- Body weight log with trend chart plus BMI/BMR/TDEE profile
- Onboarding goal/level setup that personalizes suggested workouts
- Weekly schedule that pins a plan to each day
- AI form check via on-device pose detection: squat, push-up, plank, shoulder press, biceps curl (dumbbell/hammer/barbell, alternating counts each arm), overhead triceps extension and dips. In a workout, "Count with camera" counts the set and logs it straight away (undo to fix a miscount). "Hands-free" runs the remaining camera sets back to back with no taps: each set ends at its target (or 8 s after the last rep), a spoken rest counts down, and it moves on to the next set or exercise, up to the first exercise the camera can't count
- Reminder preferences, JSON export/import backup, and a shareable summary image
- Required Google sign-in with cloud sync via the FitFlow API, sign-out and account deletion
- Session detail view per completed workout
- Theme selection (system, light, or dark)
- Metric/imperial preference
- Responsive Material UI for phone and wider layouts

## Backend API

Sign-in and sync use the FitFlow REST API, developed in a separate
repository: [PRM-393-G5/fitflow-api](https://github.com/PRM-393-G5/fitflow-api)
(NestJS + MongoDB). Clone it next to this repository and start it:

```sh
cd ../fitflow-api && npm install && cp .env.example .env
npm run build && npm run seed && npm run start:dev   # http://localhost:3001/api
```

The app finds it at `http://10.0.2.2:3001/api` on the Android emulator and
`http://localhost:3001/api` elsewhere. On a physical phone set your
computer's LAN address in `.env` (`API_BASE_URL=http://192.168.x.y:3001/api`)
or pass `--dart-define=API_BASE_URL=...`. Debug builds allow plain HTTP;
release builds need HTTPS.

How it works: Google Sign-In gives an ID token, the API verifies it and
returns its own session (stored in secure storage). Writes land locally
first and go out through a persisted outbox, so offline edits are not
lost. Access rules (public templates, each user limited to their own
data) are enforced by the API. Details and the migration history:
[`docs/backend-migration.md`](docs/backend-migration.md).

## End-to-end tests

`patrol_test/` drives the real app on an Android phone with
[Patrol](https://patrol.leancode.co): it taps through the screens, handles
native UI (Google's account picker, permission dialogs), and checks with
the API that the data really reached the server.

| Test | Covers |
| --- | --- |
| `auth_test.dart` | Google sign-in, the account shown in Profile, sign-out revoking the session |
| `workout_test.dart` | Full Body Foundation: log a set, finish, session synced, shown in History, deleted |
| `nutrition_test.dart` | The meal form refuses bad input; a two-dish meal with macros adds up on the day card and syncs; editing the portion, moving it to another meal, re-logging it from recent foods; removed |
| `body_metrics_test.dart` | Log today's weight, synced, deleted (a real weigh-in for today is put back) |
| `form_check_test.dart` | AI Form Check: camera permission, camera preview opens and closes |
| `planning_test.dart` | Onboarding as a new account (goal and level, Home's plan follows); the weekly schedule shown the same on Schedule, Workouts, Home, the weekly goal and Profile, and synced |
| `settings_test.dart` | Goal & level, kg/lb and theme from Profile; reminders scheduled on the chosen days; Sync pulling a meal logged elsewhere; export, and import refusing a bad file |

Before running:

1. The API is running with its templates seeded (see **Backend API**) and
   `API_BASE_URL` in `.env` is the computer's LAN address.
2. The phone is connected (`adb devices`) and signed in to a Google
   account. Every test clears the app's data first, so afterwards the app
   on the phone is signed out.
3. Patrol CLI is installed: `flutter pub global activate patrol_cli`, with
   `~/.pub-cache/bin` on `PATH`.

```sh
patrol test --device <adb-id> --dart-define=E2E_GOOGLE_ACCOUNT=you@gmail.com
patrol test --device <adb-id> -t patrol_test/workout_test.dart   # one file
```

Without `E2E_GOOGLE_ACCOUNT` the first account in Google's picker is
used. The tests run against that account's real data: they only touch
entries they create (names like `E2E dish 123456`) and delete them
again — through the API if a test fails after the entry reached the
server. Tests that change the goal, onboarding or weekly schedule put
the account's originals back when they end, pass or fail. Keep people
out of the camera's view during the form check, or it may count a rep.

## Architecture and directories

The project separates app composition, domain rules, persistence, and feature UI:

- `lib/main.dart`: Flutter entry point and dependency setup
- `lib/app/`: application shell, shared controller, and app scope
- `lib/core/`: theme, responsive layout, and reusable widgets
- `lib/domain/`: framework-independent models, statistics, and repository contracts
- `lib/data/`: bundled seed workouts and the local repository implementation
- `lib/features/`: feature-first presentation for home, workouts, progress, profile, and navigation
- `test/`: repository, statistics, and widget tests
- `android/` and `ios/`: native Flutter platform projects

`WorkoutRepository` keeps presentation code independent of storage. `LocalWorkoutRepository` is the current implementation.

## Local storage

The signed-in account's data is cached in `shared_preferences` and synced to the cloud (see **Backend API**). Signing out removes it from the device.

- Bundled workouts are seeded on first access and stored as JSON under `workouts_v1`.
- Completed sessions are stored as JSON under `sessions_v1`.
- Body weight entries are stored as JSON under `body_weights_v1`.
- Theme and unit choices are stored under `theme_mode` and `unit_system`.
- Data is scoped to the app installation and may be removed when the app is uninstalled or its storage is cleared.
- The cache has no encryption layer.

`shared_preferences` is appropriate for this MVP's small local dataset, but it is not intended for sensitive data or large relational datasets.

## Restore the archived Expo source

The previous Expo project is preserved outside this Flutter repository at:

```text
/home/elior/Documents/prm-expo-source-backup-20260921-221759.tar.gz
```

Expected SHA-256:

```text
5692a1d029cdfdb2cf2231a56491ac72487ed204fc46202271a8ec80dc1e3b8d
```

Restore it into a separate directory so it does not overwrite the active Flutter app:

```sh
sha256sum /home/elior/Documents/prm-expo-source-backup-20260921-221759.tar.gz
mkdir -p /home/elior/Documents/prm-expo-restored
tar -xzf /home/elior/Documents/prm-expo-source-backup-20260921-221759.tar.gz \
  -C /home/elior/Documents/prm-expo-restored --strip-components=1
```

The checksum must match before relying on the archive. Do not extract it over `/home/elior/Documents/prm` unless replacing the Flutter project is explicitly intended.

## Current limitations

- Cloud sync needs a reachable FitFlow API; release builds need it served over HTTPS.
- Workout templates are a small built-in catalog (bundled, refreshed from the API), plus locally created custom workouts.
- Local preferences are not a secure store and are not backed up by FitFlow.
- No push notifications, social features, subscriptions, or wearable integrations.
- Release signing and store distribution are not configured; the documented APK is a debug build.

The active project contains Flutter/Dart and native Flutter platform configuration only. Legacy Expo source and assets belong in the external backup described above, not in the active app.
