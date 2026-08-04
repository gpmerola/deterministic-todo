#!/bin/zsh

cd "$(dirname "$0")" || exit 1

APP_PATH=$(find "$PWD/app_pronta_macOS" -maxdepth 1 -name '*.app' -print -quit 2>/dev/null)

if [[ -n "$APP_PATH" ]]; then
  open "$APP_PATH"
  exit $?
fi

echo "L’app non è ancora stata scaricata. Avvio il download automatico..."
exec "$PWD/SCARICA_APP_MAC.command"
