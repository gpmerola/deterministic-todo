#!/bin/zsh

set -u
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$PROJECT_ROOT" || exit 1

APK="$PWD/app_pronta_Android/DeterministicTodo-Android.apk"

if [[ ! -f "$APK" ]]; then
  echo "APK non presente. Esegui prima tools/launchers/SCARICA_APK_ANDROID.command."
  read "?Premi Invio per chiudere..."
  exit 1
fi

if ! command -v adb >/dev/null 2>&1; then
  echo "ADB non è installato: apro la cartella dell’APK."
  echo "Copia il file sul telefono e aprilo da Android."
  open "$(dirname "$APK")"
  read "?Premi Invio per chiudere..."
  exit 0
fi

DEVICE=$(adb devices | awk 'NR > 1 && $2 == "device" {print $1; exit}')
if [[ -z "$DEVICE" ]]; then
  echo "Nessun telefono autorizzato. Collega Android, abilita Debug USB"
  echo "e conferma la richiesta di autorizzazione sul telefono."
  read "?Premi Invio per chiudere..."
  exit 1
fi

echo "Installo l’APK su $DEVICE..."
adb -s "$DEVICE" install -r "$APK"
echo "Installazione terminata."
read "?Premi Invio per chiudere..."
