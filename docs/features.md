# FitFlow — Danh sách tính năng

Trạng thái: ✅ đã có · 🟡 có UI, chưa hoàn chỉnh · 📋 kế hoạch (trong phạm vi capstone)

## 1. Trải nghiệm tập luyện (Workout Experience)

| Tính năng | Mô tả | Trạng thái |
|---|---|---|
| Onboarding | Lần đầu mở app: chọn mục tiêu (tăng cơ / giảm mỡ / vận động) + trình độ → cá nhân hoá gợi ý workout và filter mặc định | ✅ |
| Thư viện workout | Browse, search, filter theo category/level; xem chi tiết exercise, sets, reps, rest | ✅ |
| Màn tập (active workout) | Tick từng set, nhập reps/kg thực tế từng set (prefill từ plan), đếm ngược rest, xác nhận kết thúc; session hoàn thành tự lưu | ✅ |
| Today's workout | Home hiển thị workout theo lịch tuần hoặc theo goal onboarding | ✅ |
| Workout builder | Tạo plan riêng: tên, category, level, danh sách exercise động (sets/reps/rest/tạ), tự estimate thời lượng | ✅ |
| AI workout generator | Nhập mô tả bằng text ("30 phút, tập chân, không dụng cụ") → GPT-4o-mini tạo plan hoàn chỉnh (strict JSON schema + sanitize) → preview → lưu thành custom plan, sync cloud như plan tay | ✅ (cần `OPENAI_API_KEY` trong `.env` hoặc `--dart-define`) |
| Nutrition (AI meal plan) | Tab Nutrition: target calo từ TDEE + goal (Strength +300 / Cardio −400 / Mobility ±0), macros P/C/F; GPT-4o-mini gợi ý thực đơn ngày theo target + preferences (3 bữa / 3+phụ), cache theo ngày | ✅ (cần `OPENAI_API_KEY` trong `.env` hoặc `--dart-define`) |
| Weekly schedule | Gán plan cho từng thứ trong tuần | ✅ |
| Session detail | Tap vào lịch sử → duration, sets, volume, breakdown từng set (reps × kg) theo exercise | ✅ |

## 2. AI Form Check (kiểm tra tư thế on-device)

| Tính năng | Mô tả | Trạng thái |
|---|---|---|
| Pose detection | ML Kit pose + skeleton overlay trên camera preview, xử lý hoàn toàn trên máy | ✅ |
| Squat | Đếm rep qua góc gối/hông, cảnh báo knee tracking | ✅ |
| Push-up | Đếm rep qua góc khuỷu tay, phát hiện hông xệ/pike | ✅ |
| Plank | Đo thời gian giữ đúng form (hold seconds), kiểm tra độ thẳng thân | ✅ |
| Chấm điểm + cues | Form score 0–100, gợi ý sửa tư thế realtime; pause, đổi camera | ✅ |
| Lưu kết quả | Kết quả form check lưu vào session history | ✅ |
| Thêm bài tập | Lunge, pull-up, overhead press (analyzer mới, tái dùng pipeline) | 📋 |

## 3. Theo dõi tiến độ (Progress & Motivation)

| Tính năng | Mô tả | Trạng thái |
|---|---|---|
| Dashboard | Tổng sessions, phút tập, volume | ✅ |
| Activity heatmap | 12 tuần kiểu GitHub | ✅ |
| Weekly chart | Bar chart phút tập theo thứ | ✅ |
| Personal records | Streak dài nhất, session volume cao nhất, session dài nhất | ✅ |
| Achievements | 12 badges theo streak/volume/số buổi tập | ✅ |
| Share summary | Card tổng kết + copy text | 🟡 (chưa share ảnh — cần `share_plus`) |
| So sánh tuần/tháng | Delta % so với kỳ trước | 📋 |

## 4. Chỉ số cơ thể (Body Metrics)

| Tính năng | Mô tả | Trạng thái |
|---|---|---|
| Log cân nặng | Nhập theo ngày, tự đổi kg/lb, xoá entry | ✅ |
| Trend chart | Line chart cân nặng theo thời gian | ✅ |
| BMI / BMR / TDEE | Tính từ body profile (chiều cao, tuổi, giới tính, mức vận động) — Mifflin-St Jeor | ✅ |
| Số đo khác | Vòng eo, % body fat, ảnh tiến trình | 📋 |

## 5. Cài đặt & nhắc nhở

| Tính năng | Mô tả | Trạng thái |
|---|---|---|
| Theme | Light / dark / system | ✅ |
| Đơn vị | Metric / imperial | ✅ |
| Reminders | Chọn giờ + thứ muốn tập, bắn notification thật qua `flutter_local_notifications` | ✅ |

## 6. Dữ liệu & đồng bộ (Local-first + Cloud Sync)

| Tính năng | Mô tả | Trạng thái |
|---|---|---|
| Local-first | Mọi dữ liệu (plans, sessions, cân nặng, profile, lịch, onboarding) lưu local — app dùng được hoàn toàn offline, không bắt account | ✅ |
| Export JSON | Xuất toàn bộ dữ liệu, copy/share | ✅ |
| Sign-in | Đăng nhập Google (Firebase Auth) — mở khoá cloud sync | ✅ |
| Cloud sync | Backup + đồng bộ sessions/custom plans/metrics/schedule/onboarding qua Cloud Firestore (`users/{uid}`); merge by id cho sessions & plans, last-write-wins cho meta | ✅ |
| Multi-device | Nhiều thiết bị cùng account thấy cùng dữ liệu (sync khi mở app + mỗi lần ghi) | ✅ |

## Ưu tiên triển khai tiếp

1. **Share ảnh** summary card — cần `share_plus`
2. Bài tập form check mới / số đo cơ thể — nếu dư thời gian
3. Nhật ký calo đơn giản (log kcal/ngày vs TDEE) — nếu muốn thêm dinh dưỡng
