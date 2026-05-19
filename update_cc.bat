@echo off
REM update_cc.bat -- Replace cc.exe with cc_new.exe
REM Usa un rename indirecto porque cc.exe puede estar en uso.
cd /d %~dp0
if not exist cc_new.exe (
    echo cc_new.exe not found -- run build_cc.bat first.
    exit /b 1
)
ren cc.exe cc.old 2>nul
if errorlevel 1 (
    echo cc.exe is in use (CCHarbour is running).
    echo.
    echo Options:
    echo   1. Exit CCHarbour first, then run this batch again.
    echo   2. Or manually copy later: copy /y cc_new.exe cc.exe
    echo.
    exit /b 1
)
copy /y cc_new.exe cc.exe >nul
del cc.old
echo cc.exe updated successfully.
