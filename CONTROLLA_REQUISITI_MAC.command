#!/bin/zsh

cd "$(dirname "$0")" || exit 1

if [[ -d "$HOME/Applications/Xcode.app/Contents/Developer" ]]; then
  export DEVELOPER_DIR="$HOME/Applications/Xcode.app/Contents/Developer"
elif [[ -d "/Applications/Xcode.app/Contents/Developer" ]]; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

echo ""
echo "Controllo requisiti macOS"
echo ""

ERRORS=0

if command -v flutter >/dev/null 2>&1; then
  echo "✓ Flutter: $(flutter --version 2>/dev/null | head -n 1)"
else
  echo "✗ Flutter non trovato nel PATH."
  ERRORS=1
fi

if xcrun --find xcodebuild >/dev/null 2>&1; then
  echo "✓ Xcode completo: $(xcodebuild -version 2>/dev/null | head -n 1)"
else
  echo "✗ Xcode completo non installato."
  echo "  Command Line Tools da solo non basta per un’app Flutter macOS."
  ERRORS=1
fi

if [[ -d "$HOME/Applications/Xcode.app" ]]; then
  echo "✓ Xcode utente presente in ~/Applications/Xcode.app."
elif [[ -d "/Applications/Xcode.app" ]]; then
  echo "✓ Xcode presente in /Applications/Xcode.app."
else
  echo "✗ Xcode.app assente."
  ERRORS=1
fi

echo ""
if [[ "$ERRORS" -eq 0 ]]; then
  echo "Tutto pronto. Puoi usare AVVIA_MAC.command."
else
  echo "Configurazione necessaria:"
  echo "  1. Scarica Xcode.xip da https://developer.apple.com/download/all/"
  echo "  2. Estrailo e sposta Xcode.app in ~/Applications/."
  echo "  3. Apri Xcode dalla cartella utente almeno una volta."
  echo "Non serve modificare xcode-select: i launcher impostano DEVELOPER_DIR."
fi

echo ""
read "?Premi Invio per chiudere..."
