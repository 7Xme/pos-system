@echo off
setlocal EnableExtensions EnableDelayedExpansion
title YPOS - Build distributable EXE
cd /d "%~dp0"

rem Optional arguments (just double-click for the full build):
rem   quick    skip catalog data (fast, installer exe only)
rem   nobuild  reuse the last flutter release output
set "EXTRA="
for %%A in (%*) do (
  if /I "%%A"=="quick"   set "EXTRA=!EXTRA! -SkipData"
  if /I "%%A"=="nobuild" set "EXTRA=!EXTRA! -SkipFlutterBuild"
)

if not exist "tool\build_installer.ps1" (
  echo [ERROR] tool\build_installer.ps1 not found.
  pause
  exit /b 1
)

echo ============================================================
echo  Building YPOS distributable (release)
echo  Output: build\YPOS-Setup.exe  +  build\dist\
echo ============================================================
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tool\build_installer.ps1" %EXTRA%
if errorlevel 1 goto :failed

echo.
echo ============================================================
echo  BUILD OK
echo  Installer : %~dp0build\YPOS-Setup.exe
echo  Distribute: %~dp0build\dist   (copy the whole folder)
echo ============================================================
start "" explorer "%~dp0build\dist"
pause
exit /b 0

:failed
echo.
echo ============================================================
echo  BUILD FAILED - see messages above.
echo ============================================================
pause
exit /b 1
