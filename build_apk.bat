@echo off
echo ======================================================================
echo  Building Offline English Tutor Release APK
echo ======================================================================

where flutter >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Flutter SDK is not found in your PATH.
    echo Please install Flutter SDK from https://docs.flutter.dev/get-started/install/windows
    echo and ensure 'flutter' is added to your Environment PATH.
    pause
    exit /b 1
)

echo [1/3] Running flutter pub get...
call flutter pub get
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] flutter pub get failed.
    pause
    exit /b %ERRORLEVEL%
)

echo [2/3] Running flutter analyze...
call flutter analyze
if %ERRORLEVEL% NEQ 0 (
    echo [WARNING] flutter analyze reported issues. Continuing build...
)

echo [3/3] Compiling Release APK...
call flutter build apk --release --no-tree-shake-icons
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Flutter build apk failed.
    pause
    exit /b %ERRORLEVEL%
)

echo ======================================================================
echo  BUILD SUCCESSFUL!
echo  Release APK Location:
echo  %CD%\build\app\outputs\flutter-apk\app-release.apk
echo ======================================================================
pause
