#!/bin/zsh

set -u

cd "$(dirname "$0")" || exit 1

echo ""
echo "Attività deterministiche — avvio Android"
echo ""

if ! command -v flutter >/dev/null 2>&1; then
  echo "ERRORE: Flutter non è installato o non è nel PATH."
  echo "Installa Flutter e Android Studio, poi riprova."
  read "?Premi Invio per chiudere..."
  exit 1
fi

echo "Cerco un telefono o emulatore Android..."
ANDROID_DEVICE_ID=$(flutter devices | awk -F ' • ' '/ • android-/ {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit}')

if [[ -z "$ANDROID_DEVICE_ID" ]]; then
  echo ""
  echo "Nessun dispositivo Android disponibile."
  echo ""
  echo "Puoi:"
  echo "  1. collegare un telefono con Debug USB attivo; oppure"
  echo "  2. avviare un emulatore da Android Studio > Device Manager."
  echo ""
  echo "Dispositivi rilevati da Flutter:"
  flutter devices
  echo ""
  read "?Premi Invio per chiudere..."
  exit 1
fi

echo "Trovato dispositivo: $ANDROID_DEVICE_ID"
echo "Preparo le dipendenze..."
flutter pub get || {
  echo "ERRORE durante flutter pub get."
  read "?Premi Invio per chiudere..."
  exit 1
}

echo ""
echo "Compilo, installo e avvio l’app Android."
echo "Per fermare la sessione, torna qui e premi q oppure Ctrl+C."
echo ""
flutter run -d "$ANDROID_DEVICE_ID" --dart-define-from-file=supabase/config.json

echo ""
read "?La sessione è terminata. Premi Invio per chiudere..."
