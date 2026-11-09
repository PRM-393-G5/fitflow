#!/bin/bash
# ====================================================================
# SCRIPT CHẠY TEST E2E SIÊU TỐC - TỪNG KỊCH BẢN ĐỘC LẬP (100% STABLE)
# Kết quả ghi ra test-reports/e2e-<thời gian>_<kịch bản>.md, log của
# từng kịch bản nằm trong thư mục cùng tên bên cạnh.
# ====================================================================
export PATH="$PATH:$HOME/.pub-cache/bin"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DEVICE_ID=$(adb devices | grep -v "List" | grep "device" | head -n 1 | awk '{print $1}')

if [ -z "$DEVICE_ID" ]; then
    echo "[!] LỖI: Chưa kết nối điện thoại qua ADB!"
    echo "    -> Vui lòng kiểm tra lại cáp hoặc kết nối wireless adb."
    exit 1
fi

# Danh sách 11 kịch bản test chi tiết (mỗi kịch bản chạy độc lập để tránh crash Patrol)
ALL_TESTS=(
    "auth:PatrolGeneratedTests_auth_test#test_signs_in_with_Google_and_signs_out:Đăng nhập Google & Xác thực Profile"
    "workout:PatrolGeneratedTests_workout_test#test_logs_a_workout_syncs_it_and_deletes_it_from_history:Tập luyện, Ghi log & Đồng bộ Lịch sử"
    "nutrition:PatrolGeneratedTests_nutrition_test#test_logs_a_two_dish_meal_with_macros_the_day_totals_follow:Dinh dưỡng: Ghi nhận 2 món ăn & Macro"
    "nutrition_edit:PatrolGeneratedTests_nutrition_test#test_edits_a_logged_meal_portion_slot_and_logs_it_again_from_recent_foods:Dinh dưỡng: Sửa khẩu phần & Đổi bữa"
    "body:PatrolGeneratedTests_body_metrics_test#test_logs_today_s_weight_syncs_it_and_deletes_it:Ghi nhận Cân nặng & Chỉ số cơ thể"
    "onboarding:PatrolGeneratedTests_planning_test#test_a_new_account_answers_onboarding_and_Home_follows_its_goal:Onboarding & Khảo sát mục tiêu mới"
    "schedule:PatrolGeneratedTests_planning_test#test_plans_the_week_a_plan_today_rest_tomorrow_then_rest_today:Lên lịch tập các ngày trong tuần"
    "settings_theme:PatrolGeneratedTests_settings_test#test_changes_goal_level_units_and_theme_from_Profile:Cài đặt: Đổi mục tiêu, Đơn vị & Theme"
    "settings_reminder:PatrolGeneratedTests_settings_test#test_schedules_weekly_reminders_on_the_chosen_days:Cài đặt: Hẹn giờ nhắc nhở tập luyện"
    "settings_sync:PatrolGeneratedTests_settings_test#test_Sync_brings_in_a_meal_logged_elsewhere_export_and_import:Cài đặt: Đồng bộ đám mây & Xuất/Nhập file"
    "form:PatrolGeneratedTests_form_check_test#test_opens_the_camera_for_an_AI_form_check:AI Form Check qua Camera"
)

TARGET_ARG="${1:-all}"
SELECTED_TESTS=()

if [ "$TARGET_ARG" == "all" ] || [ "$TARGET_ARG" == "full" ]; then
    SELECTED_TESTS=("${ALL_TESTS[@]}")
else
    for item in "${ALL_TESTS[@]}"; do
        KEY=$(echo "$item" | cut -d: -f1)
        if [ "$KEY" == "$TARGET_ARG" ]; then
            SELECTED_TESTS=("$item")
            break
        fi
    done
    if [ ${#SELECTED_TESTS[@]} -eq 0 ]; then
        echo "[!] Không tìm thấy bài test: $TARGET_ARG"
        echo "    Các từ khóa: all, auth, workout, nutrition, nutrition_edit, body, onboarding, schedule, settings_theme, settings_reminder, settings_sync, form"
        exit 1
    fi
fi

TOTAL=${#SELECTED_TESTS[@]}

# Báo cáo Markdown + log "am instrument" của từng kịch bản
RUN_START=$(date +%s)
RUN_START_TEXT=$(date '+%Y-%m-%d %H:%M:%S')
REPORT_DIR="$ROOT_DIR/test-reports"
REPORT_NAME="e2e-$(date +%Y-%m-%d_%H%M%S)_$TARGET_ARG"
REPORT_FILE="$REPORT_DIR/$REPORT_NAME.md"
LOG_DIR="$REPORT_DIR/$REPORT_NAME"
mkdir -p "$LOG_DIR"

DEVICE_MODEL=$(adb -s "$DEVICE_ID" shell getprop ro.product.model 2>/dev/null | tr -d '\r')
ANDROID_VERSION=$(adb -s "$DEVICE_ID" shell getprop ro.build.version.release 2>/dev/null | tr -d '\r')
APK_INSTALLED=$(adb -s "$DEVICE_ID" shell dumpsys package com.zcode9211.prm 2>/dev/null | grep -m1 "lastUpdateTime" | cut -d= -f2 | tr -d '\r')
if GIT_COMMIT=$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null); then
    GIT_REF="\`$(git -C "$ROOT_DIR" rev-parse --abbrev-ref HEAD)\` @ \`$GIT_COMMIT\`"
    if [ -n "$(git -C "$ROOT_DIR" status --porcelain --untracked-files=no)" ]; then
        GIT_REF="$GIT_REF (có thay đổi chưa commit)"
    fi
else
    GIT_REF="không rõ"
fi

RESULT_ROWS=()
FAIL_HEADS=()
FAIL_METHODS=()
FAIL_LOGS=()

fmt_duration() {
    printf '%dm%02ds' $(($1 / 60)) $(($1 % 60))
}

# Stack trace của test lỗi: khối "stack=" trong output của "am instrument -r"
extract_stack() {
    awk 'grab && /^INSTRUMENTATION_/ { exit }
         sub(/^INSTRUMENTATION_STATUS: stack=/, "") { grab = 1 }
         grab' "$1"
}

# Một dòng lý do lỗi: dòng đầu của stack trace, hoặc thông báo crash, hoặc dòng cuối của log
fail_reason() {
    local reason
    reason=$(extract_stack "$1" | head -n 1)
    [ -z "$reason" ] && reason=$(grep -m1 "shortMsg=" "$1" | sed 's/.*shortMsg=//')
    [ -z "$reason" ] && reason=$(grep -v '^[[:space:]]*$' "$1" | tail -n 1)
    echo "$reason"
}

# Ghi (lại) toàn bộ báo cáo; $1 là trạng thái của lượt chạy
write_report() {
    local ran=$((PASSED + FAILED))
    local i log stack
    {
        echo "# FitFlow — Kết quả kiểm thử E2E (Patrol)"
        echo ""
        echo "| | |"
        echo "|---|---|"
        echo "| Bắt đầu | $RUN_START_TEXT |"
        echo "| Cập nhật lúc | $(date '+%Y-%m-%d %H:%M:%S') · $1 |"
        echo "| Thiết bị | $DEVICE_MODEL · Android $ANDROID_VERSION · \`$DEVICE_ID\` |"
        echo "| APK trên điện thoại | cài lúc ${APK_INSTALLED:-không rõ} |"
        echo "| Code trên máy tính | $GIT_REF |"
        echo "| Tài khoản | tu719719@gmail.com |"
        echo "| Kết quả | **$PASSED PASS ✅ · $FAILED FAIL ❌** — đã chạy $ran/$TOTAL kịch bản trong $(fmt_duration $(($(date +%s) - RUN_START))) |"
        echo ""
        echo "## Từng kịch bản"
        echo ""
        echo "| # | Kịch bản | File test | Kết quả | Thời gian | Log |"
        echo "|---|---|---|---|---|---|"
        for row in "${RESULT_ROWS[@]}"; do
            echo "$row"
        done
        if [ ${#FAIL_LOGS[@]} -gt 0 ]; then
            echo ""
            echo "## Chi tiết lỗi"
            for i in "${!FAIL_LOGS[@]}"; do
                log="${FAIL_LOGS[$i]}"
                echo ""
                echo "### ${FAIL_HEADS[$i]}"
                echo ""
                echo "\`${FAIL_METHODS[$i]}\` · log đầy đủ: [$(basename "$log")]($REPORT_NAME/$(basename "$log"))"
                echo ""
                echo '```text'
                stack=$(extract_stack "$log")
                if [ -n "$stack" ]; then
                    echo "$stack"
                else
                    tail -n 40 "$log"
                fi
                echo '```'
            done
        fi
    } > "$REPORT_FILE"
}

echo "=========================================================="
echo "    [FITFLOW] E2E AUTOMATION TEST SUITE (0s BUILD)        "
echo "=========================================================="
echo "[+] Thiết bị: $DEVICE_ID"
echo "[+] Tài khoản mục tiêu: tu719719@gmail.com"
echo "[+] Số lượng kịch bản: $TOTAL kịch bản"
echo "[+] Báo cáo: test-reports/$REPORT_NAME.md"
echo "[+] Đang kích hoạt màn hình luôn sáng & ADB reverse port 3001..."
adb -s "$DEVICE_ID" shell svc power stayon true 2>/dev/null
adb -s "$DEVICE_ID" shell settings put system screen_off_timeout 1800000 2>/dev/null
adb -s "$DEVICE_ID" shell input keyevent 224 2>/dev/null
adb -s "$DEVICE_ID" shell wm dismiss-keyguard 2>/dev/null
adb -s "$DEVICE_ID" reverse tcp:3001 tcp:3001 2>/dev/null
echo "=========================================================="
echo ""

PASSED=0
FAILED=0
INDEX=1

# Ctrl+C giữa chừng: vẫn giữ báo cáo của các kịch bản đã chạy xong
trap 'echo ""; echo "[!] Đã dừng giữa chừng."; write_report "dừng giữa chừng (Ctrl+C)"; echo "[+] Báo cáo: $REPORT_FILE"; exit 130' INT TERM
write_report "đang chạy"

for item in "${SELECTED_TESTS[@]}"; do
    KEY=$(echo "$item" | cut -d: -f1)
    TARGET_METHOD=$(echo "$item" | cut -d: -f2)
    TITLE=$(echo "$item" | cut -d: -f3-)
    TEST_FILE="${TARGET_METHOD%%#*}"
    TEST_FILE="${TEST_FILE#PatrolGeneratedTests_}.dart"
    LOG_FILE="$LOG_DIR/$KEY.log"

    echo "[$INDEX/$TOTAL] Đang chạy: $TITLE..."

    # Đảm bảo màn hình sáng & mở khóa
    adb -s "$DEVICE_ID" shell input keyevent 224 2>/dev/null
    adb -s "$DEVICE_ID" shell wm dismiss-keyguard 2>/dev/null
    adb -s "$DEVICE_ID" reverse tcp:3001 tcp:3001 2>/dev/null

    # Xóa dữ liệu app trước mỗi kịch bản: test nào cũng bắt đầu từ LoginPage
    # (khi chạy qua Gradle, Orchestrator làm việc này bằng clearPackageData)
    adb -s "$DEVICE_ID" shell pm clear com.zcode9211.prm >/dev/null 2>&1
    sleep 1

    # 2. Chạy đúng 1 test method cụ thể
    START_TIME=$(date +%s)
    OUTPUT=$(adb -s "$DEVICE_ID" shell am instrument -w -r -e class "com.zcode9211.prm.$TARGET_METHOD" com.zcode9211.prm.test/pl.leancode.patrol.PatrolJUnitRunner 2>&1)
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    printf '%s\n' "$OUTPUT" | tr -d '\r' > "$LOG_FILE"

    # 3. Đánh giá kết quả
    if grep -q "OK (1 test)" "$LOG_FILE"; then
        echo "    👉 KẾT QUẢ: PASS ✅ (${DURATION}s)"
        RESULT_ROWS+=("| $INDEX | $TITLE | \`$TEST_FILE\` | ✅ PASS | ${DURATION}s | [$KEY.log]($REPORT_NAME/$KEY.log) |")
        ((PASSED++))
    else
        echo "    👉 KẾT QUẢ: FAIL ❌ (${DURATION}s)"
        FAIL_REASON=$(fail_reason "$LOG_FILE")
        if [ -n "$FAIL_REASON" ]; then
            echo "       Chi tiết: $FAIL_REASON"
        fi
        RESULT_ROWS+=("| $INDEX | $TITLE | \`$TEST_FILE\` | ❌ FAIL | ${DURATION}s | [$KEY.log]($REPORT_NAME/$KEY.log) |")
        FAIL_HEADS+=("$INDEX. $TITLE")
        FAIL_METHODS+=("$TARGET_METHOD")
        FAIL_LOGS+=("$LOG_FILE")
        ((FAILED++))
    fi
    write_report "đang chạy"
    echo ""
    ((INDEX++))
done

write_report "hoàn thành"

echo "=========================================================="
echo "                   TỔNG KẾT KIỂM THỬ                      "
echo "=========================================================="
echo "  Tổng số bài test : $TOTAL"
echo "  Thành công (PASS): $PASSED ✅"
echo "  Thất bại   (FAIL): $FAILED ❌"
echo "  Báo cáo          : $REPORT_FILE"
echo "=========================================================="
