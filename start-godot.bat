@echo off
REM Nightbane launcher: force user-local .NET 8 SDK (no admin) for Godot 4.7 mono build.
set "DOTNET_ROOT=%LOCALAPPDATA%\Microsoft\dotnet"
set "DOTNET_HOST_PATH=%DOTNET_ROOT%\dotnet.exe"
set "DOTNET_MULTILEVEL_LOOKUP=0"
set "PATH=%DOTNET_ROOT%;%PATH%"

if not exist "%DOTNET_HOST_PATH%" (
  echo [ERROR] .NET SDK not found at:
  echo   %DOTNET_HOST_PATH%
  echo Run user-local install: https://dot.net/v1/dotnet-install.ps1
  pause
  exit /b 1
)

"%DOTNET_HOST_PATH%" --list-sdks
if errorlevel 1 (
  echo [ERROR] dotnet host broken
  pause
  exit /b 1
)

set "GODOT_EXE=C:\Users\SW-00-fiae19\Downloads\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64.exe"
set "PROJECT_DIR=%~dp0"

if not exist "%GODOT_EXE%" (
  echo [ERROR] Godot not found:
  echo   %GODOT_EXE%
  pause
  exit /b 1
)

echo Starting Godot with DOTNET_ROOT=%DOTNET_ROOT%
start "" "%GODOT_EXE%" --path "%PROJECT_DIR%"
