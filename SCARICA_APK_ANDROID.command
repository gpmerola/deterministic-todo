#!/bin/zsh

set -u
cd "$(dirname "$0")" || exit 1

REPOSITORY="gpmerola/deterministic-todo"
DESTINATION="$PWD/app_pronta_Android"

echo ""
echo "Attività deterministiche — download APK Android"
echo ""

if ! command -v gh >/dev/null 2>&1 || ! gh auth status >/dev/null 2>&1; then
  echo "GitHub CLI non è disponibile o non è autenticato."
  echo "Esegui: gh auth login"
  read "?Premi Invio per chiudere..."
  exit 1
fi

RUN_ID=$(gh run list \
  --repo "$REPOSITORY" \
  --workflow build-android.yml \
  --status success \
  --limit 1 \
  --json databaseId \
  --jq '.[0].databaseId')

if [[ -z "$RUN_ID" || "$RUN_ID" == "null" ]]; then
  echo "Nessuna build Android riuscita è ancora disponibile."
  echo "Controlla: https://github.com/$REPOSITORY/actions"
  read "?Premi Invio per chiudere..."
  exit 1
fi

mkdir -p "$DESTINATION"
TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/todoapp-android.XXXXXX") || exit 1

echo "Scarico la build GitHub #$RUN_ID..."
gh run download "$RUN_ID" \
  --repo "$REPOSITORY" \
  --name DeterministicTodo-Android \
  --dir "$TEMP_DIR" || exit 1

SOURCE_APK="$TEMP_DIR/app-arm64-v8a-release.apk"

if [[ ! -f "$SOURCE_APK" ]]; then
  echo "APK ARM64 non trovato nell’artefatto."
  echo "Il Galaxy S21 richiede app-arm64-v8a-release.apk."
  read "?Premi Invio per chiudere..."
  exit 1
fi

cp "$SOURCE_APK" "$DESTINATION/DeterministicTodo-Android.apk"

echo ""
echo "APK pronto in:"
echo "  $DESTINATION/DeterministicTodo-Android.apk"
echo "  Variante: ARM64 ottimizzata per Samsung Galaxy S21"
echo ""
echo "Puoi copiarlo sul telefono con AirDrop alternativo, Drive, cavo USB"
echo "o un altro metodo di trasferimento file, quindi aprirlo su Android."
open "$DESTINATION"

echo ""
read "?Premi Invio per chiudere..."
