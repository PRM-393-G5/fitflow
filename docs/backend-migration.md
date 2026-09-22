# Chuyển FitFlow từ Firebase sang NestJS + MongoDB

Mục tiêu: bỏ hẳn Firebase (Auth + Firestore) khỏi app Flutter, thay bằng backend
NestJS (`backend/`) dùng MongoDB + Mongoose. Google Sign-In vẫn ở client; backend
verify Google ID token rồi cấp JWT riêng. Giữ nguyên hành vi **local-first**:
ghi local trước, sync nền, merge theo id, xoá bằng tombstone, meta last-write-wins.

## Thiết kế backend

### Collections

| Collection | Fields chính | Index | Thay cho (Firestore) |
|---|---|---|---|
| `users` | `googleSub`, `email`, `name`, `photoUrl`, `meta`, `metaUpdatedAt` | `googleSub` unique | `users/{uid}` (meta doc) |
| `userdocs` | `userId`, `kind` (`sessions` \| `workouts` \| `weights`), `docId`, `data`, `deleted`, `updatedAt` | `(userId, kind, docId)` unique | `users/{uid}/{kind}/{docId}` |
| `workouttemplates` | `_id` (id cũ), `name`, `category`, `level`, `exercises`... | — | `workouts/{id}` |

### API (prefix `/api`)

| Method | Route | Auth | Thay cho |
|---|---|---|---|
| POST | `/auth/google` `{idToken}` → `{accessToken, refreshToken, user}` | — | `signInWithCredential` |
| POST | `/auth/refresh`, `/auth/logout` | refresh token | Firebase tự quản token |
| GET | `/me` | JWT | `currentUser` |
| DELETE | `/me` `{idToken}` (bắt đăng nhập Google lại) | JWT | `reauthenticate` + `user.delete()` + `deleteCloudData` |
| GET | `/templates` | — | collection `workouts` |
| GET | `/me/docs/:kind` (kèm tombstone) | JWT | `collection.get()` |
| PUT | `/me/docs/:kind` (bulk upsert ≤ 500) | JWT | `batch.set` |
| PUT | `/me/docs/:kind/:id` | JWT | `putDoc` |
| DELETE | `/me/docs/:kind/:id` → tombstone | JWT | `deleteDoc` |
| GET / PUT | `/me/meta` | JWT | `pullMeta` / `pushMeta` |

- Google ID token verify bằng `google-auth-library`, `audience` = web client ID
  app đang dùng làm `serverClientId`.
- JWT access 15 phút + refresh 30 ngày (hash lưu DB để logout thu hồi được).

## Thay đổi phía Flutter

- Bỏ `firebase_core`, `firebase_auth`, `cloud_firestore`; thêm `http`, `flutter_secure_storage`.
- `ApiClient`: base URL từ `.env` (`API_BASE_URL`; emulator Android dùng `http://10.0.2.2:3001/api`), tự refresh khi 401.
- `AuthService` mới: model `AppUser`, stream `userChanges`.
- `RemoteWorkoutRepository` thay `FirestoreWorkoutRepository`, giữ API public để `AppController` ít đổi.
  Firestore tự queue ghi offline, REST thì không → thêm **outbox** trong SharedPreferences;
  `flushPendingWrites()` đẩy outbox (giữ logic chặn sign-out khi còn dữ liệu chưa sync).
- Xoá `firebase_options.dart`, `firebase.json`, `firestore.rules`, `google-services.json`, plugin google-services.

## Lộ trình PR

Mỗi PR 3–4 commit, quy trình: branch → PR → review (comment trên PR) → fix → merge commit.
`main` luôn build/chạy được sau mỗi PR.

| # | Branch | Nội dung |
|---|---|---|
| 1 | `chore/backend-scaffold` | Scaffold NestJS · validate env · prefix `/api` + ValidationPipe · README + tài liệu này |
| 2 | `feat/backend-database` | Kết nối Mongoose · `/health` có ping DB · exception filter chung · test |
| 3 | `feat/backend-users` | `User` schema · `UsersService` (findOrCreate theo `googleSub`) · module · unit test |
| 4 | `feat/backend-google-auth` | `GoogleVerifier` · `POST /auth/google` · DTO · test (mock verify) |
| 5 | `feat/backend-jwt` | Access/refresh token · `JwtAuthGuard` + `@CurrentUser` · refresh/logout · `GET /me` |
| 6 | `feat/backend-templates` | `WorkoutTemplate` schema · `npm run seed` · `GET /templates` · test |
| 7 | `feat/backend-user-docs` | `UserDoc` schema · GET / PUT / bulk PUT / DELETE (tombstone) · test |
| 8 | `feat/backend-meta-account` | `/me/meta` last-write-wins · `DELETE /me` · e2e với `mongodb-memory-server` |
| 9 | `chore/backend-hardening` | Swagger `/api/docs` · helmet + CORS · rate limit auth · CI GitHub Actions |
| 10 | `feat/flutter-api-client` | `http` + secure storage · `ApiClient` · refresh khi 401 · test mock HTTP |
| 11 | `feat/flutter-backend-auth` | `AppUser` · `BackendAuthService` · sign-out/reauth/delete · `describeAuthError` |
| 12 | `feat/flutter-remote-repo` | `RemoteWorkoutRepository`: templates · `syncDocs` · meta · chuyển `cloud_sync_test` |
| 13 | `feat/flutter-sync-outbox` | Outbox offline · `flushPendingWrites` · `deleteCloudData` · test |
| 14 | `feat/flutter-wire-backend` | `main.dart` · `AppController` · `AuthGate`/`LoginPage` · `ProfilePage` |
| 15 | `chore/remove-firebase` | Gỡ package + file + Gradle plugin Firebase · cập nhật README/docs |
