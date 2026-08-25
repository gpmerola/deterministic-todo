# TODO e handover

Aggiornato il 22 agosto 2026. Leggere insieme ad `AGENTS.md` prima di modificare.

Handoff completo, architettura corrente e prossimo obiettivo movimento:
[`docs/HANDOFF.md`](docs/HANDOFF.md). Questo file resta la checklist sintetica;
non duplicare qui i dettagli tecnici.

## Stato corrente

- Repository sorgente pubblico: `gpmerola/deterministic-todo`.
- Repository release Android: `gpmerola/deterministic-todo-releases`.
- Branch operativo: `agent/verify-public-release-token`.
- Android è il primo canale nativo; desktop usa la web app GitHub Pages.
- Release Todo Test preparata: 2.31.2 build 143. **Todo Test** (`.dev`) è il
  solo client operativo sul Galaxy S21; monitor passivo e diagnostica intensiva
  sono attivi. La build Play 121 resta installata con dati intatti ma è
  `disabled-user`. Drive separa automaticamente
  cinque categorie e la prova Bip U esporta un report JSON sicuro. La prova
  preferisce il dispositivo già associato e usa la scansione BLE come fallback.
  Gli ID SAF delle sottocartelle sono persistenti dalla 121, perché la cache
  del provider Drive aveva causato directory omonime nella 120. Movimento include una
  diagnostica intensiva temporanea di sette giorni, segmentata per build e con
  upload JSONL orario e finale crash-safe, oltre agli snapshot
  cumulativi Todo/Google Fit ogni ora; la diagnostica Android
  aggiorna il file Drive giornaliero all'avvio e ogni ora. Il sync task conferma sul
  server ogni versione prima di svuotare l'outbox e ribasa automaticamente i
  contatori Lamport più alti. I record passi sono ripartiti
  sull'intero intervallo e l'esclusione di veicolo/bicicletta richiede una quota
  temporale almeno dell'80%; la finestra passiva resta di sette giorni. La base funzionale build 95 ha
  superato Web, manifest Android, Google Play interno e controllo di parità;
  la 96 consolida codice, test e documentazione senza cambiare l'algoritmo.
- La build 133 stabilizza il primo fix coerente dopo un riaggancio GPS senza
  aggiungerne il segmento e impedisce alle sessioni con oltre il 20% di passi
  a cadenza diversa dall'etichetta di calibrare la falcata. Il prossimo test
  utile è una corsa prevalentemente continua, lasciando attivi monitor passivo
  e diagnostica.
- La build 134 mantiene per le ultime 15 sessioni un unico export a tre fonti,
  con timeline UTC Todo/Bip, aggregati Fit, confronti a coppie e campioni Bip
  unici. Il backfill Bip recupera fino a sette giorni con sovrapposizione.
- La build 135 rende analizzabili gli intervalli passivi brevi tramite timeline
  al minuto e rende osservabili sync Bip incompleti e gap intensivi. Il prossimo
  test utile è una camminata passiva con orari noti, senza sessione manuale.
- Sul Galaxy S21 coesistono **Todo Test** attiva e la
  **build Play 121** disabilitata. Non disinstallare la seconda e non usare
  l'APK GitHub per aggiornarla. Runbook canonico:
  [`docs/operations/ANDROID_DEV_CHANNEL.md`](docs/operations/ANDROID_DEV_CHANNEL.md).
- Telefono principale: Samsung Galaxy S21, `arm64-v8a`.
- Lo stato dell'ultimo snapshot operativo è leggibile in sicurezza con
  `adb shell content query --uri content://app.deterministic.todo.deterministic_todo.dev.movement_debug/status`.
- Supabase reale e convergenza Android↔cloud sono già stati provati.

## P0 — Ultimi collaudi browser

La procedura canonica e la fixture sintetica sono descritte in
[`docs/operations/WEB.md`](docs/operations/WEB.md). I test automatici non
sostituiscono la riapertura sul profilo Chrome reale.

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

## P1 — Canale Android rapido di collaudo

- dalla build 123 il flavor `dev` usa il package distinto `.dev` ed è
  installabile come **Todo Test** accanto alla versione Play;
- dalla 128 il manifest pubblico contiene APK `android-dev-*`; l'updater Todo
  Test non può più selezionare gli APK della linea principale;
- dalla 129 i push `agent/**` pubblicano soltanto Todo Test arm64 sul manifest
  rolling `todo-test-latest`; Play/Web/direct multi-ABI usano la pipeline
  stabile manuale e non bloccano più il collaudo;
- dalla 130 la pipeline calcola sempre `versionCode = 2000 + build`; la 129 è
  stata installata localmente come 2129 dopo che Android aveva rifiutato
  prudentemente il primo APK CI con valore 129;
- `make todo-test` è il comando canonico: ADB locale se disponibile, altrimenti
  upload diretto del build Mac; Actions resta il fallback non interattivo;
- dalla 131 il recupero manuale usa un solo pulsante per GPX, diagnostica e
  riprogrammazione Fit; i retry Fit identici sono idempotenti su Drive;
- dalla 132 l’updater normalizza `-dev`, confronta la build logica e ricontrolla
  il package installato prima del download, impedendo downgrade da manifest
  rolling in ritardo;
- dalla 143 il caricamento manuale avvia snapshot passivo e diagnostica
  generale come rami WorkManager indipendenti: un retry Health Connect/Drive
  del primo non impedisce più log grezzi e report unificato;
- login Supabase, Health Connect, cartella Drive e aggiornamento ADB in-place
  sono collaudati; mantenere invariata la firma diretta;
- Movimento è attivo soltanto in Todo Test; Play resta `disabled-user`;
- non implementare condivisione implicita di database, dati sanitari o chiavi
  fra package. I segmenti storici Play restano su Drive.

## P0 — Collaudo movimento Todo Test build 123

- lasciare attivi diagnostica intensiva e test passivo già avviati su Todo
  Test; la notifica permanente conferma il servizio;
- usare normalmente il telefono. Non servono soste annotate, screenshot o
  sessioni manuali; dopo circa un'ora verificare su Drive un file
  `intensive_<experiment>_<segment>_*.jsonl`;
- gli aggiornamenti intermedi non azzerano i sette giorni: aprire una volta
  l'app dopo ciascun update. Versione e segmento nei file separano i periodi;
- terminare dal pulsante o dalla notifica soltanto se consumo/temperatura sono
  problematici. Alla scadenza il servizio si arresta automaticamente;

- lasciare attivo il test passivo già avviato e raccogliere almeno due giorni
  normali, principalmente camminata e corsa, senza premere altri comandi;
- quando serve anticipare un controllo remoto usare soltanto `Carica ora tutti
  i dati di test`; non usare `Sincronizza ultima attività`, che resta limitato
  alla sessione GPS esplicita più recente;
- verificare sulla build 142 che l'anello passi sia leggibile nelle viste
  principali, che il target cambi dalle Impostazioni e che Movimento integrato
  consenta avvio/stop/upload senza redirect o scorrimento anomalo;
- verificare via provider ADB e nei nuovi `movement_snapshot_*.json` /
  `daily_audit_*.json` schema 8: timeline Todo/Fit/Bip al minuto, episodi e
  pause automatici, copertura/ritardi, delta tra snapshot, scarto distanza, quote
  cammino/corsa/incerte, record grezzi e riconciliazione, esclusi
  veicolo/bicicletta, conflitti `STILL + passi` e flag di qualità;
- verificare che nessun nuovo file Drive resti a 0 byte e che il report
  unificato schema 5 mostri fasi JSON strutturate, ultimo upload concluso,
  smaltimento della coda intensiva, CPU/rete normalizzate, delta PSS e stato
  Bip esplicito;
- per calibrare, registrare quando comodo tre camminate da almeno 1 km e tre
  corse da almeno 3 km con i pulsanti dedicati. Non servono soste annotate né
  screenshot: GPX, passi, confronto e report vengono esportati automaticamente;
- confrontare dopo il terzo campione le falcate applicate e lo scarto rispetto
  a Google Fit; non modificare manualmente le soglie durante la raccolta.

## P1 — Collaudo corsa Bip U

- la build 124 ha superato il precedente GATT 6: prova reale completa con
  autenticazione challenge-response, 7 campioni tra 67 e 73 bpm (media 70),
  stop automatico, GATT 0 e report schema 2 in `05 Bip U`;
- la build 134 usa un’importazione locale idempotente incrementale, con un'ora
  di sovrapposizione, fino a sette giorni di backfill e senza ACK distruttivo;
- il primo test reale ha ricevuto 1.440 campioni/11.520 byte senza errori GATT;
  la 126 ha poi salvato 1.440 minuti, 2.626 passi e 358 campioni cardiaci. Il
  retry ha deduplicato l’intersezione e inserito solo due minuti nuovi;
- la 134 esporta ogni ora riepilogo unificato e report sessione canonico a tre
  fonti con finestre UTC, dati Bip nativi e differenze a coppie. L'import
  dell'orologio resta esplicito e non mantiene una connessione BLE permanente;
- prossimo incremento: stimare offset/drift temporale e validare la qualità dei
  campioni Bip prima di usarli nell'algoritmo mostrato all’utente;
- prossimo passo: integrare una sessione cardiaca esplicita nell'attività e
  verificarne continuità, consumo e timestamp, mantenendo la misura disattiva
  fuori da una sessione richiesta dall'utente;
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
- aggiungere UI del profilo locale per peso e visibilità delle due falcate; la
  calibrazione automatica GPS è presente dalla build 108 e i fallback restano
  provvisori;
- collaudare `TYPE_STEP_COUNTER` durante sessioni con schermo spento; la
  gestione del totale quotidiano attraverso mezzanotte/reboot resta distinta;
- misurare il costo reale del job WorkManager orario temporaneo prima di
  scegliere la frequenza definitiva; il conteggio di sistema non richiede
  polling dell'app;
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
3. eseguire `make check-generated`, `make check`, le build release e i
   controlli Android pertinenti;
4. commit e push sul branch `agent/*`;
5. attendere e verificare entrambe le pipeline automatiche;
6. collaudare fisicamente Android e, per cambi web, refresh/persistenza in
   Chrome sul sito pubblicato.
