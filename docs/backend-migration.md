# Chuyển FitFlow từ Firebase sang NestJS + MongoDB

> **Trạng thái:** 15 bước — fitflow-api #1–#9, fitflow #18–#24. Sau bước 15 app
> không còn phụ thuộc Firebase. Xem "Việc còn lại" ở cuối tài liệu.

Mục tiêu: bỏ hẳn Firebase (Auth + Firestore) khỏi app Flutter, thay bằng backend
NestJS dùng MongoDB + Mongoose. Google Sign-In vẫn ở client; backend
verify Google ID token rồi cấp JWT riêng. Giữ nguyên hành vi **local-first**:
ghi local trước, sync nền, merge theo id, xoá bằng tombstone, meta last-write-wins.

## Hai repository

| Repo | Nội dung |
|---|---|
| [`PRM-393-G5/fitflow`](https://github.com/PRM-393-G5/fitflow) | App Flutter (repo này) |
| [`PRM-393-G5/fitflow-api`](https://github.com/PRM-393-G5/fitflow-api) | Backend NestJS + MongoDB |

Khi phát triển local, clone hai repo cạnh nhau:

```sh
git clone https://github.com/PRM-393-G5/fitflow.git
git clone https://github.com/PRM-393-G5/fitflow-api.git
```

Backend ban đầu được làm trong thư mục `backend/` của repo này (PR #13–#17),
sau đó được tách sang `fitflow-api` kèm toàn bộ lịch sử commit; các PR đó được
làm lại ở `fitflow-api` (#1–#5) để review và lịch sử nằm cùng chỗ với code.

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

## Đồng bộ offline (outbox)

Firestore tự xếp hàng các lệnh ghi khi offline; REST thì không, nên app có
`SyncOutbox` (lưu trong SharedPreferences) + `OutboxSender`:

- Mỗi lệnh ghi (`PUT`/`DELETE /api/me/docs/...`) vào outbox trước, gửi nền sau.
- Chỉ giữ lệnh mới nhất cho mỗi document; gửi **tuần tự, đúng thứ tự** (DELETE
  không bao giờ vượt PUT trước nó); các PUT liên tiếp cùng loại gộp thành bulk ≤ 500.
- Lỗi tạm thời (offline, 5xx, 429, phiên hết hạn) → dừng, giữ lại, gửi tiếp ở lần
  sync sau; lỗi 4xx khác (dữ liệu bị server từ chối) → bỏ lệnh đó.
- Mỗi lệnh ghi nhớ tài khoản tạo ra nó; lệnh của tài khoản khác không bao giờ
  được gửi bằng phiên hiện tại.
- `syncDocs` gửi outbox trước khi tải về, và áp các lệnh còn treo lên bản server
  nên chỉnh sửa offline không bị "remote wins" ghi đè.
- `flushPendingWrites()` giữ nguyên hành vi chặn sign-out khi còn dữ liệu chưa sync.

## Lộ trình PR

Mỗi PR 3–4 commit, quy trình: branch → PR → review (comment trên PR) → fix → merge commit.
`main` luôn build/chạy được sau mỗi PR. Cột **Bước** là số thứ tự trong kế hoạch, **không phải**
số PR trên GitHub: bước 1–9 làm ở `fitflow-api` (bước N = `fitflow-api` PR #N), bước 10–15 làm ở `fitflow`.

| Bước | Branch | Nội dung |
|---|---|---|
| 1 | `chore/backend-scaffold` | Scaffold NestJS · validate env · prefix `/api` + ValidationPipe · README |
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

## Việc còn lại (ngoài code)

- **Dữ liệu cũ trên Firestore không được chuyển sang MongoDB.** Người dùng từng sync
  qua Firebase sẽ thấy tài khoản trống khi đăng nhập bằng API (dữ liệu trên máy vẫn
  còn và sẽ được upload khi đăng nhập). Nếu cần giữ dữ liệu cloud cũ: export từ
  Firebase console (hoặc script `firebase-admin` với service account) rồi import vào
  collection `userdocs`/`users` của `fitflow-api`.
- **Project Firebase `fitflow-cbbcb` vẫn hoạt động.** Gỡ file khỏi repo không thu hồi
  API key (vẫn còn trong lịch sử git) và không xoá dữ liệu/rules đã deploy. Sau khi
  không cần dữ liệu cũ nữa: tắt Firestore/Auth hoặc xoá project trong Firebase console.
- **Google Sign-In trên iOS chưa cấu hình** (`GIDClientID` + URL scheme trong
  `ios/Runner/Info.plist`); iOS hiện chạy local-only.
