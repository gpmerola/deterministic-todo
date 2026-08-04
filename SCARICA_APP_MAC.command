#!/bin/zsh

set -u
cd "$(dirname "$0")" || exit 1

REPOSITORY="gpmerola/deterministic-todo"
DESTINATION="$PWD/app_pronta_macOS"

echo ""
echo "Attività deterministiche — download app macOS"
echo "Non richiede Xcode né sudo."
echo ""

if ! command -v gh >/dev/null 2>&1; then
  echo "ERRORE: GitHub CLI (gh) non è disponibile."
  echo "Su questo Mac era disponibile durante la configurazione; verifica il PATH."
  read "?Premi Invio per chiudere..."
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "GitHub richiede il login. Esegui nel Terminale: gh auth login"
  read "?Premi Invio per chiudere..."
  exit 1
fi

echo "Cerco l’ultima build riuscita..."
RUN_ID=$(gh run list \
  --repo "$REPOSITORY" \
  --workflow build-macos.yml \
  --status success \
  --limit 1 \
  --json databaseId \
  --jq '.[0].databaseId')

if [[ -z "$RUN_ID" || "$RUN_ID" == "null" ]]; then
  echo "Nessuna build riuscita è ancora disponibile."
  echo "Controlla: https://github.com/$REPOSITORY/actions"
  read "?Premi Invio per chiudere..."
  exit 1
fi

mkdir -p "$DESTINATION"
DOWNLOAD_DIR=$(mktemp -d "${TMPDIR:-/tmp}/todoapp-download.XXXXXX") || exit 1

echo "Scarico la build GitHub #$RUN_ID..."
gh run download "$RUN_ID" \
  --repo "$REPOSITORY" \
  --name DeterministicTodo-macOS \
  --dir "$DOWNLOAD_DIR" || {
    echo "Download non riuscito."
    read "?Premi Invio per chiudere..."
    exit 1
  }

ZIP_PATH="$DOWNLOAD_DIR/DeterministicTodo-macOS.zip"
if [[ ! -f "$ZIP_PATH" ]]; then
  echo "Archivio della build non trovato."
  read "?Premi Invio per chiudere..."
  exit 1
fi

ditto -x -k "$ZIP_PATH" "$DESTINATION"
APP_PATH=$(find "$DESTINATION" -maxdepth 1 -name '*.app' -print -quit)

if [[ -z "$APP_PATH" ]]; then
  echo "Il download non contiene un bundle .app."
  read "?Premi Invio per chiudere..."
  exit 1
fi

echo ""
echo "App pronta in: $APP_PATH"
echo "La apro ora."
open "$APP_PATH"

echo ""
read "?Premi Invio per chiudere questa finestra..."
