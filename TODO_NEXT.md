# TODO e handover

## P1 — Revisione interfaccia (5 ottobre 2026, screenshot Galaxy 2217)

Tutti gli 8 punti approvati dall'utente e implementati nella 2.57.0+219.
Verifica sul Galaxy fatta con screenshot di Oggi, Prossime, Agenda in
settimana e mese, e dell'editor. Diagnosi originale:
1. Rosso del marchio come `primary` anche nel tema scuro: link, bottoni,
   bordi, «Salvato sul dispositivo», contatore filtri e Modifica/Elimina
   tutti rossi, indistinguibili da errori.
2. Colori dei calendari saturi e crudi sul tema scuro.
3. Testi troncati: chip del mese, parole spezzate nella settimana, titolo
   «Prossi…».
4. Barra in alto affollata, con anello passi «234» poco chiaro.
5. Barra in basso incoerente nell'Agenda; tre icone simili a calendari.
6. Link lunghi su più righe.
7. Il + copre l'ultima riga; la vista giorno va sotto la barra di sistema.
8. Editor: due chip di data poco chiari.

- [ ] Riscontro dell'utente sulla 219. Nel mese ogni giorno mostra meno
  eventi (orario sopra il titolo), poi «+N»: valutare con lui.
- [x] Build 220: 3 giorni, cascata, orari completi, barre multi-giorno,
  Oggi con numero, icone; verificata su emulatore (AVD `todo_s21`).
- [x] Build 221: inviti con bordo, colori personali, ore compattate, «tra
  N min» con Partecipa, frecce giorno, pressione lunga, creare trascinando;
  verificata su emulatore.
- [ ] Riscontro dell'utente sulla 221–222 sul Galaxy.
- [x] KCL k2473476 aggiunto a Samsung Email (Exchange): eventi di
  ottobre presenti; SLaM resta libero/occupato via Google (verificato
  acceso in Agenda).
- [ ] Facoltativo: k25129662 anche in Samsung Email.
- [x] Build 223: «Canceled:» nascosti; «senza risposta» dalla copia che lo
  sa; filtro dopo l'unione.
- [ ] Web 221 dopo `PUBBLICA`.

## P1 — Agenda dal Web e background, build 213

- [x] Coda Web→telefono, job in background, sovrapposizioni, ricerca senza
  accenti; `make check` verde; 2213 su manifest rolling.
- [x] `202610050001_agenda_requests.sql` applicata e verificata.
- [x] Web 213 pubblicata e verificata.
- [x] Prova reale creazione + eliminazione Web → telefono riuscita.
- [ ] Web: verificare la velocità di caricamento in una finestra visibile:
  la misura automatica era falsata da una scheda nascosta.
- [x] Web 215: ordine della coda (214), «In attesa ·», predefiniti dal telefono
  e «Fuso…» durante il caricamento.
- [x] Galaxy 2215: la copia contiene `main`/`ai`; il + sul Web propone
  `sennar.pierp@gmail.com`.
- [x] Job a trigger e motore headless verificati con app chiusa: creazione
  su Google → copia aggiornata senza aprire Todo (STATUS).
- [x] Galaxy 2217: sessione scaduta rinnovata in background (token ruotato
  e attivo), copia aggiornata senza aprire Todo.
- [x] Conferma dell'utente (5 ottobre 2026): nessuna richiesta di login
  all'apertura.
- [ ] Osservare un giorno di batteria: il job a trigger deve fermarsi
  all'impronta quando non cambia nulla.

## P1 — Agenda sul Web, build 212

- [x] Copia dell'Agenda su Supabase (RPC unica, RLS, sola lettura sul Web).
- [x] Migrazione `202610040001_agenda_mirror` applicata e verificata.
- [x] Web 212 pubblicata dopo `PUBBLICA`; `release-info.json` verificato.
- [x] Prima copia dal Galaxy 2212 caricata il 4 ottobre 2026 alle 14:20 UTC:
  9 calendari, 271 eventi in `agenda_events`.
- [ ] Facoltativo: creazione/modifica dal Web tramite coda eseguita dal
  telefono.

## P1 — Assistente AI, build 205

- [x] Chiave API DeepSeek/Claude nel Keystore, verifica senza contenuti.
- [x] Prima funzione: ✨ Scrivi o detta con DeepSeek (build 206), test verdi.
- [x] Prova reale su 9 note (builds 206–208): troncamento e date inventate
  corretti; nessun elemento creato durante le prove.
- [ ] L'utente sceglie «Nuovi eventi in» e prova una creazione reale (✨ visibile
  in Todo e in Google).
- [ ] Se l'utente non gradisce: cercare «✨» per rimuovere gli elementi creati.

## P1 — Agenda unificata, build 191

- [x] Agenda Android in sola lettura su calendari di sistema, duplicati uniti,
  link Teams/Zoom/Meet, calendari nascondibili; 2191 sul manifest rolling.
- [x] Galaxy 2193 via ADB: Agenda, selettore e unione dei duplicati verificati;
  i due account KCL Outlook sono visibili.
- [x] Vista Mese stile Google Calendar (194–195) verificata sul Galaxy.
- [x] Riapertura istantanea e query nativa unica (196), verificate sul Galaxy.
- [x] SLaM libero/occupato abbonato su Google e sincronizzato sul telefono.
- [x] Filtri (inviti senza risposta, parole) e vista giorno in scala: 197–198.
- [ ] Verificare a video titolo e margine inferiore della vista giorno (198).
- [x] Creazione eventi (199–200): modulo verificato sul Galaxy, salvataggio
  coperto da test; primo salvataggio reale lasciato all'utente.
- [x] Modifica/eliminazione (occorrenza o serie), vista 2 settimane
  predefinita e fuso IANA sempre visibile: 201–202, verificati sul Galaxy.
- [x] Build 203: attività «Mostra in Agenda» (flag locale), vista settimana,
  Ripeti, celle a pallino, ricerca unificata; test verdi.
- [ ] Provare sul Galaxy (con l'utente): vista settimana, un'attività segnata,
  un evento ricorrente creato, ricerca di un evento dalla lente.
- [ ] Prima modifica reale di un evento da parte dell'utente: controllare
  che la sincronizzazione Google/Outlook la carichi senza duplicati.
- [ ] Possibile: scegliere un fuso diverso alla creazione (oggi si usa
  sempre quello del telefono).
- [ ] Valutare unione heydoc/Semble (stesso inizio, titoli diversi) solo se
  l'utente vuole tenerli entrambi visibili.
- [ ] SLaM: condivisione esterna bloccata e pubblicazione solo libero/occupato.
  Proposto all'utente di abbonare l'ICS libero/occupato da Google Calendar.
  Lettura ICS nell'app solo se l'aggiornamento di Google è troppo lento.
- [ ] Provare pulsante Teams e apertura di un evento su una riunione reale.
- [ ] Passo successivo: opzione esplicita per attività "Mostra in agenda"
  (colonna sincronizzata + migrazione Supabase approvata).

## P1 — Movimento archiviato, solo passi, build 190

- [x] Tag/branch `archive/movimento-completo-b189` pubblicati; GPS, Bip U,
  Health Connect, diagnostica e Drive tolti dal build; scheda sostituita dal
  pannello sull'anello; pulizia una tantum dei lavori in background.
- [x] Todo Test 2190 sul manifest rolling; CI verde. Dettagli in STATUS.
- [ ] Installare la 2190 sul Galaxy e verificare: anello e pannello passi,
  nessun job archiviato in `adb shell dumpsys jobscheduler` per il package
  `.dev`, nessuna notifica GPS.
- [ ] Eventuale: aggiungere `--split-debug-info` a `make todo-test` per non
  spedire al telefono ~1,2 MB di simboli Dart.
- [ ] Web non ripubblicata: nessuna modifica rilevante per il browser oltre
  alla rimozione della scheda già nascosta sul Web.

Aggiornato il 3 ottobre 2026. Leggere insieme ad `AGENTS.md` prima di modificare.

## P1 — Pianificazione, Inbox e shell, build 189

- [x] Stato derivato dalla data, viste definite solo in SQL, `due_date` rimossa.
- [x] Inbox senza riconoscimento per nome; **Sposta in Inbox** esplicito.
- [x] Ricerca in SQLite con limite; aggiornamento a mezzanotte; `main.dart` diviso.
- [x] `make check`, migrazione Web 188 → 189 e refresh verificati in Chrome.
- [x] Todo Test 2189 pubblicata; installata dall'utente (non verificata via ADB).
- [ ] Sul Galaxy e sul Web convertire con **Sposta in Inbox** il vecchio
  progetto "Inbox", dopo aver aggiornato entrambi i client.
- [x] Web 189 pubblicata e verificata.
- [ ] Ricaricare le schede Web aperte prima di convertire l'Inbox.
- [ ] Rimuovere `due_date` da Supabase solo con migrazione approvata.
- [ ] Valutare se `LIKE` solo ASCII basta per la ricerca di lettere accentate.

Contratto: [pianificazione e viste](docs/architecture/TODO_PLANNING_MODEL.md).

## P1 — Anteprima descrizione, build 188

- [x] Fino a tre righe di descrizione negli elenchi, righe vuote saltate.
- [x] Build 188 sul manifest rolling Todo Test; CI verde.
- [x] 2188 installata sul Galaxy dall'utente; Web 188 pubblicata e verificata.
- [ ] Riscontro dell'utente sul numero di righe dell'anteprima.
- [x] Ricerca con attive prima delle completate: build 189.
- [ ] Idea UX da valutare: azioni dirette per elementi rifiutati in Problemi di
  sincronizzazione.

## P0 — Invii in blocco e diagnostica divergenza, build 183

- [x] Lettura remota in blocco e ricevute raggruppate: 150 → 52 richieste per 50 modifiche.
- [x] Nessun fetch Realtime per versioni già note; diagnostica `diverged_buckets`.
- [x] Web 183 pubblicata e `release-info.json` verificato; Web 184 dopo `PUBBLICA`.
- [x] Consegna Todo Test 2183, ciclo reale `healthy` e CI verde.
- [ ] Osservare `diverged_buckets` su più cicli reali prima di progettare una riparazione.
- [x] Build 184: pausa applicata anche se l'app va in background durante l'avvio.
- [x] Causa reale dei cicli falliti a schermo spento: ripresa di ~1 s allo
  sblocco; build 185 annulla il controllo in sola lettura alla pausa.
- [x] Build 186: pausa legata al binding, non ai frame; la 184 non poteva agire
  su un avvio in background.
- [x] Build 187: listener prima di `start()`, che rispetta la pausa.
- [x] Galaxy 2187: avvio a schermo spento senza cicli, ripresa breve riuscita,
  nessun ciclo in background per sei minuti.
- [x] Web 187 pubblicata e verificata.
- [ ] Ricaricare le schede Web e verificare convergenza con la 2187.

## P0 — Ciclo di vita e ricerca, build 182

- [x] Ricerca senza ricarica per carattere; pausa solo in background reale.
- [x] Invio immediato alla pausa, niente sync in background per cambi rete.
- [x] Indicatore neutro per un retry transitorio già programmato.
- [ ] Consegna Todo Test e verifica sul Galaxy; Web dopo conferma `PUBBLICA`.
- [x] Incremento successivo realizzato nella build 183.

## P0 — Isolamento errori sync, build 181

- [x] Isolare i rifiuti server per singola entità; Realtime a lotti con fallback.
- [x] Snapshot fresco dopo la sottoscrizione Realtime; regressioni dedicate.
- [x] Consegna Todo Test 2181 e ciclo reale sul Galaxy; CI verde. Dettagli in [STATUS](STATUS.md).
- [x] Web 181 pubblicata e `release-info.json` verificato.
- [ ] Ricaricare le schede Web aperte e verificare convergenza con la 2181.

Contratto: [sincronizzazione e storico](docs/architecture/TODO_SYNC_AND_HISTORY.md).

## P0 — Recupero conflitto dopo ripristino, build 180

- [x] Riprodurre il blocco causato da un vecchio invio incerto prima del ripristino.
- [x] Correggere la precedenza dell'ultima scelta e aggiungere regressioni.
- [x] Verifiche locali, installazione Todo Test e recupero reale: coda zero e zero conflitti.
- [x] Rolling e CI verificate; disponibilità Web separata in [STATUS](STATUS.md).
- [x] Correggere la policy del branch Pages e pubblicare Web 180; diagnosi e recovery in [RELEASE](docs/operations/RELEASE.md).

## P0 — Paginazione sync, build 179

- [x] Riprodurre il difetto reale di ordine/cursore con server sintetico corretto.
- [x] Correggere ordine, guardie di pagina e diagnostica di scansione/conflitti.
- [x] Completare verifiche locali e build Android/Web; stato in [STATUS](STATUS.md).
- [x] Verificare consegna rolling Todo Test e CI.
- [x] Verificare sul Galaxy la 2179 installata e un ciclo riuscito; ADB Tailscale ripristinato.
- [x] Verificare recupero dell’errore serale di rinnovo sessione; dettagli in [STATUS](STATUS.md).
- [x] Pubblicare Web, APK diretti e Play interno dopo conferma `PUBBLICA`; parità verificata.
- [ ] Verificare la convergenza reale dopo aggiornamento Android e refresh Web.
- [ ] Confrontare lo storico Android della singola attività; ADB ora disponibile.

Contratto: [paginazione sync](docs/architecture/TODO_SYNC_PAGINATION.md).

## P0 — Controllo unificato, build 178

- [x] RPC unica, cache SQLite transazionale, applicazione aggregata delle cancellazioni.
- [x] Test locali e Galaxy; migrazione server 004 applicata dopo consenso specifico.
- [x] Misurare il ciclo reale e distinguere rete, confronto e cancellazioni.
- [x] Pubblicare il branch verificato e controllare il manifest Todo Test.

Contratto e recovery: [sincronizzazione compatta](docs/architecture/TODO_SYNC_PERFORMANCE.md).
Esiti misurati: [STATUS](STATUS.md).

## P0 — Lentezza sincronizzazione APK, build 177

- [x] Confronto compatto delle versioni, merge SQLite aggregato e controlli sovrapposti condivisi.
- [x] Test locali e Galaxy con 20.000 attività sintetiche.
- [x] Applicare la migrazione server 003 dopo approvazione specifica e misurare il nuovo ciclo reale.
- [x] Pubblicare il branch verificato e controllare il manifest Todo Test.

Contratto: [sincronizzazione compatta](docs/architecture/TODO_SYNC_PERFORMANCE.md).
Esiti e limiti: [STATUS](STATUS.md).

## P0 — Todo UX e sincronizzazione, build 174

- [x] Implementare editor, bozze, viste filtrate, intenti progetti/sezioni,
  paginazione e isolamento dei conflitti.
- [x] Completare collaudo Galaxy e confronto browser/telefono con fixture.
- [x] Applicare le migrazioni del cestino e dei privilegi dopo autorizzazione.
- [x] Pubblicare Web, APK diretti e Play interno dopo conferma `PUBBLICA`.
- [x] Verificare un nuovo ciclo cloud dopo la migrazione sul Galaxy.
- [ ] Completare la convergenza Android–Web con account reale e client aggiornati.
- [x] Build 175: backup/ripristino JSON completo, gestione delle richieste
  obsolete e stream outbox leggero con indice per entità/operazione.
  Contratto e limiti: [backup e lifecycle](docs/architecture/TODO_BACKUP_AND_LIFECYCLE.md).


Contratto: [Todo UX hardening](docs/architecture/TODO_UX_HARDENING.md).
Esiti e limiti correnti: [STATUS](STATUS.md). Movimento escluso da questo task.

## P0 — Sincronizzazione e storico, build 172

- [x] Eliminare le scritture di cambio giorno e il rebase dell'intera attività.
- [x] Introdurre revisioni locali, protezione dei retry e ripristino esplicito.
- [x] Distribuire la build Web 172: pipeline coordinata e identità pubblica
  verificate. I browser devono ricaricare per usare il nuovo client.
- [ ] Collaudare la sincronizzazione Android↔Web con la 172 su entrambi i client.
- [ ] Osservare una mattina reale conservando le nuove revisioni. Stato delle verifiche in [STATUS](STATUS.md), contratto in
  [sincronizzazione e storico](docs/architecture/TODO_SYNC_AND_HISTORY.md).

## Archiviato — Movimento autonomo, solo telefono

Superato dalla build 190: resta solo il contapassi
([Movimento archiviato](docs/archive/MOVIMENTO.md)). Le voci aperte qui e i
collaudi Bip U, Drive e confronto Fit sotto non sono più applicabili.

Riscontri e piano canonico: [MOVEMENT_AUTONOMY](docs/archive/MOVEMENT_AUTONOMY.md).

- [x] Build 173: lettura ADB locale dei minuti per confronti su intervalli
  espliciti; contratto e limiti in MOVEMENT_AUTONOMY, collaudo in STATUS.
- [x] Primo incremento 169: regressioni automatiche e installazione ADB;
  verificata l'esposizione dello stato tecnico sul Galaxy.
- [x] Build 170: raccolta Recording API, import Room idempotente, classificazione
  locale, integrazione distanza GPS e profilo peso/passo; verifiche automatiche.
- [ ] Collaudare la 170 su giornate reali e misurare consumo a riposo; affinare
  cadenza e calorie soltanto dopo la validazione del modello iniziale.
- [ ] Confrontare camminata/corsa con passi contati e distanza nota, in una
  prova dedicata senza Fit e senza diagnostica intensiva. Non assumere che gli
  esperimenti storici sotto siano ancora attivi: stato corrente in STATUS.

Handoff completo, architettura corrente e prossimo obiettivo movimento:
[`docs/HANDOFF.md`](docs/HANDOFF.md). Questo file resta la checklist sintetica;
non duplicare qui i dettagli tecnici.

## Prossimi collaudi build 164–168

- [ ] Build 168: in Todo Test e Web, togliere la data a una fixture sintetica
  di progetto con **Senza data** e con la X, salvare e riaprire. Verificare che
  rimanga nel progetto, fuori da Oggi/Prossime, anche dopo un’altra modifica.
  Il difetto di persistenza Chrome osservato nella 168 è stato riprodotto e
  corretto nella 172; stato corrente in [STATUS.md](STATUS.md).
  La release Web 2.35.3+168 è pubblicata e verificata dalla pipeline; resta
  soltanto il collaudo manuale della persistenza sul profilo Chrome reale.

- [x] Importazione Bip U headless reale: 4.263 campioni minuto, finestra 168
  ore, esito `activity_sync_success`, GATT chiuso dopo circa 18 secondi.
- [ ] Verificare il primo avvio naturale del worker dopo circa tre ore, senza
  trigger ADB, e confermare che una seconda importazione sovrapposta inserisca
  soltanto campioni nuovi.
- [x] Build 160: import incrementale dei minuti recenti Bip U con upsert
  monotono. Una ripubblicazione aggiorna il record soltanto se contiene più
  passi; duplicati e valori regressivi non vengono sommati.
- [x] Build 161: un cursore più vecchio di 12 ore abbandona la vecchia ora di
  sovrapposizione e recupera prioritariamente la finestra recente di 12 ore.
  Collaudo Galaxy superato: 720 minuti nuovi e 3.303 passi in circa 11 secondi.
- [x] Build 163: il cambio giorno non attribuisce più al nuovo giorno il delta
  dall'ultimo campione precedente. Collaudo Galaxy: 2.705 passi errati corretti
  a zero; monitor passivo attivo e successivo snapshot Drive `success/ok`.
- [ ] Build 164: verificare almeno una giornata completa del confronto davvero
  indipendente. Nel report schema 9 `todo.source` deve essere locale,
  `google_fit.role` deve essere `independent_reference_only` e i due totali non
  devono essere derivati dagli stessi record Health Connect.
- [ ] Build 166: verificare su Web e Todo Test che **Impostazioni → Attività
  senza data** elenchi soltanto elementi attivi con data nulla e che rimozione
  singola/collettiva converga sugli altri dispositivi senza ricomparire.
- [ ] Build 167: verificare che Inbox escluda i backlog assegnati ai progetti e
  che **Svuota cestino** rimuova definitivamente task, progetti e sezioni dopo
  aver sincronizzato tutti i dispositivi.

- [-] Superato dalla build 190 (Movimento archiviato). Lasciare invariato il collaudo Movimento iniziato con la build 153 e
  proseguito sulla 154: aprire la nuova build una volta e non usare upload
  manuali. Verificare almeno due aggiornamenti automatici alternati di
  `diagnostics_last_7_days_{a,b}.json`; un errore SAF riconciliato deve
  incrementare `provider_write_reconciled_count`, mentre un fallimento reale
  non deve più portare il job periodico nel backoff WorkManager di cinque ore.
- [ ] Al prossimo avviso Todo, non forzare retry ripetuti: attendere il recupero
  ordinario e leggere lo stato sicuro con il provider ADB `todo_sync_debug`.
  Verificare fase, classe errore, rete/sessione, outbox, retry e successivo
  `sync_recovered` senza ispezionare il database personale.

## Stato corrente

- Repository sorgente pubblico: `gpmerola/deterministic-todo`.
- Repository release Android: `gpmerola/deterministic-todo-releases`.
- Branch operativo: `agent/todo-ux-sync-hardening`.
- Android è il primo canale nativo; desktop usa la web app GitHub Pages.
- Release Todo Test installata e stato dei monitor: fonte corrente [STATUS](STATUS.md).
  **Todo Test** (`.dev`) è il solo client operativo sul Galaxy S21.
  La build Play 121 resta installata con dati intatti ma è
  `disabled-user`. Drive separa automaticamente
  cinque categorie e la prova Bip U esporta un report JSON sicuro. La prova
  preferisce il dispositivo già associato e usa la scansione BLE come fallback.
  Gli ID SAF delle sottocartelle sono persistenti dalla 121, perché la cache
  del provider Drive aveva causato directory omonime nella 120. Movimento include una
  diagnostica intensiva temporanea di sette giorni, segmentata per build e con
  upload JSONL orario e finale crash-safe, oltre agli snapshot
  cumulativi Todo/Google Fit ogni ora; la diagnostica generale Android conserva
  sette giorni locali e alterna due bundle Drive ogni tre ore o su comando. Il sync task usa intenti per campo, scritture
  condizionali e conferma prima dell'ack; il rebase completo è stato eliminato. Dalla build 154 ogni incidente Todo registra fase,
  classe tecnica, rete/sessione, outbox, retry e recupero ed è leggibile in
  sicurezza anche via provider ADB protetto. I record passi sono ripartiti
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
- dalla 144 lo stesso comando conserva nomi stabili durante i retry e il report
  unificato schema 6 non può sparire silenziosamente: numeri non finiti sono
  normalizzati e un errore di generazione produce un fallback tecnico sicuro;
- dalla 145 il backlog intensivo è gestito esclusivamente da un worker dedicato:
  nel comando manuale parte con due minuti di ritardo e non può più precedere o
  bloccare snapshot, log generale e report unificato;
- dalla 146 il report manuale parte subito fuori da WorkManager e mantiene un
  fallback persistente dopo un minuto; il totale passi visibile si riconcilia
  ogni 30 secondi soltanto mentre l'app è in foreground;
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
  `daily_audit_*.json` schema 9: sorgenti Todo/Fit/Bip separate, episodi e
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

- il contatore hardware quotidiano e quello diretto di sessione sono verificati
  sul Galaxy S21; la build 164 elimina Health Connect dalla sorgente Todo e lo
  conserva soltanto per il riferimento Google Fit;
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
