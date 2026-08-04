@echo off
setlocal
cd /d "%~dp0"

where flutter >nul 2>nul
if errorlevel 1 (
  echo ERRORE: Flutter non e installato o non e nel PATH.
  pause
  exit /b 1
)

call flutter pub get
if errorlevel 1 goto :error

call flutter build windows --release --dart-define-from-file=supabase/config.json
if errorlevel 1 goto :error

echo.
echo Applicazione creata in:
echo %CD%\build\windows\x64\runner\Release
start "" "%CD%\build\windows\x64\runner\Release"
pause
exit /b 0

:error
echo.
echo La compilazione non e riuscita. Leggi il messaggio sopra.
pause
exit /b 1
