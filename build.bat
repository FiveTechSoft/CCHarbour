@echo off
setlocal
rem ---------------------------------------------------------------------------
rem CCHarbour build script.
rem
rem The Harbour install ships msvc64 libraries built against the *dynamic* CRT
rem (/MD). hbmk2 links the static CRT by default, which leaves the CRT import
rem symbols (_dclass, _wfsopen, isdigit, ...) unresolved. The HB_USER_* vars
rem below force dynamic-CRT linking so the build succeeds.
rem ---------------------------------------------------------------------------

set "HARBOUR=C:\harbour"
set "HBMK2=%HARBOUR%\bin\win\msvc64\hbmk2.exe"

if not exist "%HBMK2%" (
  echo ERROR: hbmk2 not found at "%HBMK2%".
  echo Set HARBOUR in this script to your Harbour install path.
  exit /b 1
)

rem Locate a Visual Studio C++ toolchain (MSVC linker + CRT). VS2019 first: the
rem Harbour libs were built with it, so it is the proven match.
set "VCVARS="
for %%V in (
  "C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
  "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"
  "C:\Program Files\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
) do if not defined VCVARS if exist %%V set "VCVARS=%%V"

if not defined VCVARS (
  echo ERROR: vcvars64.bat not found. Install Visual Studio with the C++ tools.
  exit /b 1
)

echo Using %VCVARS%
call %VCVARS% >nul

set "HB_USER_CFLAGS=-MD"
set "HB_USER_LDFLAGS=/NODEFAULTLIB:libcmt.lib /NODEFAULTLIB:libucrt.lib /NODEFAULTLIB:libvcruntime.lib msvcrt.lib ucrt.lib vcruntime.lib"

"%HBMK2%" -comp=msvc64 cc.hbp
if errorlevel 1 (
  echo.
  echo BUILD FAILED.
  exit /b 1
)

echo.
echo Build OK -^> cc.exe
endlocal
