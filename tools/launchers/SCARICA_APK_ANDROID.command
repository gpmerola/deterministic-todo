#!/bin/zsh

set -u
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$PROJECT_ROOT" || exit 1

DESTINATION="$PROJECT_ROOT/app_pronta_Android"
APK="$DESTINATION/DeterministicTodo-Android.apk"
URL="https://github.com/gpmerola/deterministic-todo-releases/releases/latest/download/DeterministicTodo-Android-arm64-v8a.apk"

echo ""
echo "Deterministic Todo — download Android ARM64"
echo ""

mkdir -p "$DESTINATION"
if ! curl --fail --location --retry 3 "$URL" --output "$APK"; then
  echo "Download non riuscito. Riprova tra poco."
  read "?Premi Invio per chiudere..."
  exit 1
fi

echo "APK pronto in: $APK"
open "$DESTINATION"
read "?Premi Invio per chiudere..."
