@echo off
title CareAI - Galaxy Watch Emulator
echo ===================================================================
echo       CAREAI - KHOI DONG THIET BI DONG HO WEAR OS AO
echo ===================================================================
echo.
echo Dang tim kiem trinh gia lap Android SDK tren he thong...

set "EMU_PATH="
set "EMU_DIR="

if exist "D:\Android\Sdk\emulator\emulator.exe" (
    set "EMU_PATH=D:\Android\Sdk\emulator\emulator.exe"
    set "EMU_DIR=D:\Android\Sdk\emulator"
) else if defined ANDROID_HOME (
    if exist "%ANDROID_HOME%\emulator\emulator.exe" (
        set "EMU_PATH=%ANDROID_HOME%\emulator\emulator.exe"
        set "EMU_DIR=%ANDROID_HOME%\emulator"
    )
) else if exist "%LOCALAPPDATA%\Android\Sdk\emulator\emulator.exe" (
    set "EMU_PATH=%LOCALAPPDATA%\Android\Sdk\emulator\emulator.exe"
    set "EMU_DIR=%LOCALAPPDATA%\Android\Sdk\emulator"
)

if not defined EMU_PATH (
    echo [LOI] Khong tim thay Android SDK Emulator tren he thong!
    echo Vui long kiem tra lai duong dan D:\Android\Sdk hoac cai dat Android Emulator.
    pause
    exit /b 1
)

echo Dang khoi dong thiet bi ao Galaxy Watch: %EMU_PATH%
cd /d "%EMU_DIR%"
start "" "%EMU_PATH%" -avd Galaxy_Watch_Emulator -no-snapshot-load -no-skin
echo.
echo [OK] Da kich hoat khoi dong thanh cong!
echo Cua so dong ho Wear OS se hien thi ngay tren man hinh cua ban.
timeout /t 3
