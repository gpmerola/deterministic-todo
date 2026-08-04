#!/bin/zsh

set -u

cd "$(dirname "$0")" || exit 1

# Xcode può vivere nella cartella utente: non richiede xcode-select né sudo.
if [[ -d "$HOME/Applications/Xcode.app/Contents/Developer" ]]; then
  export DEVELOPER_DIR="$HOME/Applications/Xcode.app/Contents/Developer"
elif [[ -d "/Applications/Xcode.app/Contents/Developer" ]]; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

echo ""
echo "Attività deterministiche — avvio macOS"
echo "Cartella: $PWD"
echo ""

if ! command -v flutter >/dev/null 2>&1; then
  echo "ERRORE: Flutter non è installato o non è nel PATH."
  echo "Installa Flutter da https://docs.flutter.dev/get-started/install/macos"
  echo ""
  read "?Premi Invio per chiudere..."
  exit 1
fi

if ! xcrun --find xcodebuild >/dev/null 2>&1; then
  echo "ERRORE: è presente solo Command Line Tools, ma Flutter macOS"
  echo "richiede l’applicazione Xcode completa."
  echo ""
  echo "Installazione senza App Store e senza sudo:"
  echo "  1. Scarica Xcode.xip da https://developer.apple.com/download/all/"
  echo "     (serve un Apple Account gratuito; il file è molto grande)."
  echo "  2. Apri Xcode.xip per estrarlo."
  echo "  3. Crea ~/Applications e sposta lì Xcode.app."
  echo "  4. Avvia ~/Applications/Xcode.app almeno una volta."
  echo ""
  echo "Il launcher userà automaticamente ~/Applications/Xcode.app tramite"
  echo "DEVELOPER_DIR: non modifica la configurazione globale del Mac."
  echo ""
  read "?Premi Invio per chiudere..."
  exit 1
fi

if ! xcodebuild -version >/dev/null 2>&1; then
  echo "ERRORE: Xcode è presente ma non è ancora configurato correttamente."
  echo "Apri Xcode dalla cartella utente, accetta la licenza e lascia che completi"
  echo "la preparazione. Se l’organizzazione blocca anche questa operazione, sarà"
  echo "necessario compilare l’app su un altro Mac e copiare qui il bundle .app."
  echo ""
  read "?Premi Invio per chiudere..."
  exit 1
fi

echo "Preparo le dipendenze..."
flutter pub get || {
  echo "ERRORE durante flutter pub get."
  read "?Premi Invio per chiudere..."
  exit 1
}

echo ""
echo "Avvio l’app macOS. Lascia aperta questa finestra mentre usi l’app."
echo "Per fermarla, torna qui e premi q oppure Ctrl+C."
echo ""
flutter run -d macos --dart-define-from-file=supabase/config.json

echo ""
read "?L’app è stata chiusa. Premi Invio per terminare..."
