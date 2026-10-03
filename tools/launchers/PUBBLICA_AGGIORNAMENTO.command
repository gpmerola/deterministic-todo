#!/bin/zsh

set -u
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$PROJECT_ROOT" || exit 1

echo ""
echo "Pubblica aggiornamento Android + browser"
echo ""

if ! command -v flutter >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1; then
  echo "Flutter o Git non sono disponibili nel PATH."
  read "?Premi Invio per chiudere..."
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "GitHub CLI non è autenticato. Esegui: gh auth login"
  read "?Premi Invio per chiudere..."
  exit 1
fi

if [[ -z "$(git status --porcelain)" ]]; then
  echo "Non ci sono modifiche da pubblicare."
  read "?Premi Invio per chiudere..."
  exit 0
fi

echo "Formatto e verifico il progetto..."
dart format lib test || exit 1
flutter analyze || exit 1
flutter test || exit 1

echo ""
echo "File che verranno pubblicati:"
git status --short
echo ""
read "?Descrizione breve dell’aggiornamento: " MESSAGE

if [[ -z "${MESSAGE// /}" ]]; then
  echo "Descrizione vuota: pubblicazione annullata."
  read "?Premi Invio per chiudere..."
  exit 1
fi

echo ""
read "?Confermi commit e push su GitHub? (scrivi SI): " CONFIRM
if [[ "$CONFIRM" != "SI" ]]; then
  echo "Pubblicazione annullata."
  read "?Premi Invio per chiudere..."
  exit 0
fi

git add -A || exit 1
git diff --cached --check || exit 1
git commit -m "$MESSAGE" || exit 1
git push || exit 1

echo ""
echo "Pubblicato. GitHub sta creando Android e la versione browser."
echo "Controlla: https://github.com/gpmerola/deterministic-todo/actions"
echo "L’APK si scarica da tools/launchers/SCARICA_APK_ANDROID.command."
echo ""
read "?Premi Invio per chiudere..."
