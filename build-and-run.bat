@echo off
REM Build C# then launch Godot.
REM Fixed: never use %~dp0 with trailing \ inside quoted --path (breaks start).

set "DOTNET_ROOT=%LOCALAPPDATA%\Microsoft\dotnet"
set "DOTNET_HOST_PATH=%DOTNET_ROOT%\dotnet.exe"
set "DOTNET_MULTILEVEL_LOOKUP=0"
set "PATH=%DOTNET_ROOT%;%PATH%"

set "GODOT_EXE=C:\Users\SW-00-fiae19\Downloads\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64.exe"
set "PROJECT_DIR=C:\Users\SW-00-fiae19\OneDrive - bbw Gruppe\VS Code\rogue-lite-trololol"

echo.
echo === Nightbane build-and-run ===
echo Project: %PROJECT_DIR%
echo Godot:   %GODOT_EXE%
echo.

if not exist "%DOTNET_HOST_PATH%" (
  echo [ERROR] Missing user SDK at %DOTNET_HOST_PATH%
  pause
  exit /b 1
)

if not exist "%GODOT_EXE%" (
  echo [ERROR] Missing Godot at %GODOT_EXE%
  pause
  exit /b 1
)

if not exist "%PROJECT_DIR%\project.godot" (
  echo [ERROR] Project not found at:
  echo   %PROJECT_DIR%
  pause
  exit /b 1
)

if not exist "%PROJECT_DIR%\Nightbane.csproj" (
  echo [ERROR] Nightbane.csproj missing.
  pause
  exit /b 1
)

echo SDK:
"%DOTNET_HOST_PATH%" --list-sdks
echo.

echo === Building ===
pushd "%PROJECT_DIR%"
"%DOTNET_HOST_PATH%" build "Nightbane.csproj" -c Debug --nologo
if errorlevel 1 (
  echo.
  echo [ERROR] Build failed.
  popd
  pause
  exit /b 1
)
popd

echo.
echo Build OK - launching Godot...
start "" "%GODOT_EXE%" --path "%PROJECT_DIR%"
echo Godot started.
