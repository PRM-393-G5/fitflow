# FitFlow — Báo cáo kiểm thử End-to-End (Patrol)

Ngày chạy: 30–31/10/2026 · Code app: `main` @ `92ae849` · Bộ test: `patrol_test/`

## Tóm tắt

| | |
|---|---|
| Tổng số test E2E | **11** |
| Đạt | **11 ✅** |
| Lỗi | 0 |
| Bỏ qua | 0 |
| Lỗi tìm thấy trong app | 0 — ba lỗi tìm thấy đều nằm trong code test và đã sửa (xem [Lỗi đã sửa](#lỗi-đã-sửa-trong-code-test)) |
| Dữ liệu test còn sót trên server | 0 |

Mỗi test chạy trên điện thoại Android thật, gọi API thật, và hỏi lại API để chắc
dữ liệu đã lên server — không mock.

## Môi trường

| Thành phần | Phiên bản / cấu hình |
|---|---|
| Thiết bị | Xiaomi Redmi Note 14 (`24117RN76O`), HyperOS 3.0, Android 16 |
| Kết nối | adb không dây (Wi‑Fi) |
| Flutter / Dart | 3.47.2 / 3.13.2 |
| Patrol | `patrol` 4.10.0, `patrol_finders` 3.6.0, `patrol_cli` 4.8.0 |
| Runner Android | `PatrolJUnitRunner` + Android Test Orchestrator 1.5.1, xoá dữ liệu app trước mỗi test (`clearPackageData`) |
| Backend | `fitflow-api` `main` @ `2266f86`, Node 24.22.2, MongoDB 8.0.19 |
| Đường tới API | `https://fitflow-api.polarislab.asia/api` (Cloudflare Tunnel → `localhost:3001`) |
| Tài khoản | Một tài khoản Google thật trên máy, chọn qua `--dart-define=E2E_GOOGLE_ACCOUNT=…` |

## Kết quả chi tiết

| # | File | Test | Kết quả | Thời gian | Chạy lúc |
|---|---|---|---|---|---|
| 1 | `auth_test.dart` | signs in with Google and signs out | ✅ | 27,0 s | 31/10 07:52 |
| 2 | `body_metrics_test.dart` | logs today's weight, syncs it, and deletes it | ✅ | 24,7 s | 31/10 07:52 |
| 3 | `form_check_test.dart` | opens the camera for an AI form check | ✅ | 27,1 s | 31/10 07:53 |
| 4 | `nutrition_test.dart` | logs a two-dish meal with macros; the day totals follow | ✅ | 36,8 s | 31/10 07:53 |
| 5 | `nutrition_test.dart` | edits a logged meal: portion, slot, and logs it again from recent foods | ✅ | 44,8 s | 31/10 07:54 |
| 6 | `planning_test.dart` | a new account answers onboarding, and Home follows its goal | ✅ | 27,8 s | 30/10 17:26 |
| 7 | `planning_test.dart` | plans the week: a plan today, rest tomorrow, then rest today | ✅ | 34,8 s | 30/10 17:27 |
| 8 | `settings_test.dart` | changes goal & level, units and theme from Profile | ✅ | 28 s | 30/10 17:59 |
| 9 | `settings_test.dart` | schedules weekly reminders on the chosen days | ✅ | 21 s | 30/10 18:00 |
| 10 | `settings_test.dart` | Sync brings in a meal logged elsewhere; export and import | ✅ | 21 s | 30/10 18:00 |
| 11 | `workout_test.dart` | logs a workout, syncs it, and deletes it from history | ✅ | 22,5 s | 30/10 17:35 |

Mỗi test được ghi theo lần chạy đạt gần nhất của nó. Các lần sửa test chỉ đụng
`nutrition_test`, `settings_test`, `form_check_test` và helper `loggedMeal`;
`planning_test`, `workout_test` không dùng những phần đó.

### Từng test kiểm tra gì

**1. Đăng nhập / đăng xuất** (`auth_test`)
- Đăng nhập qua bảng chọn tài khoản Google (UI native, Patrol bấm).
- API trả về đúng tài khoản app đang hiện (`GET /me`), Profile hiện đúng email, phiên đăng nhập được lưu trên máy.
- Đăng xuất: xoá phiên trên máy, và phiên bị thu hồi cả trên server (refresh token cũ nhận `401`).

**2. Cân nặng** (`body_metrics_test`)
- Ghi 88,8 kg (hoặc lb, theo đơn vị đang dùng) cho hôm nay; trang cân nặng hiện giá trị mới, API nhận được.
- Xoá bản ghi; nếu tài khoản đã có cân nặng thật của hôm nay, test trả lại đúng giá trị đó.

**3. AI Form Check** (`form_check_test`)
- Mở form check từ Home, cấp quyền camera qua hộp thoại hệ thống.
- Camera preview được dựng (camera đã khởi tạo), không có lỗi "Could not open the camera".
- Đóng lại sạch sẽ, không lưu buổi tập nào.

**4. Bữa ăn hai món** (`nutrition_test`)
- Nút ghi bị khoá khi chưa có tên món, khi kcal = 0, và khi macro không phải số (hiện thông báo lỗi).
- Hai món có macro: chân form cộng đúng `450 kcal` và `2 dishes · P 22g · C 51g · F 15g`.
- Bữa hiện trong slot Breakfast; tổng kcal và macro của ngày tăng đúng; API lưu đúng hai món.
- Xoá bữa: tổng ngày về như cũ, server nhận lệnh xoá.

**5. Sửa bữa ăn** (`nutrition_test`)
- Đổi khẩu phần 1½×: kcal và macro nhân đúng (200 → 300 kcal), tổng ngày và server khớp.
- Chuyển từ Breakfast sang Lunch: vẫn là một bữa (cùng id), không tạo bản sao.
- Ghi lại từ "recent foods" vào Dinner bằng một chạm, giữ khẩu phần đã sửa.
- Xoá cả hai bữa, tổng ngày về như cũ.

**6. Onboarding** (`planning_test`)
- Đưa tài khoản về như mới (chưa onboarding, chưa xếp lịch tuần).
- Phải chọn đủ mục tiêu và trình độ mới bắt đầu được; Home đề xuất plan sức mạnh đúng trình độ đã chọn.
- Onboarding và lịch gốc của tài khoản được trả lại khi test kết thúc.

**7. Lịch tuần** (`planning_test`)
- Từ ô "Today" của tab Workouts, bắt đầu từ tuần trống: xếp plan cho hôm nay, nghỉ cho ngày mai.
- Hôm nay hiện giống nhau ở Schedule, Workouts, Home và Profile; một ngày có plan → mục tiêu tuần = 1; lịch đồng bộ lên server.
- Đổi hôm nay thành ngày nghỉ từ lối tắt lịch trên Home.
- Lịch gốc được trả lại khi test kết thúc.

**8. Goal, đơn vị, theme** (`settings_test`)
- Đổi Goal & level trên Profile → hiện đúng và đồng bộ lên server.
- Bật đơn vị lb: Profile, trang cân nặng và form nhập cân đều theo; tắt lại về kg.
- Theme Dark / Light ghi đè cài đặt của máy (kiểm tra độ sáng thật của theme), rồi về System.

**9. Nhắc nhở tập** (`settings_test`)
- Bật nhắc nhở, cấp quyền thông báo: mặc định T2, T4, T6 lúc 18:00 được lên lịch trên máy.
- Đổi T2 thành T7 → lịch nhắc đúng T4, T6, T7; tắt thì không còn nhắc nào.

**10. Sync, export, import** (`settings_test`)
- Một "máy khác" ghi bữa trưa qua API; bấm Sync now → bữa hiện trong app.
- Xoá bữa trong app → server cũng xoá.
- Export ra bản sao lưu FitFlow đúng định dạng; import từ chối JSON hỏng và file không phải FitFlow, dữ liệu không đổi.

**11. Buổi tập** (`workout_test`)
- Tập Full Body Foundation: ghi một set (`1 of N sets`), cấp quyền thông báo cho đồng hồ nghỉ, kết thúc buổi.
- Server nhận buổi tập với `completedSets = 1`; buổi đứng đầu History, chi tiết hiện đúng ngày giờ và "Sets completed 1".
- Xoá buổi tập khỏi History, server cũng xoá.

## Lỗi đã sửa (trong code test)

Không lỗi nào nằm trong app; cả ba nằm ở cách test tìm và kiểm tra widget.

### 1. App treo khi kiểm tra bữa ăn (ANR)

- **Hiện tượng:** test sửa bữa ăn và test Sync đứng im rồi bị Android kill sau 60 giây (`MainActivity is not responding`).
- **Nguyên nhân:** finder `loggedMeal(...).containing('300 kcal')` lồng 4 tầng `containing`. Flutter tính lại finder bên trong cho từng ứng viên, nên mỗi tầng nhân thời gian với độ sâu cây widget. Flutter 3.47 chạy UI chung luồng chính của Android, nên treo lâu thành ANR.
- **Đo trên `NutritionPage` thật** (widget test, 1.435 element):

  | Finder | Thời gian |
  |---|---|
  | Cũ, 3 tầng `containing` | 568 ms |
  | Cũ, 4 tầng `containing` | 213 s |
  | Mới (`enclosing` + `.$`) | 0–3 ms |

- **Cách sửa:** thêm helper `enclosing<T>()` trong `patrol_test/support/e2e.dart` — lấy widget `T` gần nhất bao quanh một widget, rồi kiểm tra nội dung bằng `.$(...)`. `loggedMeal`, chân form bữa ăn và tổng ngày dùng helper này. Helper trả về rỗng khi không có gì khớp (khác `find.ancestor(…).first`, vốn ném lỗi), nên `findsNothing` và `waitUntilGone` vẫn dùng được.
- Cách mới cũng chỉ lấy đúng `Row` gần nhất, nên hết lỗi "khớp 2 `Row`" ở chân form bữa ăn hai món.

### 2. Test theme luôn đọc ra theme sáng

- **Nguyên nhân:** app dùng `MaterialApp`/`Theme` của package `material_ui`, còn test import `Theme` từ `package:flutter/material.dart` — hai class khác nhau. `Theme.of` của test không thấy theme của app nên trả về theme mặc định (sáng).
- **Cách sửa:** `settings_test.dart` import `Theme` từ `material_ui`.

### 3. Test form check không thấy camera preview

- **Nguyên nhân:** camera mở bình thường, nhưng lớp vẽ khung xương (`PoseOverlay`, một `CustomPaint`) phủ lên preview và nhận hit-test (mặc định của `CustomPainter`), nên `waitUntilVisible()` không bao giờ đạt.
- **Cách sửa:** `form_check_test.dart` chờ `waitUntilExists()` — preview chỉ được dựng khi camera đã khởi tạo xong.

## Dữ liệu test

- Mọi dữ liệu test tạo ra có tên riêng (`E2E soup 885401`, `E2E remote dish 189959`…), test chỉ đụng dữ liệu của mình.
- Test xoá dữ liệu khi kết thúc, kể cả khi lỗi (qua API). Test đổi onboarding, goal hoặc lịch tuần trả lại bản gốc khi kết thúc.
- Kiểm tra MongoDB sau khi chạy: không còn tài liệu `E2E` nào ở mọi tài khoản; onboarding, goal và lịch tuần của tài khoản thử nghiệm giống trước khi chạy.

## Cách chạy lại

Chuẩn bị:

1. API đang chạy và `API_BASE_URL` trong `.env` trỏ tới nó (xem README, mục **Backend API**).
2. Điện thoại đã kết nối: `adb devices` thấy thiết bị.
3. Đã cài Patrol CLI: `flutter pub global activate patrol_cli`, `~/.pub-cache/bin` có trong `PATH`.

```sh
# Toàn bộ
patrol test --device <adb-id> --dart-define=E2E_GOOGLE_ACCOUNT=you@gmail.com

# Một hoặc vài file
patrol test --device <adb-id> --dart-define=E2E_GOOGLE_ACCOUNT=you@gmail.com \
  -t patrol_test/nutrition_test.dart -t patrol_test/settings_test.dart
```

Lưu ý trên máy Xiaomi (HyperOS/MIUI):

- Mỗi lần chạy cài 4 APK (orchestrator, test services, app, test). MIUI hỏi **Install** cho từng APK và tự từ chối sau ~10 giây. Bật **Developer options → Install via USB** để khỏi phải bấm.
- Máy có nhiều tài khoản Google thì truyền `E2E_GOOGLE_ACCOUNT`; không truyền thì test chọn tài khoản đầu tiên.
- Trong lúc test form check chạy, để camera trước không thấy người, nếu không nó có thể đếm một rep.
- Nên để bộ test chạy hết. Nếu dừng giữa `planning_test` hoặc `settings_test`, bước trả lại onboarding / lịch tuần không chạy — mở app kiểm tra lại hai mục này.
