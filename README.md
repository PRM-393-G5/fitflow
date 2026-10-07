# FitFlow

FitFlow is a Flutter workout-tracking MVP. It ships with built-in workout plans, guides a local workout session, and records progress on the device without requiring an account or network connection. Signing in with Google is optional and adds cloud backup and multi-device sync through the FitFlow API.

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

Accounts and sync need the FitFlow API running (see **Backend API**
below). The app works fully offline without it; only sign-in and cloud
sync are unavailable.

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

For a distributable Android release, configure a production application ID and release signing before running `flutter build apk --release` or `flutter build appbundle --release`.

## MVP features

- Home dashboard with weekly workout statistics and quick start
- Browse and filter bundled workout plans by category
- Workout details with exercise, set, repetition, and rest guidance
- Active workout flow with set completion, rest countdown, and finish confirmation
- Local workout history and progress summaries
- Activity heatmap, weekly minutes chart, and personal records
- Achievements derived from streaks, volume, and session counts
- Custom workout builder for user-created plans
- AI workout generator that builds a plan from a text prompt (OpenAI, needs `OPENAI_API_KEY` via `--dart-define`)
- Nutrition tab with a TDEE+goal calorie target, AI-suggested daily meal plans, food-photo analysis, and a local daily intake log vs target (same OpenAI key)
- Body weight log with trend chart plus BMI/BMR/TDEE profile
- Onboarding goal/level setup that personalizes suggested workouts
- Weekly schedule that pins a plan to each day
- AI form check for squat, push-up, and plank via on-device pose detection
- Reminder preferences, JSON export/import backup, and a shareable summary image
- Optional Google sign-in with cloud sync via the FitFlow API, sign-out and account deletion
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

FitFlow stores everything locally in `shared_preferences` first; when signed in, data is also synced to the cloud (see below).

- Bundled workouts are seeded on first access and stored as JSON under `workouts_v1`.
- Completed sessions are stored as JSON under `sessions_v1`.
- Body weight entries are stored as JSON under `body_weights_v1`.
- Theme and unit choices are stored under `theme_mode` and `unit_system`.
- Data is scoped to the app installation and may be removed when the app is uninstalled or its storage is cleared.
- Without signing in there is no sync or cross-device recovery; there is no encryption layer.

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
