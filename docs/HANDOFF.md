# Handoff tecnico e di prodotto

Punto di ingresso per una nuova chat o un nuovo agente. Riscritto il
7 ottobre 2026 (build 238); la versione precedente, centrata su Movimento e
ferma alle build 95–190, è in [archivio](archive/HANDOFF_2026-08.md). Leggere
insieme ad [`AGENTS.md`](../AGENTS.md), [`TODO_NEXT.md`](../TODO_NEXT.md) e,
per gli esiti verificati, [`STATUS.md`](../STATUS.md).

## Prodotto

Deterministic Todo è un gestore personale Flutter offline-first. Android
(Galaxy S21) è il client prioritario; su desktop si usa la web app. SQLite
locale è sempre la fonte immediata dell'interfaccia; Supabase è una replica
personale. Niente analytics, collaborazione o dipendenza dalla rete per l'uso
ordinario.

Tre aree:

1. **Todo** — attività, progetti, sezioni, ricorrenze, import Todoist.
   Contratti: [pianificazione e viste](architecture/TODO_PLANNING_MODEL.md),
   [sincronizzazione e storico](architecture/TODO_SYNC_AND_HISTORY.md),
   [sync compatta](architecture/TODO_SYNC_PERFORMANCE.md),
   [paginazione](architecture/TODO_SYNC_PAGINATION.md),
   [backup e lifecycle](architecture/TODO_BACKUP_AND_LIFECYCLE.md),
   [UX hardening](architecture/TODO_UX_HARDENING.md).
2. **Calendario** (identificatori interni ancora «agenda») — unione dei
   calendari di sistema Android, copia di sola lettura sul Web, coda di
   modifiche Web→telefono, backup su Supabase. Contratto:
   [Calendario unificato](architecture/AGENDA.md).
3. **Contapassi** — unico resto del modulo Movimento, archiviato dalla build
   190 ([MOVIMENTO](archive/MOVIMENTO.md)). Non reintrodurre GPS, Amazfit,
   Health Connect o diagnostica senza decisione esplicita dell'utente.

Funzioni accessorie: assistente ✨ ([AI_ASSISTANT](architecture/AI_ASSISTANT.md))
e copia privata su Drive ([SECOND_BRAIN](operations/SECOND_BRAIN.md)).

## Struttura del codice

- `lib/domain/` — regole pure: date civili, parser, ricorrenze, Calendario.
- `lib/data/local/` — Drift/SQLite (`database.g.dart` è generato:
  `make check-generated`).
- `lib/data/sync/` — outbox, versioni Lamport, tombstone, Supabase/Realtime.
  Hotspot: `sync_service.dart`.
- `lib/services/` — calendario, backup, import/export, aggiornamenti, AI.
- `lib/ui/` — shell (`lib/main.dart`, ancora grande), viste in `ui/views/`.
- `android/app` — canali nativi Calendario, scorciatoia Home, debug provider.
- `android/runtracker` — contapassi (Room + Recording API, nessun GPS/BLE).
- `supabase/migrations/` — applicate a mano solo dopo consenso specifico;
  test in `tools/sql-tests/`.
- `web/` — `drift_worker.js` e `sqlite3.wasm` compilati: vanno rigenerati
  insieme a un aggiornamento di `drift`/`sqlite3`.

Dettagli: [ARCHITETTURA](ARCHITETTURA.md).

## Consegna

- `make check` (analisi, test Flutter, strumenti, link documentazione, SQL) e
  `make check-generated` prima di ogni commit funzionale.
- Todo Test (`.dev`): `make todo-test`, ADB via `s21-adb` e Tailscale
  ([ADB_WIFI](operations/ADB_WIFI.md),
  [ANDROID_DEV_CHANNEL](operations/ANDROID_DEV_CHANNEL.md)). La build Play 121
  resta installata ma `disabled-user`: non riattivarla né disinstallarla.
- Release stabile (Web, APK diretti, Play interno) solo dopo conferma
  `PUBBLICA`: [RELEASE](operations/RELEASE.md),
  [GOOGLE_PLAY](operations/GOOGLE_PLAY.md), [WEB](operations/WEB.md).
- Performance e aggiornamenti:
  [ANDROID_PERFORMANCE_E_AGGIORNAMENTI](ANDROID_PERFORMANCE_E_AGGIORNAMENTI.md).

## Segreti e dati sensibili

Non inserire mai in chat, Git, log, diagnostica o fixture: credenziali
Supabase, GitHub o Play Console, chiavi di firma, chiavi API dell'assistente,
titoli/note delle attività o dettagli di eventi reali, dati di attività fisica.
La publishable key Supabase è configurazione client; service role, chiavi di
firma e token restano segreti.

## Ripresa consigliata

1. Leggere `AGENTS.md`, `TODO_NEXT.md` e questo file; controllare `git status -sb`.
2. Le voci aperte più utili sono i riscontri dell'utente sul Galaxy e la
   manutenzione elencata in `TODO_NEXT.md` (dipendenze bloccate, divisione di
   `main.dart`).
3. Ogni modifica funzionale: versione/build in `pubspec.yaml`, CHANGELOG,
   STATUS, `make check`, `make todo-test` e prova sul Galaxy.
