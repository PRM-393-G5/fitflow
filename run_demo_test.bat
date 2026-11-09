@echo off
chcp 65001 >nul
echo ==========================================================
echo           FITFLOW - AUTOMATED TEST SUITE (DEMO)           
echo ==========================================================
echo.
echo [*] Dang khoi chay toan bo Test Case (Unit & Widget Tests)...
echo.

flutter test --reporter expanded

if %ERRORLEVEL% equ 0 (
    echo.
    echo ==========================================================
    echo   [OK] TAT CA AUTOMATED TESTS DA PASS THANH CONG (100%)!  
    echo ==========================================================
) else (
    echo.
    echo [!] Co test case bi loi, vui long kiem tra lai.
)
pause
