@echo off
setlocal enabledelayedexpansion
title Portal Strike - Asset Verification (CS:S Primary Host)
cls

echo ==============================================================
echo      PORTAL STRIKE: ASSET AND SEARCH PATH VERIFICATION
echo ==============================================================
echo.

set "GAMEINFO_FILE=E:\SteamLibrary\steamapps\common\Counter-Strike Source\cstrike\gameinfo.txt"
set "PORTAL_VPK=D:\Steam\steamapps\common\Portal\portal\portal_pak_dir.vpk"
set "CSS_EXE=E:\SteamLibrary\steamapps\common\Counter-Strike Source\hl.exe"
if not exist "%CSS_EXE%" set "CSS_EXE=E:\SteamLibrary\steamapps\common\Counter-Strike Source\cstrike.exe"

echo [1] Checking CS:S gameinfo.txt configuration...
if not exist "%GAMEINFO_FILE%" (
    echo   [FAIL] Missing gameinfo.txt at: %GAMEINFO_FILE%
) else (
    echo   [PASS] Found CS:S gameinfo.txt at: %GAMEINFO_FILE%
)

echo.
echo [2] Reading mounted SearchPaths from gameinfo.txt...
findstr /i /c:"portal_pak_dir.vpk" /c:"custom/portal_strike" "%GAMEINFO_FILE%"
if !ERRORLEVEL! EQU 0 (
    echo   [PASS] Portal companion VPK and custom mod mounted in gameinfo.txt
) else (
    echo   [WARN] Portal search paths not found in gameinfo.txt
)

echo.
echo [3] Checking Primary Host & Companion executables...
if exist "%CSS_EXE%" (
    echo   [PASS] Found CS:S Host Executable: %CSS_EXE%
) else (
    echo   [FAIL] Missing CS:S Host Executable: %CSS_EXE%
)

if exist "%PORTAL_VPK%" (
    echo   [PASS] Found Portal Companion VPK: %PORTAL_VPK%
) else (
    echo   [FAIL] Missing Portal Companion VPK: %PORTAL_VPK%
)

echo.
echo [4] Running deep asset scanner...
where python >nul 2>&1
if !ERRORLEVEL! EQU 0 (
    python "%~dp0verify_assets.py"
) else (
    echo   [WARN] Python not found on PATH.
)

echo.
echo ==============================================================
echo Verification complete.
echo ==============================================================
pause
