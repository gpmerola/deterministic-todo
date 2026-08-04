@echo off
setlocal
cd /d "%~dp0"

echo.
echo Attivita deterministiche - avvio Windows
echo Cartella: %CD%
echo.

where flutter >nul 2>nul
if errorlevel 1 (
  echo ERRORE: Flutter non e installato o non e nel PATH.
  echo Installa Flutter e Visual Studio 2022 con il workload
  echo "Desktop development with C++", poi riprova.
  echo.
  pause
  exit /b 1
)

echo Preparo le dipendenze...
call flutter pub get
if errorlevel 1 (
  echo.
  echo ERRORE durante flutter pub get.
  pause
  exit /b 1
)

echo.
echo Avvio l'app Windows. Lascia aperta questa finestra mentre la usi.
echo Per fermarla, torna qui e premi q oppure Ctrl+C.
echo.
call flutter run -d windows --dart-define-from-file=supabase/config.json

echo.
echo L'app e stata chiusa.
pause
