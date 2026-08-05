# Stato corrente

Aggiornato il 5 agosto 2026.

- Canali supportati: Android nativo e browser Chrome/Edge.
- Versione in pubblicazione: 2.14.1 build 42.
- Fonte locale: SQLite Drift; replica facoltativa: Supabase con RLS.
- Release: un solo workflow coordinato Android + web con parità verificata di
  versione, build e commit.
- Test automatici: dominio, migrazioni, repository, sync, import Todoist, update,
  diagnostica e UI.
- Blocchi esterni: verifica hardware Android/Google Calendar e passaggio finale
  da Todoist descritti in [TODO_NEXT.md](TODO_NEXT.md).

Le decisioni architetturali sono in [docs/ARCHITETTURA.md](docs/ARCHITETTURA.md),
le procedure in [docs/operations/](docs/operations/) e la cronologia in
[CHANGELOG.md](CHANGELOG.md).
