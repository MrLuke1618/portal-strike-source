@echo off
setlocal enabledelayedexpansion
title Portal Strike - Standalone Dynamic Launcher (Creator: MrLuke1618)

:: Default Engine Search Paths (can be updated via GUI Directory Picker [D])
if not defined CSS_BASE_DIR set "CSS_BASE_DIR=E:\SteamLibrary\steamapps\common\Counter-Strike Source"
if not defined PORTAL_BASE_DIR set "PORTAL_BASE_DIR=D:\Steam\steamapps\common\Portal"

:scan_maps
cls
echo ======================================================================
echo        PORTAL STRIKE: TACTICAL PORTAL HYBRID LAUNCHER
echo  Portal Strike - 2026 ^| Creator: MrLuke1618 ^| YouTube: @luke1618gamer
echo  TikTok: @hoangcao2704 ^| Public Distribution: Melty.gg ^& YouTube
echo ======================================================================
echo Current Directories:
echo   CS:S Base:   !CSS_BASE_DIR!
echo   Portal Base: !PORTAL_BASE_DIR!
echo.

set "CSS_MAPS_DIR=!CSS_BASE_DIR!\cstrike\maps"
set "CSS_CUSTOM_DIR=!CSS_BASE_DIR!\cstrike\custom"
set "PORTAL_CUSTOM_MAPS=!PORTAL_BASE_DIR!\portal\custom\portal_strike\maps"
set "LOCAL_PROJ_MAPS=%~dp0portal_strike\maps"
set "LOCAL_MAPS=%~dp0maps"

set MAP_COUNT=0

:: Clear previous scan variables
for /l %%I in (1,1,100) do (
    set "MAP_%%I="
    set "MAP_SRC_%%I="
)

:: 1. Scan Local project maps folder
if exist "%LOCAL_PROJ_MAPS%" (
    for %%F in ("%LOCAL_PROJ_MAPS%\*.bsp") do (
        set "M=%%~nF"
        if not defined SEEN_!M! (
            set "SEEN_!M!=1"
            set /a MAP_COUNT+=1
            set "MAP_!MAP_COUNT!=!M!"
            set "MAP_SRC_!MAP_COUNT!=Custom"
        )
    )
)

:: 2. Scan Local standalone maps folder
if exist "%LOCAL_MAPS%" (
    for %%F in ("%LOCAL_MAPS%\*.bsp") do (
        set "M=%%~nF"
        if not defined SEEN_!M! (
            set "SEEN_!M!=1"
            set /a MAP_COUNT+=1
            set "MAP_!MAP_COUNT!=!M!"
            set "MAP_SRC_!MAP_COUNT!=Custom"
        )
    )
)

:: 3. Scan Portal custom installation folder
if exist "%PORTAL_CUSTOM_MAPS%" (
    for %%F in ("%PORTAL_CUSTOM_MAPS%\*.bsp") do (
        set "M=%%~nF"
        if not defined SEEN_!M! (
            set "SEEN_!M!=1"
            set /a MAP_COUNT+=1
            set "MAP_!MAP_COUNT!=!M!"
            set "MAP_SRC_!MAP_COUNT!=Custom"
        )
    )
)

:: 4. Scan CS:S custom directory subfolders
if exist "%CSS_CUSTOM_DIR%" (
    for /d %%D in ("%CSS_CUSTOM_DIR%\*") do (
        if exist "%%D\maps" (
            for %%F in ("%%D\maps\*.bsp") do (
                set "M=%%~nF"
                if not defined SEEN_!M! (
                    set "SEEN_!M!=1"
                    set /a MAP_COUNT+=1
                    set "MAP_!MAP_COUNT!=!M!"
                    set "MAP_SRC_!MAP_COUNT!=CS:S Custom"
                )
            )
        )
    )
)

:: 5. Scan Official Mounted Counter-Strike: Source maps
if exist "%CSS_MAPS_DIR%" (
    for %%F in ("%CSS_MAPS_DIR%\*.bsp") do (
        set "M=%%~nF"
        if not defined SEEN_!M! (
            set "SEEN_!M!=1"
            set /a MAP_COUNT+=1
            set "MAP_!MAP_COUNT!=!M!"
            set "MAP_SRC_!MAP_COUNT!=CS:S"
        )
    )
)

:: Clear temporary SEEN tracker
for /l %%I in (1,1,!MAP_COUNT!) do (
    for %%K in (!MAP_%%I!) do set "SEEN_%%K="
)

echo Available Tactical Maps (!MAP_COUNT! maps dynamically discovered):
echo ----------------------------------------------------------------------

set /a HALF=(MAP_COUNT + 1) / 2
for /l %%I in (1,1,!HALF!) do (
    set /a J=%%I + HALF
    set "ENTRY1=[%%I] !MAP_%%I!"
    if %%I LSS 10 set "ENTRY1=[ %%I] !MAP_%%I!"
    set "ENTRY2="
    if !J! LEQ !MAP_COUNT! (
        for %%K in (!J!) do (
            set "ENTRY2=[!J!] !MAP_%%K!"
            if !J! LSS 10 set "ENTRY2=[ !J!] !MAP_%%K!"
        )
    )
    set "PAD=                                  "
    set "COL1=!ENTRY1!!PAD!"
    set "COL1=!COL1:~0,30!"
    echo   !COL1! !ENTRY2!
)

echo ----------------------------------------------------------------------
echo   [ 0] Boot to Counter-Strike: Source Main Menu
echo   [ D] Open Automated Directory Picker (Select CS:S ^& Portal folders)
echo   [ I] Run Automated Deployment Engine (Auto-place plugin ^& assets)
echo   [ G] Print Complete Installation Guide (for Melty.gg ^& YouTube)
echo   [ V] Verify Assets and SearchPaths
echo   [ R] Rescan Map Folders
echo.

set "MAPCHOICE="
set /p MAPCHOICE="Select option [0 for Menu, 1-!MAP_COUNT!, D, I, G, V, R - Default: 0]: "

if /i "%MAPCHOICE%"=="R" goto :scan_maps

if /i "%MAPCHOICE%"=="G" (
    cls
    python "%~dp0package_portal_to_css.py" --guide
    echo.
    pause
    goto :scan_maps
)

if /i "%MAPCHOICE%"=="D" (
    cls
    echo ======================================================================
    echo           AUTOMATED DIRECTORY PICKER: STEAM GAMES SELECTION
    echo ======================================================================
    echo Opening folder browser for Counter-Strike: Source folder...
    for /f "usebackq delims=" %%P in (`powershell -NoProfile -Command "Add-Type -AssemblyName System.Windows.Forms; $f = New-Object Windows.Forms.FolderBrowserDialog; $f.Description = 'Select your Counter-Strike: Source Installation Directory'; $f.SelectedPath = 'C:\'; if ($f.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { Write-Output $f.SelectedPath }"`) do (
        set "CHOSEN_CSS=%%P"
    )
    if defined CHOSEN_CSS (
        set "CSS_BASE_DIR=!CHOSEN_CSS!"
        echo [OK] Selected CS:S Directory: !CSS_BASE_DIR!
    ) else (
        echo [INFO] No directory selected for CS:S, retaining: !CSS_BASE_DIR!
    )

    echo.
    echo Opening folder browser for Portal folder...
    for /f "usebackq delims=" %%P in (`powershell -NoProfile -Command "Add-Type -AssemblyName System.Windows.Forms; $f = New-Object Windows.Forms.FolderBrowserDialog; $f.Description = 'Select your Portal Installation Directory'; $f.SelectedPath = 'C:\'; if ($f.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { Write-Output $f.SelectedPath }"`) do (
        set "CHOSEN_PORTAL=%%P"
    )
    if defined CHOSEN_PORTAL (
        set "PORTAL_BASE_DIR=!CHOSEN_PORTAL!"
        echo [OK] Selected Portal Directory: !PORTAL_BASE_DIR!
    ) else (
        echo [INFO] No directory selected for Portal, retaining: !PORTAL_BASE_DIR!
    )
    echo.
    pause
    goto :scan_maps
)

if /i "%MAPCHOICE%"=="I" (
    cls
    echo ======================================================================
    echo          RUNNING AUTOMATED FILE PLACEMENT ^& DEPLOYMENT ENGINE
    echo ======================================================================
    python "%~dp0package_portal_to_css.py" --css "!CSS_BASE_DIR!" --portal "!PORTAL_BASE_DIR!"
    echo.
    pause
    goto :scan_maps
)

if /i "%MAPCHOICE%"=="V" (
    echo.
    call "%~dp0verify_assets.bat"
    pause
    goto :scan_maps
)

:: Check if user wants to boot directly to authentic CS:S Main Menu
if "%MAPCHOICE%"=="0" (
    set "BOOT_TO_MENU=1"
    set "SELECTED_MAP="
) else (
    set "BOOT_TO_MENU=0"
    if "%MAPCHOICE%"=="" (
        set "BOOT_TO_MENU=1"
        set "SELECTED_MAP="
    ) else (
        if defined MAP_%MAPCHOICE% (
            for %%K in (%MAPCHOICE%) do set "SELECTED_MAP=!MAP_%%K!"
        ) else (
            set "SELECTED_MAP=%MAPCHOICE%"
        )
    )
)

if defined SELECTED_MAP (
    for /f "tokens=* delims= " %%A in ("!SELECTED_MAP!") do set "SELECTED_MAP=%%A"
)

:: Interactive Bot Configuration for Level Matches
set "BOT_COUNT=10"
set "BOT_DIFF=1"
if not "!BOOT_TO_MENU!"=="1" (
    echo.
    echo ----------------------------------------------------------------------
    echo                 PRE-LOAD BOT CONFIGURATION
    echo ----------------------------------------------------------------------
    set /p USER_BOTS="Enter Bot Count (bot_quota 0-32) [Default: 10]: "
    if defined USER_BOTS set "BOT_COUNT=!USER_BOTS!"

    echo.
    echo Bot Difficulty Levels:
    echo   [0] Easy
    echo   [1] Normal (Default)
    echo   [2] Hard
    echo   [3] Expert
    set /p USER_DIFF="Select Bot Difficulty (0-3) [Default: 1]: "
    if defined USER_DIFF set "BOT_DIFF=!USER_DIFF!"
)

echo.
echo Quick Asset Preflight:
set "GAMEINFO_FILE=!CSS_BASE_DIR!\cstrike\gameinfo.txt"
set "CSS_EXE=!CSS_BASE_DIR!\hl.exe"
if not exist "%CSS_EXE%" set "CSS_EXE=!CSS_BASE_DIR!\cstrike.exe"

if not exist "%GAMEINFO_FILE%" (
    echo [WARN] gameinfo.txt was not found at %GAMEINFO_FILE%
) else (
    findstr /i /c:"custom/portal_strike" "%GAMEINFO_FILE%" >nul 2>&1
    if !ERRORLEVEL! EQU 0 (
        echo [OK] Isolated portal_strike search path active in CS:S gameinfo.txt
    ) else (
        echo [WARN] portal_strike search path missing in CS:S gameinfo.txt
    )
)

if not exist "%CSS_EXE%" (
    echo [WARN] CS:S executable not found at %CSS_EXE%
)

echo.
where python >nul 2>&1
if !ERRORLEVEL! EQU 0 (
    echo Syncing isolated Portal assets and standalone definitions...
    python "%~dp0package_portal_to_css.py" --css "!CSS_BASE_DIR!" --portal "!PORTAL_BASE_DIR!"
    if defined SELECTED_MAP (
        if exist "%~dp0tactical_bridge.py" (
            python "%~dp0tactical_bridge.py" !SELECTED_MAP!
        )
    )
)

echo.
echo ======================================================================
if "!BOOT_TO_MENU!"=="1" (
    echo Starting Counter-Strike: Source (Pristine CS:S Main Menu)
) else (
    echo Starting Portal Strike on: !SELECTED_MAP!
    echo Pre-Load Bots: !BOT_COUNT! combatants ^| Difficulty: Level !BOT_DIFF!
)
echo Primary Host: Counter-Strike: Source
echo Executable: %CSS_EXE% -game cstrike
echo Mod Path: !CSS_BASE_DIR!\cstrike\custom\portal_strike
echo ======================================================================
echo.

if "!BOOT_TO_MENU!"=="1" (
    start "" "%CSS_EXE%" -game cstrike -windowed -noborder -novid -condebug +sv_consistency 0 +sv_pure 0
) else (
    start "" "%CSS_EXE%" -game cstrike -windowed -noborder -novid -condebug +sv_consistency 0 +sv_pure 0 +sv_cheats 1 +mp_roundtime 2.5 +mp_freezetime 3 +mp_startmoney 800 +mp_winlimit 0 +mp_timelimit 0 +bot_difficulty !BOT_DIFF! +bot_quota !BOT_COUNT! +map !SELECTED_MAP!
)
