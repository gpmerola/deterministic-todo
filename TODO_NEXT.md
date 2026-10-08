# TODO e handover

Solo voci **aperte**. Le voci completate fino alla build 238 sono state tolte
il 7 ottobre 2026: esiti in [STATUS](STATUS.md), storia in
[CHANGELOG](CHANGELOG.md) e nella cronologia git di questo file. Leggere insieme
ad `AGENTS.md` e [`docs/HANDOFF.md`](docs/HANDOFF.md) prima di modificare.

## P1 — Manutenzione aperta (revisione del 7 ottobre 2026)

- [ ] `flutter_secure_storage` 10 → 11: la release stabile 242 (con la 10) è
  pubblicata; prima verificare che Play e APK diretto l'abbiano installata.
- [ ] «Tutta la serie» dall'app su un calendario Google reale: provata solo su
  emulatore.
- [ ] Test UI via ADB: mai toccare la fascia alta dello schermo dove compaiono
  le notifiche; preferire una schermata appena catturata prima di ogni tocco.
- [ ] Proseguire la divisione di `lib/main.dart` (`_TaskShellState`) e
  `lib/ui/views/agenda_view.dart` in controller più piccoli.

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

- [ ] Completare la persistenza dopo chiusura **completa** di Chrome quando
  la sessione attiva con videocamera/microfono è terminata. Modifiche nei due
  sensi, storico, Inbox e refresh già verificati su fixture sintetica:
  [esiti e ripresa](docs/diagnostics/2026-10-08-todo-cross-device-smoke.md).
- [ ] Sul Galaxy e sul Web convertire con **Sposta in Inbox** il vecchio
  progetto "Inbox", dopo aver aggiornato e ricaricato entrambi i client.
- [ ] Collaudi Web sul profilo Chrome reale ([WEB](docs/operations/WEB.md)):
  import/export JSON con fixture sintetica; rimozione dalla vista
  **Attività senza data** e **Svuota cestino** con dati esclusivamente di prova
  e autorizzazione specifica per la cancellazione permanente.

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
