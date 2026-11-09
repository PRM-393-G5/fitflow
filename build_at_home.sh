#!/bin/bash
# ====================================================================
# BƯỚC 1: BUILD TRƯỚC E2E APK Ở NHÀ (TIẾT KIỆM CPU + TÀI KHOẢN CỐ ĐỊNH)
# ====================================================================
export PATH="$PATH:$HOME/.pub-cache/bin"

echo "=========================================================="
echo "    [FITFLOW] PRE-BUILD E2E TEST APK (TIẾT KIỆM CPU)      "
echo "=========================================================="
echo ""
echo "[*] Tài khoản Google mặc định: tu719719@gmail.com"
echo "[*] Giới hạn tài nguyên: 2 luồng CPU (nice -n 19)"
echo ""

# Build với --emit-test-manifest và truyền account cố định
nice -n 19 patrol build android --emit-test-manifest --dart-define=E2E_GOOGLE_ACCOUNT=tu719719@gmail.com

if [ $? -eq 0 ]; then
    echo ""
    echo "=========================================================="
    echo "  🎉 PRE-BUILD THÀNH CÔNG!"
    echo "=========================================================="

    DEVICE_ID=$(adb devices | grep -v "List" | grep "device" | head -n 1 | awk '{print $1}')
    if [ -n "$DEVICE_ID" ]; then
        echo ""
        echo "[*] Đang tự động nạp APK mới vào điện thoại ($DEVICE_ID)..."
        adb -s "$DEVICE_ID" push build/app/outputs/apk/debug/app-debug.apk /data/local/tmp/app.apk
        adb -s "$DEVICE_ID" shell pm install -r -t /data/local/tmp/app.apk
        adb -s "$DEVICE_ID" push build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk /data/local/tmp/test.apk
        adb -s "$DEVICE_ID" shell pm install -r -t /data/local/tmp/test.apk
        echo "[+] Đã nạp thành công vào điện thoại!"
    fi

    echo ""
    echo "=========================================================="
    echo "  SẴN SÀNG! Bây giờ bạn chỉ cần chạy: ./run_e2e_instant.sh"
    echo "=========================================================="
else
    echo ""
    echo "[!] Có lỗi trong quá trình build, vui lòng kiểm tra lại."
fi
