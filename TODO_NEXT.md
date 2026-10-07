# TODO e handover

Solo voci **aperte**. Le voci completate fino alla build 238 sono state tolte
il 7 ottobre 2026: esiti in [STATUS](STATUS.md), storia in
[CHANGELOG](CHANGELOG.md) e nella cronologia git di questo file. Leggere insieme
ad `AGENTS.md` e [`docs/HANDOFF.md`](docs/HANDOFF.md) prima di modificare.

## P1 — Manutenzione aperta (revisione del 7 ottobre 2026)

- [ ] `flutter_secure_storage` 10 → 11 solo dopo una release stabile con la 10
  (build ≥ 240) installata su ogni client: la 11 non legge i dati v9.
- [ ] Controllare a mano, nell'app, se attività importate in passato da
  Todoist o da backup hanno accenti alterati («Ã©» al posto di «é»): il bug
  di decodifica è corretto dalla build 240.
- [ ] Web pubblica dopo `PUBBLICA`: confermare su HTTPS reale che la sessione
  (cassaforte web 2.x) e i dati (drift 2.35) restino dopo il refresh.
- [ ] Calendario 241 sul Galaxy: provare con un evento reale una modifica e
  un'eliminazione di una singola occorrenza e verificare su Google/Outlook.
- [ ] Proseguire la divisione di `lib/main.dart` (`_TaskShellState`) e
  `lib/ui/views/agenda_view.dart` in controller più piccoli.
- [ ] Facoltativo, solo su decisione esplicita: migrazione Room che elimini le
  tabelle archiviate `run_sessions`, `track_points`, `bip_u_activity_samples`.

## P1 — Riscontri dell'utente sul Galaxy

- [ ] Calendario: riscontro sulle build 219–238 (mese con meno eventi e «+N»,
  221–224, 226), vista settimana, attività «Mostra in Agenda», evento
  ricorrente, ricerca dalla lente, titolo e margine della vista giorno.
- [ ] Conferma del launcher e apertura dalla scorciatoia Calendario (233).
- [ ] Prima modifica reale di un evento: Google/Outlook senza duplicati.
- [ ] Pulsante Teams su una riunione reale.
- [ ] Ripristino del backup Calendario con serie reali su telefono vuoto.
- [ ] Assistente ✨: scegliere «Nuovi eventi in» e provare una creazione reale;
  se non gradito, cercare «✨» per rimuovere gli elementi creati.
- [ ] Anteprima descrizione (188): numero di righe gradito?
- [ ] Contapassi: anello e pannello; nessun job archiviato in
  `adb shell dumpsys jobscheduler` per `.dev`, nessuna notifica GPS.
- [ ] Facoltativo: account k25129662 anche in Samsung Email.

## P1 — Osservazioni in corso

- [ ] Second Brain: prima esecuzione automatica oraria e frase da una nuova chat
  con Drive collegato (STATUS).
- [ ] Un giorno di batteria: il job Calendario a trigger deve fermarsi
  all'impronta quando non cambia nulla.
- [ ] `diverged_buckets` su più cicli reali prima di progettare una riparazione.
- [ ] Web: velocità di caricamento in una finestra visibile.
- [ ] Al prossimo avviso sync, non forzare retry: leggere lo stato con il
  provider ADB `todo_sync_debug` (fase, classe errore, outbox, recupero).

## P0 — Convergenza Android ↔ Web

- [ ] Ricaricare le schede Web e verificare convergenza con l'ultima Todo Test,
  incluso lo storico della singola attività.
- [ ] Sul Galaxy e sul Web convertire con **Sposta in Inbox** il vecchio
  progetto "Inbox", dopo aver aggiornato e ricaricato entrambi i client.
- [ ] Collaudi Web sul profilo Chrome reale ([WEB](docs/operations/WEB.md)):
  persistenza dopo chiusura completa; import/export JSON con fixture
  sintetica; diagnostica persistente dopo refresh; **Senza data** su una
  fixture di progetto; **Attività senza data**, Inbox e **Svuota cestino**
  convergenti sugli altri dispositivi.

## P0 — Passaggio definitivo da Todoist

- esportare un ultimo JSON Todoist e usare **Sostituisci**;
- verificare conteggi, progetti, sezioni, descrizioni, link, priorità, date e
  ricorrenze, poi confrontare Android e browser;
- non committare mai l'export personale.

## P2 — Idee e decisioni future

- Fuso diverso alla creazione di un evento (oggi quello del telefono).
- Unione heydoc/Semble (stesso inizio, titoli diversi) solo se richiesta.
- SLaM: lettura ICS nell'app solo se l'abbonamento Google è troppo lento.
- Opzione sincronizzata «Mostra in agenda» (colonna + migrazione Supabase).
- Creazione/modifica Calendario dal Web tramite coda eseguita dal telefono.
- Azioni dirette per elementi rifiutati in Problemi di sincronizzazione.
- Rimuovere `due_date` da Supabase solo con migrazione approvata.
- Valutare se `LIKE` solo ASCII basta per le lettere accentate.
- RPC Supabase transazionale prima di un «cancella tutto» cloud + dispositivo.
- Commenti, allegati, etichette, sotto-attività Todoist solo se negli export.
- Backup cifrato e revoca remota del singolo dispositivo.

## P2 — Performance

Misurare prima di ottimizzare: cold/warm start, RAM e frame con 100/1.000/10.000
task, CPU a riposo, latenza del database browser, primo sync e reimport
Todoist. Baseline in `docs/diagnostics/2026-08-08-web-android.md`. Non
introdurre polling, timer o dipendenze senza una misura che li giustifichi.

## Stato corrente

- Repository sorgente `gpmerola/deterministic-todo`; release Android
  `gpmerola/deterministic-todo-releases`; branch operativo
  `agent/todo-ux-sync-hardening`.
- Galaxy S21 (`arm64-v8a`): **Todo Test** (`.dev`) è il solo client operativo;
  la build Play 121 resta installata ma `disabled-user`. Runbook:
  [ANDROID_DEV_CHANNEL](docs/operations/ANDROID_DEV_CHANNEL.md).
- Movimento archiviato dalla build 190: solo contapassi
  ([MOVIMENTO](docs/archive/MOVIMENTO.md)); le vecchie checklist GPS, Bip U,
  Fit e diagnostica non sono più applicabili.

## Checklist di consegna

1. controllare `git status -sb` e preservare dati personali/chiavi;
2. aggiornare versione, test e documentazione;
3. eseguire `make check-generated`, `make check`, le build release e i
   controlli Android pertinenti;
4. commit e push sul branch `agent/*`;
5. attendere e verificare entrambe le pipeline automatiche;
6. collaudare fisicamente Android e, per cambi web, refresh/persistenza in
   Chrome sul sito pubblicato.
