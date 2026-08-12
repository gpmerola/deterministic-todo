# TODO e handover

Aggiornato l'11 agosto 2026. Leggere insieme ad `AGENTS.md` prima di modificare.

Handoff completo, architettura corrente e prossimo obiettivo movimento:
[`docs/HANDOFF.md`](docs/HANDOFF.md). Questo file resta la checklist sintetica;
non duplicare qui i dettagli tecnici.

## Stato corrente

- Repository sorgente pubblico: `gpmerola/deterministic-todo`.
- Repository release Android: `gpmerola/deterministic-todo-releases`.
- Branch operativo: `agent/verify-public-release-token`.
- Android è il primo canale nativo; desktop usa la web app GitHub Pages.
- Release coordinata corrente: 2.24.2 build 107. La base funzionale build 95 ha
  superato Web, manifest Android, Google Play interno e controllo di parità;
  la 96 consolida codice, test e documentazione senza cambiare l'algoritmo.
- Telefono principale: Samsung Galaxy S21, `arm64-v8a`.
- Supabase reale e convergenza Android↔cloud sono già stati provati.

## P0 — Ultimi collaudi browser

1. confermare in Chrome reale che una task locale sopravviva a chiusura e
   riapertura completa; lo startup deve fallire esplicitamente se Drift offre
   soltanto storage in memoria;
2. verificare import ed export JSON dal browser con una fixture sintetica;
3. dopo la 2.16.0 esportare la diagnostica, ricaricare la pagina ed esportarla
   di nuovo per confermare la persistenza IndexedDB sul profilo reale.

Sito HTTPS, layout desktop, pagina di avvio Chrome e sincronizzazione
Android↔browser sono già configurati. La pipeline coordinata ne verifica da
2.16.0 versione, build, commit, APK e URL pubblici.

La web app non deve dipendere dalla rete per mostrare o modificare task già
locali. Non usare navigazione in incognito come ambiente supportato.

## P0 — Passaggio definitivo da Todoist

- esportare un ultimo JSON Todoist;
- usare **Sostituisci** per ricostruire soltanto i dati Todoist;
- verificare conteggi, progetti, sezioni, descrizioni, link, priorità, date e
  ricorrenze;
- attendere la sincronizzazione e confrontare Android e browser;
- non committare mai l’export personale.

L’ultimo export analizzato conteneva 5 progetti, 13 sezioni e 110 task attive,
ma questi numeri sono storici e vanno ricalcolati sul nuovo file.

## P1 — Blocchi pratici

- provare per alcuni giorni creazione, modifica, completamento, ricorrenze,
  swipe e Indietro sul Galaxy S21;
- confermare Google Calendar su hardware Android reale;
- aggiungere una RPC Supabase transazionale prima di offrire “cancella tutto”
  contemporaneamente su cloud e dispositivo;
- valutare commenti, allegati, etichette e sotto-attività Todoist solo se
  compaiono nei prossimi export reali;
- backup cifrato e revoca remota del singolo dispositivo restano futuri.

## P0 — Collaudo corsa Bip U

- collaudare la build 105 sul Galaxy S21; il permesso di lettura Health Connect
  in background è già stato concesso. Aprire Movimento deve recuperare la
  sessione 14 e produrre nel JSON un confronto oppure un `error_code` tecnico;
  cartella Drive e permessi devono restare persistenti senza nuova configurazione;
  notifiche; impostare Batteria → Senza restrizioni per il collaudo Samsung;
- attivare una sola volta **Test passivo · 4 giorni**: non annotare soste e non
  aprire Movimento ogni giorno. Dopo quattro giorni confrontare i file
  `daily_audit_YYYY-MM-DD.json`; sono stime quotidiane senza percorso GPS e non
  sostituiscono il collaudo di una sessione esplicita;
- registrare 10–15 minuti con schermo spento, includendo una sosta di circa 30
  secondi, e confrontare distanza, passi e diagnostica con Google Fit;
- al termine si può chiudere Movimento: il job persistente attende e riprova
  Google Fit in background. La concessione deve riprogrammare automaticamente
  anche la sessione 14 già salvata. Riaprire dopo 2–3 minuti e verificare lo stato del
  confronto automatico e la presenza della coppia omonima nella
  cartella Drive; il JSON deve contenere `google_fit_comparison` senza premere
  riesporta o confronta manualmente;
- verificare che la notifica termini la sessione e che riaprire l'attività dopo
  una sospensione conservi durata e distanza;
- provare scansione e batteria con Zepp completamente chiusa. Se il servizio
  batteria non è esposto prima dell'autenticazione, non aggirare la protezione;
- implementare in modo indipendente autenticazione Huami e download attività
  solo dopo capture BLE autorizzate sul dispositivo personale; aggiungere
  fixture sintetiche prive di chiave/MAC e test di allineamento timestamp;
- abilitare battito live soltanto dopo conferma sul Bip U reale. Firmware,
  risorse e impostazioni dell'orologio restano fuori ambito.

## P0 — Passi e distanza quotidiana

- il recupero passi Health Connect e il contatore diretto di sessione sono
  verificati sul Galaxy S21; resta da verificare un cambio giorno reale con
  app chiusa e riconciliazione alla riapertura;
- aggiungere profilo locale con peso e falcata, calibrazione tramite sessione
  GPS e stima calorica versionata; i valori 70 kg/0,72 m sono solo provvisori;
- collaudare `TYPE_STEP_COUNTER` durante sessioni con schermo spento; la
  gestione del totale quotidiano attraverso mezzanotte/reboot resta distinta;
- valutare `WorkManager` e lettura Health Connect in background solo dopo una
  misura reale: il conteggio di sistema non richiede polling dell'app;
- mostrare separatamente distanza GPS di una sessione e distanza quotidiana
  stimata dai passi, senza doppio conteggio;
- calibrare separatamente i profili manuali `Camminata` e `Corsa` sul telefono;
- non mantenere GPS, BLE o un foreground service permanente per il conteggio
  quotidiano;
- misurare batteria sul Galaxy S21 prima di ampliare il lavoro in background;
- rimandare autenticazione e import Amazfit finché questo MVP non è collaudato.

## P2 — Performance

Misurare prima di ottimizzare ulteriormente:

- la build 106 limita la cache immagini a 16 MiB, rimuove Realtime in
  background e registra PSS totale/Java/native/grafica oltre al RSS; esportare
  una nuova diagnostica della build 106/107 dopo almeno un giorno per
  confrontarla con la baseline RSS media 203 MiB e picco 284 MiB del 5–11
  agosto; `diagnostics (5).jsonl` era byte-per-byte identico al file precedente
  e terminava ancora alla build 105;

- baseline reale 5–8 agosto registrata in
  `docs/diagnostics/2026-08-08-web-android.md`;

- cold/warm start Android;
- RAM e frame pacing con 100, 1.000 e 10.000 task;
- CPU a riposo per cinque minuti;
- dimensione e latenza del database browser;
- tempo di primo sync e reimport Todoist.

Il browser usa SQLite Drift WebAssembly; Android usa SQLite nativo in background.
Non introdurre polling, timer o dipendenze senza una misura che li giustifichi.

## Checklist di consegna

1. controllare `git status -sb` e preservare dati personali/chiavi;
2. aggiornare versione, test e documentazione;
3. eseguire `dart format lib test`, `flutter analyze`, `flutter test`,
   `flutter build web --release` e i controlli Android pertinenti;
4. commit e push sul branch `agent/*`;
5. attendere e verificare entrambe le pipeline automatiche;
6. collaudare fisicamente Android e, per cambi web, refresh/persistenza in
   Chrome sul sito pubblicato.
