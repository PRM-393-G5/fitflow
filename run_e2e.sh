#!/bin/bash
# Script chạy E2E Test (Patrol) 1-Click cho Demo
export PATH="$PATH:$HOME/.pub-cache/bin"

echo "=========================================================="
echo "          FITFLOW - E2E AUTOMATED TEST (PATROL)           "
echo "=========================================================="
echo ""

# 1. Kiểm tra thiết bị Android (Điện thoại thật hoặc Máy ảo)
DEVICE_COUNT=$(adb devices | grep -v "List" | grep "device" | wc -l)

if [ "$DEVICE_COUNT" -eq 0 ]; then
    echo "[!] KHÔNG TÌM THẤY THIẾT BỊ ANDROID NÀO ĐƯỢC KẾT NỐI!"
    echo "    -> Vui lòng cắm điện thoại Android (đã bật USB Debugging)"
    echo "    -> HOẶC bật 1 Máy ảo Android (Android Emulator) lên trước khi chạy."
    echo ""
    exit 1
fi

DEVICE_NAME=$(adb devices | grep -v "List" | grep "device" | head -n 1 | awk '{print $1}')
echo "[+] Đã phát hiện thiết bị: $DEVICE_NAME"
echo ""

# 2. Nhắc nhở Backend
echo "[*] Lưu ý: Đảm bảo Backend API (fitflow-api) đang chạy ở máy tính."
echo "[*] Đang khởi chạy E2E Test (Auth & Profile Flow)..."
echo ""

# 3. Chạy test
patrol test -t patrol_test/auth_test.dart

echo ""
echo "=========================================================="
echo "                E2E TEST HOÀN THÀNH                       "
echo "=========================================================="
