#!/bin/zsh

set -u
cd "$(dirname "$0")" || exit 1

echo ""
echo "Creazione applicazione installabile"
echo ""
echo "Scegli la piattaforma disponibile su questo computer:"
echo "  1) macOS (.app)"
echo "  2) Android (.apk)"
echo ""
read "?Scelta: " CHOICE

if ! command -v flutter >/dev/null 2>&1; then
  echo "ERRORE: Flutter non è installato o non è nel PATH."
  read "?Premi Invio per chiudere..."
  exit 1
fi

flutter pub get || exit 1

case "$CHOICE" in
  1)
    flutter build macos --release --dart-define-from-file=supabase/config.json && {
      echo ""
      echo "App creata in: build/macos/Build/Products/Release/"
      open build/macos/Build/Products/Release
    }
    ;;
  2)
    flutter build apk --release --dart-define-from-file=supabase/config.json && {
      echo ""
      echo "APK creato in: build/app/outputs/flutter-apk/app-release.apk"
      open build/app/outputs/flutter-apk
    }
    ;;
  *)
    echo "Scelta non valida."
    ;;
esac

echo ""
read "?Premi Invio per chiudere..."
