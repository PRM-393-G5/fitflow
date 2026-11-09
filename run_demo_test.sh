#!/bin/bash
# Script chạy Test tự động 1-Click cho Demo PRM393
echo "=========================================================="
echo "          FITFLOW - AUTOMATED TEST SUITE (DEMO)           "
echo "=========================================================="
echo ""
echo "[*] Đang khởi chạy toàn bộ Test Case (Unit & Widget Tests)..."
echo ""

flutter test --reporter expanded

if [ $? -eq 0 ]; then
    echo ""
    echo "=========================================================="
    echo "  🎉 TẤT CẢ AUTOMATED TESTS ĐÃ PASS THÀNH CÔNG (100%)!    "
    echo "=========================================================="
else
    echo ""
    echo "[!] Có test case bị lỗi, vui lòng kiểm tra lại."
fi
