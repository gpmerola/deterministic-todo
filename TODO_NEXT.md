# TODO e handover

Solo voci **aperte**; riordinato il 17 ottobre 2026. Esiti in
[STATUS](STATUS.md), storia in
[CHANGELOG](CHANGELOG.md) e nella cronologia git di questo file. Leggere insieme
ad `AGENTS.md` e [`docs/HANDOFF.md`](docs/HANDOFF.md) prima di modificare.

## Da fare con l'utente

Richiedono il telefono, il Chrome reale o dati reali: non eseguirle da soli.

- [ ] Sul Galaxy e sul Web convertire con **Sposta in Inbox** il vecchio
  progetto "Inbox", dopo aver aggiornato e ricaricato entrambi i client.
- [ ] «Tutta la serie» dall'app su un calendario Google reale: provata solo su
  emulatore.
- [ ] Collaudi Web sul profilo Chrome reale ([WEB](docs/operations/WEB.md)):
  persistenza dopo chiusura completa di Chrome (sul profilo di prova si perde
  solo un completamento chiuso entro circa 12–60 ms,
  [esiti](docs/diagnostics/2026-10-13-web-persistence.md)); import/export
  JSON con fixture sintetica; rimozione dalla vista **Attività senza data** e
  **Svuota cestino** con dati esclusivamente di prova e autorizzazione
  specifica per la cancellazione permanente.

## Osservazioni passive

Nessuna azione finché non emerge un problema.

- Second Brain: prima esecuzione automatica oraria e frase da una nuova chat
  con Drive collegato (STATUS).
- Un giorno di batteria: il job Calendario a trigger deve fermarsi
  all'impronta quando non cambia nulla.
- Impronte v2 (produzione dal 12 ottobre 2026): `diverged_buckets` su più
  cicli reali.
- Al prossimo avviso sync, non forzare retry: leggere lo stato con il
  provider ADB `todo_sync_debug` (fase, classe errore, outbox, recupero).

## Idee aperte, solo su richiesta

- Fuso diverso alla creazione di un evento (oggi quello del telefono).
- Unione heydoc/Semble (stesso inizio, titoli diversi).
- Opzione sincronizzata «Mostra in agenda» (colonna + migrazione Supabase).
- Rimuovere `due_date` da Supabase solo con migrazione approvata.
- RPC Supabase transazionale prima di un «cancella tutto» cloud + dispositivo.
- Commenti, allegati, etichette, sotto-attività Todoist solo se negli export.
- Revoca remota del singolo dispositivo.
- Backup automatico anche fuori dal telefono (es. Supabase cifrato): oggi
  Documenti/Todo backup, copiabile dall'utente.

Escluse dall'utente (12 e 16 ottobre 2026), da non riproporre: ulteriore
aggregazione dei calendari KCL/SLaM (anche via ICS), pulizia del Markdown nei
titoli degli eventi creati, azioni dirette in Problemi di sincronizzazione,
ricerca indipendente dagli accenti, misure di prestazioni sul Galaxy, note,
ripetizione e cambio calendario degli eventi modificati dal Web.

Prima di ottimizzare, misurare: baseline in
`docs/diagnostics/2026-08-08-web-android.md`; ultimi esiti
[Settimana](docs/diagnostics/2026-10-13-calendar-week-build.md),
[backup](docs/diagnostics/2026-10-16-backup-isolate-and-week-wrap.md),
[avvio Web](docs/diagnostics/2026-10-13-web-startup.md). Non introdurre
polling, timer o dipendenze senza una misura che li giustifichi.

## Stato corrente

- Repository sorgente `gpmerola/deterministic-todo`; release Android
  `gpmerola/deterministic-todo-releases`. Ultima stabile 2.98.0 / 277;
  branch operativo `agent/maintenance-perf` (build 279 su Todo Test,
  [PR #4](https://github.com/gpmerola/deterministic-todo/pull/4)).
- Galaxy S21 (`arm64-v8a`): **Todo Test** (`.dev`) è il solo client operativo;
  la build Play 121 resta installata ma `disabled-user`. Runbook:
  [ANDROID_DEV_CHANNEL](docs/operations/ANDROID_DEV_CHANNEL.md).
- Movimento archiviato dalla build 190: solo contapassi
  ([MOVIMENTO](docs/archive/MOVIMENTO.md)).
- Shell divisa in `lib/ui/shell/` (vedi [HANDOFF](docs/HANDOFF.md)); nuovi
  flussi vanno nei `part` esistenti, non di nuovo in `main.dart`.

## Checklist di consegna

1. controllare `git status -sb` e preservare dati personali/chiavi;
2. aggiornare versione, test e documentazione;
3. eseguire `make check-generated`, `make check`, le build release e i
   controlli Android pertinenti;
4. commit e push sul branch `agent/*`;
5. attendere e verificare entrambe le pipeline automatiche;
6. collaudare fisicamente Android e, per cambi web, refresh/persistenza in
   Chrome sul sito pubblicato.
