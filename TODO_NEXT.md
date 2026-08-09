# TODO e handover

Aggiornato il 9 agosto 2026. Leggere insieme ad `AGENTS.md` prima di modificare.

## Stato corrente

- Repository sorgente pubblico: `gpmerola/deterministic-todo`.
- Repository release Android: `gpmerola/deterministic-todo-releases`.
- Branch operativo: `agent/verify-public-release-token`.
- Android è il primo canale nativo; desktop usa la web app GitHub Pages.
- Release coordinata corrente verificata: 2.18.10 build 82, con avviso Annulla
  del completamento ridotto a due secondi e cancellazioni mantenute a cinque;
  Web, manifest Android e Google Play internal track derivano dal commit
  `5ef280e` e hanno superato il controllo di parità.
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

- installare la 2.19.0 sul Galaxy S21 e concedere posizione precisa e
  notifiche; impostare Batteria → Senza restrizioni per il collaudo Samsung;
- registrare almeno 20 minuti con schermo spento, includendo una sosta, e
  confrontare distanza/GPX con un percorso noto;
- verificare che la notifica termini la sessione e che riaprire l'attività dopo
  una sospensione conservi durata e distanza;
- provare scansione e batteria con Zepp completamente chiusa. Se il servizio
  batteria non è esposto prima dell'autenticazione, non aggirare la protezione;
- implementare in modo indipendente autenticazione Huami e download attività
  solo dopo capture BLE autorizzate sul dispositivo personale; aggiungere
  fixture sintetiche prive di chiave/MAC e test di allineamento timestamp;
- abilitare battito live soltanto dopo conferma sul Bip U reale. Firmware,
  risorse e impostazioni dell'orologio restano fuori ambito.

## P2 — Performance

Misurare prima di ottimizzare ulteriormente:

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
