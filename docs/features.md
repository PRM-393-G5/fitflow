# FitFlow — Danh sách tính năng

Trạng thái: ✅ đã có · 🟡 có UI, chưa hoàn chỉnh · 📋 kế hoạch (trong phạm vi capstone)

## 1. Trải nghiệm tập luyện (Workout Experience)

| Tính năng | Mô tả | Trạng thái |
|---|---|---|
| Onboarding | Lần đầu mở app: chọn mục tiêu (tăng cơ / giảm mỡ / vận động) + trình độ → cá nhân hoá gợi ý workout và filter mặc định | ✅ |
| Thư viện workout | Template có sẵn trong app (fallback khi offline/chưa có API) + template từ FitFlow API (`GET /api/templates`); search theo tên/bài/nhóm cơ/level, filter category + level; chi tiết có "last performed", thêm vào lịch | ✅ |
| Màn tập (active workout) | Tick từng set, nhập reps + tạ theo đơn vị người dùng (kg/lb, chấp nhận dấu phẩy), undo set, đếm ngược rest/hold theo mốc thời gian (đúng cả khi app ở nền) + rung/âm báo, preview bài kế tiếp; không lưu buổi 0 set; tạ vượt xa mức nặng nhất từng log (> 1.25× và > +10 kg) phải xác nhận trước khi log (chặn gõ nhầm 600 thay 60) | ✅ |
| Gợi ý tăng tạ (progressive overload) | Mỗi bài trong màn tập hiện "Last time" + gợi ý hôm nay, suy ra từ lịch sử. Bài có tạ: double progression + quy tắc 2-for-2 (ACSM/NSCA) — khoảng rep [target, target+2], đạt đỉnh khoảng 2 buổi liền thì tăng 2.5% (thân trên) / 5% (thân dưới) làm tròn theo bước tạ thật (kg: 1 / 2.5; lb: 2.5 / 5); trượt rep 3 buổi liền cùng mức tạ → giảm 10%; nghỉ > 4 tuần → nhẹ hơn 10% (> 12 tuần: 20%); đổi số rep mục tiêu → quy đổi tạ theo Epley (100 kg × 5 → 92.5 kg × 8); mức tạ làm việc = mức nặng nhất của buổi (drop set/khởi động không kéo gợi ý xuống). Không tạ: +1 rep tới 20; giữ: +5 s tới 60 s, rồi gợi ý biến thể khó hơn. Bài không tạ trong plan Mobility/Cardio và bài nhóm Cardio giữ nguyên như lần trước; bài có tạ luôn được gợi ý tăng | ✅ |
| Today's workout | Home hiển thị workout theo lịch tuần hoặc theo goal onboarding | ✅ |
| Workout builder | Tạo / **sửa / xoá** plan riêng: tên, category, level, exercise động (reps hoặc giây, nhóm cơ, rest, tạ), validate từng field, tự estimate thời lượng | ✅ |
| AI workout generator | Nhập mô tả bằng text ("30 phút, tập chân, không dụng cụ") → gpt-6-luna tạo plan hoàn chỉnh (strict JSON schema + sanitize) → preview → lưu thành custom plan, sync cloud như plan tay | ✅ (cần `OPENAI_API_KEY` trong `.env` hoặc `--dart-define`) |
| Nutrition (AI meal plan + food log) | Tab Nutrition: target calo từ TDEE + goal (tăng cơ +10% tối đa 300 kcal / giảm mỡ −15% tối đa 500 kcal / còn lại giữ cân) có chốt an toàn: BMI < 18.5 không cắt calo, dưới 18 tuổi giữ ở mức duy trì, sàn 1.500 kcal (nam) / 1.200 kcal (nữ), nếu mức duy trì đã dưới sàn thì không thâm hụt; protein theo mức thực áp dụng: 1.8 g/kg khi thâm hụt, 1.6 khi dư, 1.2 khi duy trì (người lớn thừa cân tính trên cân nặng ở BMI 25); tuổi tự tăng theo năm kể từ lúc nhập; card hiện đã ăn / mục tiêu cho calo và P/C/F, kèm lý do khi mục tiêu bị giữ lại và lưu ý "không phải tư vấn y tế"; gpt-6-luna gợi ý thực đơn ngày (cache theo ngày); chụp/chọn ảnh → luna vision đoán món + kcal/macro; log bữa ăn (ảnh, nhập tay kèm macro, hoặc 1 chạm từ thực đơn gợi ý), sửa khẩu phần, lịch sử 30 ngày, tổng P/C/F đã ăn vs target; đổi goal ngay trên tab; đồng bộ cloud khi đăng nhập | ✅ (cần `OPENAI_API_KEY` trong `.env` hoặc `--dart-define`) |
| Weekly schedule | Gán plan / ngày nghỉ / bỏ trống cho từng thứ; Home hiện "Rest day" / "Done today" | ✅ |
| Session detail | Tap vào lịch sử → duration, sets, volume, breakdown từng set theo exercise; **sửa reps/tạ từng set** (sửa gõ nhầm; PR và gợi ý tự tính lại); **xoá session** | ✅ |

## 2. AI Form Check (kiểm tra tư thế on-device)

| Tính năng | Mô tả | Trạng thái |
|---|---|---|
| Pose detection | ML Kit pose + skeleton overlay trên camera preview, xử lý hoàn toàn trên máy | ✅ |
| Squat | Đếm rep qua góc gối/hông, cảnh báo knee tracking; per-rep telemetry (độ sâu, tempo ↓↑, lỗi: shallow/valgus/lean/heels/asymmetry/fast) + review sheet sau set + AI coach nhận xét (gpt-6-luna) | ✅ (AI review cần `OPENAI_API_KEY`) |
| Push-up | Đếm rep qua góc khuỷu tay chỉ khi thân nằm ngang, phát hiện hông xệ/pike | ✅ |
| Plank | Đo thời gian giữ đúng form (hold seconds), độ lệch hông chuẩn hoá theo chiều dài thân, phải chống tay/khuỷu (nằm sấp không tính) | ✅ |
| Chấm điểm + cues | Form score 0–100, gợi ý sửa tư thế realtime; pause, đổi camera | ✅ |
| Lưu kết quả | Kết quả form check lưu vào session history (hiện trong lịch sử, không tính là buổi tập: không cộng vào số buổi, phút tập, mục tiêu tuần, streak, huy hiệu) | ✅ |
| Thêm bài tập | Lunge, pull-up, overhead press (analyzer mới, tái dùng pipeline) | 📋 |

## 3. Theo dõi tiến độ (Progress & Motivation)

| Tính năng | Mô tả | Trạng thái |
|---|---|---|
| Dashboard | Tổng sessions, phút tập, volume (không tính form check) | ✅ |
| Activity heatmap | 12 tuần kiểu GitHub | ✅ |
| Weekly chart | Bar chart phút tập theo thứ | ✅ |
| Streak theo tuần | Số tuần liên tiếp đạt mục tiêu tuần (mặc định 3 buổi, tuần bắt đầu thứ 2), giống Hevy; ngày nghỉ không làm đứt chuỗi, tuần đang dở chưa đạt không làm đứt chuỗi | ✅ |
| Personal records | Session volume/dài nhất; PR từng bài — bài có tạ: tạ nặng nhất + 1RM ước tính (Epley, số rep tính tối đa 10) + set tạo ra 1RM đó; thêm rep ở một mức tạ đã từng tập (hoặc nặng hơn) cũng là PR; bài không tạ: nhiều rep nhất; bài giữ: hold lâu nhất. Tạ so với dung sai 0.05 kg nên đổi kg/lb không tạo PR giả; danh sách xếp theo PR gần nhất | ✅ |
| Achievements | 12 badges theo số buổi tập/phút tập/volume/streak tuần (2, 4, 12 tuần liên tiếp đạt weekly goal), hiện tiến độ badge chưa mở | ✅ |
| Share summary | Card tổng kết → share ảnh PNG (`share_plus`), fallback text/copy | ✅ |
| So sánh tuần/tháng | Delta % so với kỳ trước | 📋 |

## 4. Chỉ số cơ thể (Body Metrics)

| Tính năng | Mô tả | Trạng thái |
|---|---|---|
| Log cân nặng | Một entry/ngày, kg/lb, validate, không cho ngày tương lai, xoá có xác nhận | ✅ |
| Trend chart | Line chart theo trục thời gian, min/max, lọc 30d/90d/all | ✅ |
| BMI / BMR / TDEE | Tính từ body profile (chiều cao, tuổi, giới tính, mức vận động) — Mifflin-St Jeor | ✅ |
| Số đo khác | Vòng eo, % body fat, ảnh tiến trình | 📋 |

## 5. Cài đặt & nhắc nhở

| Tính năng | Mô tả | Trạng thái |
|---|---|---|
| Theme | Light / dark / system | ✅ |
| Đơn vị | Metric / imperial | ✅ |
| Reminders | Chọn giờ + thứ (hoặc khớp lịch tuần), notification qua `flutter_local_notifications`; receiver + boot receiver trong manifest, reschedule mỗi lần mở app, an toàn DST | ✅ |

## 6. Dữ liệu & đồng bộ (Local-first + Cloud Sync)

| Tính năng | Mô tả | Trạng thái |
|---|---|---|
| Local-first | Mọi dữ liệu lưu local, đọc/ghi không chờ mạng; **không bắt buộc đăng nhập** ("Continue without an account"); không kết nối được API → vẫn chạy local-only; iOS chưa cấu hình Google Sign-In → chạy local-only | ✅ |
| Export / Import JSON | Xuất backup (plans riêng, sessions, cân nặng, profile, lịch, goal, settings) ra file/copy; import merge theo id | ✅ |
| Sign-in | Đăng nhập Google tuỳ chọn — mở khoá cloud sync; đăng xuất chờ dữ liệu sync xong (cảnh báo nếu còn thay đổi chưa lên cloud) rồi xoá dữ liệu trên máy; **xoá tài khoản** + dữ liệu cloud | ✅ |
| Cloud sync | FitFlow API (`fitflow-api`, NestJS + MongoDB): sessions, custom plans, cân nặng merge theo id với tombstone khi xoá; profile/lịch/onboarding last-write-wins; ghi offline qua outbox, gửi lại khi có mạng; dữ liệu khách được gộp vào tài khoản khi đăng nhập; đổi tài khoản xoá sạch dữ liệu người trước | ✅ |
| Multi-device | Nhiều thiết bị cùng account thấy cùng dữ liệu (sync khi mở app + mỗi lần ghi) | ✅ |

## Ưu tiên triển khai tiếp

1. Chuyển OpenAI key ra backend (`fitflow-api`) — hiện key vẫn nằm trong APK
2. Đưa `fitflow-api` lên server HTTPS để bản release dùng được cloud sync
3. Cấu hình Google Sign-In cho iOS (`GIDClientID` + reversed client ID URL scheme trong `ios/Runner/Info.plist`) — iOS hiện chạy local-only
3. Bài tập form check mới / số đo cơ thể — nếu dư thời gian
