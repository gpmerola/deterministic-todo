# Android: performance, dimensioni e aggiornamenti

## Identità visiva

Le sorgenti canoniche dell'icona sono `assets/branding/app_icon.svg` e
`app_icon_maskable.svg`. I PNG in `android/app/src/main/res/mipmap-*` e
`web/icons/` sono derivati: non vanno ridisegnati separatamente, così Android,
favicon e PWA restano coerenti. Il rosso di marca è `#DB4035`; priorità e stati
di errore mantengono i propri colori semantici. Da Android 8 il launcher usa
`mipmap-anydpi-v26/ic_launcher.xml`: sfondo e primo piano separati evitano il
doppio bordo prodotto dalle maschere Samsung e dagli altri launcher adattivi.

La superficie web espone la stessa icona come favicon SVG, fallback PNG 16/32,
bookmark Chrome, Apple touch icon e icone PWA normali/maskable. Quando cambia
la sorgente canonica, tutte le varianti vanno rigenerate nello stesso commit;
la favicon primaria deve ricevere un nuovo nome per superare la cache dei
bookmark già esistenti.

## Obiettivi e budget

Android è ottimizzato prima per uso offline rapido e poi per dimensione. I budget attuali sono:

- APK per ABI inferiore a 25 MB;
- nessuna rete nel percorso di creazione, modifica o consultazione locale;
- nessun polling continuo quando la sincronizzazione non è configurata;
- un solo controllo leggero del manifest a ogni apertura, oltre al comando manuale;
- nessun caricamento della cronologia completata nelle viste attive;
- nessun plugin, database o servizio per orari e notifiche.
- timeline futura lazy fino a dieci anni, con salto data e senza stream aggiuntivi.

Ogni aumento significativo va misurato e documentato. Flutter porta un costo minimo non eliminabile: ogni APK include motore Flutter, snapshot AOT Dart e librerie native necessarie. Cambiare toolkit potrebbe ridurre il minimo, ma eliminerebbe la base di codice multipiattaforma richiesta.

Dalla 2.17.0 il workflow applica automaticamente il budget ai tre APK per CPU:
una release oltre 25 MiB si ferma prima della pubblicazione. Le regole
`baseline-prof.txt` e `startup-prof.txt` includono il percorso Android di avvio;
vanno rigenerate da hardware reale quando cambia l'embedding Flutter, non
estese a tentativi con classi non osservate.

## Risultati misurati

La build universale 1.0.3 era circa 59 MB perché conteneva tre copie delle librerie native. La build 1.0.4 con `--split-per-abi`, misurata sugli artefatti GitHub Actions, produce:

| ABI | Uso tipico | Dimensione approssimativa |
| --- | --- | ---: |
| `arm64-v8a` | telefoni Android recenti | 21 MB |
| `armeabi-v7a` | telefoni ARM 32 bit | 19 MB |
| `x86_64` | emulatori e pochi dispositivi | 23 MB |
| universale | solo ponte da updater vecchi | 59 MB |

La 2.1.2 aggiunge `--split-debug-info`. La misura ARM64 è passata da 23.609.433 byte nella 2.1.1 a 22.364.249 byte: 1.245.184 byte, circa il 5,3%, rimossi dall’APK installato. Le symbol map compresse occupano circa 3,6 MB nell’artefatto CI privato con scadenza a 30 giorni e non vengono distribuite al dispositivo.

Il client 1.0.4 interroga l’ABI tramite il plugin OTA e seleziona la voce esatta del manifest. L’asset universale non è scelto dai client nuovi e non viene più ricompilato a ogni release. I manifest futuri possono riferirsi al solo universale 1.0.4 come bootstrap per client 1.0.3: dopo quel passaggio il nuovo updater scarica l’ultima ABI specifica.

## Avvio e CPU

Il bootstrap apre Drift su un isolate nativo in background e attiva WAL. Dalla 2.8.0 non registra plugin di notifiche o fusi, non richiede i relativi permessi e non installa receiver al riavvio.

La preparazione di un import Todoist usa `compute`: parsing JSON, validazione e
normalizzazione non competono con il frame UI su Android. Le scritture Drift
restano transazionali sul database e il Web conserva lo stesso contratto.

Il controllo aggiornamenti parte dopo il primo frame, non blocca la UI e memorizza `last_update_check_us` in `app_settings`. I controlli automatici successivi sono saltati per sei ore. Il controllo manuale nelle Impostazioni ignora intenzionalmente questo limite.

Dal flavor Play 2.16.14 il controllo usa `Play App Update 2.1.0` e il flusso
flessibile ufficiale: il prompt compare soltanto se Google Play conferma una
versione più recente, il download non blocca l'app e l'installazione si completa
quando il pacchetto è pronto. La dipendenza è `playImplementation`, quindi APK
diretto e browser non la includono. In caso di API non disponibile, soltanto il
controllo manuale apre la scheda Store come fallback.

Non aggiungere servizi Android persistenti per gli aggiornamenti. La sincronizzazione reagisce a modifica, riconnessione e ritorno in primo piano. Il controllo di sicurezza ogni dieci minuti esiste soltanto mentre l’app è visibile e viene sospeso in background. Per il singolo account personale privilegia la convergenza rapida con una query incrementale economica; Realtime resta il percorso normale immediato. Progetti e sezioni già confermati dal server sono identificati tramite la coppia Lamport `(logical_version, device_id)` e non vengono reinviati finché non cambiano.

Prima del push, l’outbox viene compattata logicamente per `entity_id`: più modifiche pendenti della stessa attività causano un solo `merge_task` della versione finale, mentre tutte le operazioni vengono comunque riconosciute e rimosse soltanto dopo il successo. Il pull carica le attività locali interessate con una sola query SQLite e applica poi il confronto Lamport in memoria, evitando una query per ogni riga remota.

Una nuova riga nell'outbox avvia il sync dopo 120 ms, così più tocchi ravvicinati
restano accorpati. Realtime gestisce il percorso immediato sul dispositivo
ricevente; il controllo completo ogni dieci minuti rimane come recovery. Quando
l'app è in background gli eventi non avviano lavoro e il rientro forza un sync.
Errori, timeout o chiusure di Realtime riaprono il canale dopo due secondi e la
nuova sottoscrizione forza una riconciliazione completa.
Il ricevente raccoglie gli ID per tabella e interroga esclusivamente quei
record; anche import e raffiche di modifiche producono una query per tabella,
non un pull completo per evento.

Gli errori di trasporto temporanei vengono ritentati dopo 2, 10 e 30 secondi,
poi al massimo ogni 2 minuti, esclusivamente in foreground. Pausa e background
annullano il timer. Gli errori strutturali Supabase non generano loop: il loro
codice sicuro resta visibile e nell'outbox, mentre titoli, token e payload non
entrano mai nel messaggio. Le impronte Lamport di tutti i progetti e sezioni
sono lette con una sola query SQLite anziché una query per elemento.

## RAM e query SQLite

`TaskShell` conserva due stream Drift creati una sola volta:

- `watchActive()` esclude tombstone e completate;
- `watchCompleted()` carica esclusivamente la cronologia completata.

Il cambio schermata seleziona lo stream pertinente. Questo evita di tenere in RAM tutta la cronologia durante Oggi, Prossime e Progetti. Gli indici SQLite della migrazione 2 sono:

- `tasks_status_order_idx (deleted_at, status, position, created_at, id)`;
- `tasks_dates_idx (deleted_at, show_date, due_date)`.

Il riordino confronta la posizione desiderata con quella persistita e non scrive né aggiunge outbox per righe già nella posizione corretta. Tutte le scritture necessarie restano transazionali e deterministiche.

## Profilo Galaxy S21

Il Galaxy S21 usa un processore ARM a 64 bit e riceve quindi `android-arm64-v8a`, non il fallback universale. Lo schermo adattivo può arrivare a 120 Hz: l’interfaccia evita timer di animazione decorativa e mantiene liste lazy, così Flutter produce frame solo in risposta a input o cambiamenti dati. Non viene forzato un refresh rate specifico, lasciando ad Android/Samsung la gestione energetica adattiva.

L'animazione di completamento della 2.3.1 dura complessivamente 480 ms ed è avviata esclusivamente dal tocco dell'utente: prima conferma spunta, colore e testo barrato, poi dissolve e sposta la riga. Usa transizioni implicite Flutter, non mantiene ticker o timer a riposo e applica la scrittura SQLite al termine. Le frasi di ricorrenza e le priorità derivano dai campi già caricati nella riga e non aggiungono query.

La 2.4.0 riduce inoltre il numero di widget per riga: priorità sul bordo del checkbox, nessuna azione calendario ripetuta nell'elenco e nessun contatore nei chip dei giorni. L'export calendario resta nell'editor. La risoluzione del contenitore Todoist Inbox esegue una singola query locale all'avvio e non introduce polling.

La 2.5.0 applica la priorità con una decorazione statica leggera e ordina in memoria le sole liste già caricate; non aggiunge query né scritture automatiche. Il composer osserva esclusivamente il cambiamento dell'inset della tastiera mentre è aperto: quando Android nasconde l'IME, chiude nello stesso gesto anche il bottom sheet con reverse animation da 90 ms. Non esistono listener o timer persistenti dopo la chiusura.

La 2.16.8 conserva il massimo inset osservato durante la singola apertura del
composer: può salire insieme alla tastiera, ma non segue più le oscillazioni di
altezza prodotte da suggerimenti, toolbar o passaggi intermedi dell'IME. Quando
l'inset arriva a zero il foglio viene chiuso come prima. Il valore è locale al
foglio e viene rilasciato alla chiusura. La zona della spunta intercetta inoltre
le sole gesture orizzontali che iniziano sul controllo, eliminando la contesa
con lo swipe senza aggiungere listener globali o lavoro a riposo.

La 2.7.0 riduce le transizioni del composer a 80/45 ms e aggiunge il campo descrizione soltanto su richiesta, senza controller, layout o listener persistenti dopo la chiusura. La nuova gerarchia Progetti riusa gli stessi due stream SQLite di progetti e sezioni e non introduce query, polling o dipendenze.

La 2.9.0 riusa lo stesso composer anche dentro Progetti e limita la descrizione nelle liste a una riga, senza aggiungere stream, timer o dipendenze. Lo swipe richiede il 62% della larghezza e funziona soltanto verso sinistra; l'Undo resta disponibile. La semplificazione a una sola data elimina confronti e rami UI duplicati, mentre la colonna legacy resta nullable per un upgrade senza migrazioni distruttive.

La 2.10.0 aggiunge le azioni progetto/sezione usando menu costruiti soltanto all'apertura. Spostamento e archiviazione sono aggiornamenti SQLite puntuali sugli stream esistenti; non introducono dipendenze, polling, query persistenti o cancellazioni a cascata.

La 2.11.0 porta il composer a 30/20 ms, elimina l'animazione del padding IME e riduce le animazioni di editor, completamento e swipe. Prossime usa un solo `ListView.builder` lazy fino a dieci anni: anche i giorni vuoti non vengono materializzati fuori schermo. Completate osserva al massimo 200 righe e archivia oltre 365 giorni. Il controllo release usa un solo timer da sei ore, esegue rete soltanto in foreground ed è protetto da single-flight; un polling ogni dieci minuti è stato escluso perché sproporzionato.

Dalla 2.11.1 ogni richiesta al manifest aggiunge un timestamp e `Cache-Control: no-cache`: GitHub può mantenere brevemente in CDN il redirect `latest`, ma il client non riutilizza più una risposta manifest obsoleta tra due controlli.

La 2.12.0 imposta a zero la durata della route del composer; non aggiunge overlay persistenti o controller globali. Il Cestino riusa stream SQLite filtrati e limita le attività eliminate a 200 righe. I chip link vengono costruiti soltanto quando l'editor e la sezione dettagli sono aperti.

La 2.16.11 riduce da 230 a 140 ms l'attesa complessiva prima del commit di
completamento e accorcia in proporzione spunta, dissolvenza e scorrimento. La
scrittura resta successiva al feedback visivo iniziale, ma la riga libera prima
la lista senza aggiungere controller, timer persistenti o lavoro di database.

La 2.16.13 isola lo stato di sincronizzazione in un solo widget dell'AppBar:
le transizioni `syncing/current/offline` non ricostruiscono più Scaffold,
navigazione e liste. Il composer riusa la cache progetti già acquisita prima
dell'apertura e non esegue una query SQLite al submit. Inbox e cache rapida
condividono inoltre la lettura iniziale dei progetti; l'archiviazione annuale
viene controllata una sola volta per data civile. Il promemoria diagnostico
resta giornaliero ma usa una SnackBar non bloccante.

L’accesso al calendario avviene esclusivamente premendo “Salva + calendario” e crea un evento giornaliero; non introduce servizi, polling, OAuth o processi Google aggiuntivi. La sincronizzazione remota dell’evento è quella già gestita dall’account calendario del telefono.

Per i collaudi senza cavo, pairing, connessione, riconnessione e limiti di ADB
wireless sono documentati in
[`operations/ADB_WIFI.md`](operations/ADB_WIFI.md). Il pairing persistente non
garantisce una sessione sempre connessa: IP e porta vanno trattati come valori
effimeri e mai salvati nel repository.

Il test passivo Movimento è temporaneo e auto-scade dopo sette giorni. Dalla
2.25.5 usa un solo `PeriodicWorkRequest` ogni ora: legge da Health Connect la
giornata corrente e crea un file immutabile
`movement_snapshot_YYYY-MM-DD_HH.json` per fascia oraria. Conserva inoltre il
report definitivo `daily_audit_YYYY-MM-DD.json` del giorno concluso. Il primo
snapshot è pianificato circa un minuto dopo l'avvio e un test già attivo viene
aggiornato automaticamente dalla nuova build. I retry restano affidati a
WorkManager. Non registra GPS, non mantiene un servizio foreground e non usa
BLE; il costo va comunque misurato sul Galaxy S21 prima di rendere permanente
la frequenza di debug.

Dalla 2.25.6 lo stato aggregato dell'ultimo tentativo è interrogabile dalla
shell ADB con il comando canonico documentato in
[`operations/ADB_WIFI.md`](operations/ADB_WIFI.md). Il provider è read-only,
protetto da `android.permission.DUMP` e non rende debuggabile l'APK release.

La 2.25.7 non considera più `STILL` una causa di esclusione quando il sensore
registra passi nello stesso intervallo: quei passi alimentano il fallback
prudente da camminata e restano marcati come conflitto. Veicolo e bicicletta
dominanti restano esclusi e sono misurati separatamente nello schema 4 e nel
provider ADB, insieme alla baseline di distanza su tutti i passi.

## Motion system UI

La 2.16.15 introduce un motion system limitato alle transizioni informative:
140 ms per il cambio schermata/progetto e 110 ms per titolo, data e stato
vuoto. Le animazioni sono fade e traslazioni minime, lavorano in parallelo al
cambio di contenuto e non aggiungono attese alle operazioni. Le righe non
vengono animate durante lo scroll per evitare lavoro GPU e distrazioni.

Il composer rapido resta escluso: `sheetAnimationStyle` mantiene durata e
durata inversa a zero, così il percorso `+` → tastiera → invio non subisce
regressioni.

La 2.17.2 limita a cinque secondi gli annunci con azione e imposta
esplicitamente `persist: false`: Undo e promemoria non restano bloccati quando
il sistema segnala navigazione accessibile. Il pannello dettagli desktop usa
una sola transizione di dimensione da 140 ms e un cambio contenuto da 110 ms;
il composer continua ad avere durata zero.

La 2.17.3 non legge né scrive più una preferenza per l'ultima priorità rapida:
ogni composer nasce in P4, cioè nessuna priorità, e conserva soltanto il
progetto recente. La modifica nel pannello desktop riusa l'editor esistente e
non introduce stream, controller o dipendenze aggiuntive.

La 2.17.4 incorpora lo stesso `TaskEditor` nella colonna desktop: l'istanza vive
soltanto mentre una task è selezionata e viene ricreata quando cambia la sua
versione locale. Non aggiunge query, timer o dipendenze; elimina invece il
secondo passaggio e la seconda route necessari per modificare dal browser.

La 2.17.5 instrada Invio e il pulsante Salva nella stessa funzione dell'editor.
Un flag locale ignora conferme duplicate durante la singola transazione; non
aggiunge timer, listener o lavoro a riposo. Il campo descrizione resta
multilinea e non intercetta Invio.

La 2.18.0 sostituisce il movimento laterale del completamento con una conferma
verde e una dissolvenza di 140 ms; la scrittura avviene dopo la conclusione
visiva, evitando ricostruzioni intermedie della lista. Riferimenti usa un solo
stream SQLite filtrato, attivo soltanto nella relativa sezione, e riusa outbox,
sync e componenti link già presenti: nessun polling, dipendenza o servizio in
background aggiuntivo.

La 2.18.7 riduce il completamento a un solo controllo circolare animato dalla
Checkbox Material, senza cambio di widget, overshoot o tinta dell'intera riga.
La breve conferma precede una contrazione verticale controllata e la scrittura
SQLite: nessun ticker resta attivo e non vengono aggiunte query o dipendenze.
La 2.18.8 porta la sequenza da 430 a 370 ms senza aggiungere animazioni: 200 ms
di conferma e 170 ms di contrazione usano due costanti condivise, evitando che
durata visiva e attesa della persistenza possano divergere.

La 2.18.9 rende esplicito il feedback di pressione riusando il ripple Material
della riga e rimuove icone decorative dagli stati vuoti. Sul Web l'editor resta
montato durante gli aggiornamenti dello stream: evita ricreazione dei controller
e perdita di focus, senza buffer, timer, query o dipendenze aggiuntive.

La 2.18.1 rimuove lo stream dedicato ai Riferimenti insieme alla relativa UI:
gli eventuali record esistenti riusano lo stream attività, senza query o copie.
La migrazione locale elimina anche l'indice del tipo non più interrogato,
riducendo marginalmente spazio e lavoro su ogni scrittura.
Il controllo completo Supabase passa da uno a dieci minuti, riducendo del 90%
i wake-up periodici in foreground senza rallentare Realtime, outbox,
riconnessione o sincronizzazione al resume. Invio fisico nell'editor Web viene
intercettato localmente e non aggiunge listener persistenti globali.

## Telemetria prestazionale locale

Dalla 2.2.0 la diagnostica registra solo sul dispositivo, senza timer o invii esterni:

- `performance_snapshot`: millisecondi di avvio, RAM RSS e, su Android dalla
  2.24.1, PSS totale con ripartizione Java/native/grafica, byte SQLite,
  attività attive/completate e outbox, raccolti ad avvio e cambio
  foreground/background;
- `frame_sample`: media e massimo dei tempi build/raster e frame oltre 16,67 ms, aggregato ogni 600 frame o andando in background per ridurre le scritture;
- `sync_completed`: durata, righe remote, entità effettivamente caricate e progetti/sezioni saltati perché invariati;
- `sync_failed`: tipo/codice tecnico e durata prima dell’errore.
- `update_check`: canale, esito, durata e natura automatica/manuale;
- `interaction_latency`: durata di apertura composer/editor, cambio schermata,
  creazione, modifica e completamento. Non contiene ID, titoli, note o URL.

La 2.16.14 inizializza l'identità auth prima di ascoltare gli eventi Supabase:
la notifica iniziale della stessa sessione non duplica più il primo sync
completo; login e cambio account continuano invece a forzarlo.

La 2.24.1 limita la cache immagini Flutter a 16 MiB e la svuota quando l'app
passa in background. Nello stesso momento rimuove il canale Supabase Realtime;
al resume lo ricrea e avvia il pull completo già previsto, quindi la riduzione
di socket e memoria non introduce finestre di perdita. RSS resta utile per
confrontare il processo nel tempo, ma PSS è la misura primaria per attribuire
al processo pagine condivise in modo proporzionale.

La 2.16.20 sovrappone durante il bootstrap diagnostica, attivazione delle task
pianificate e inizializzazione Supabase. Sul Web il documento precarica
`sqlite3.wasm` e `drift_worker.js` e mostra uno stato HTML immediato prima del
primo frame Flutter. Il report reale del 5–8 agosto 2026 è in
[`diagnostics/2026-08-08-web-android.md`](diagnostics/2026-08-08-web-android.md).

I dati restano in due blocchi rotanti da 512 KiB e si esportano esplicitamente da Impostazioni: file applicativi su Android e IndexedDB nel browser. L'export include sia il blocco precedente sia quello corrente. Non contengono titoli, note, email, URL, token, identificatori di attività o identificatori dispositivo. Ogni riga include versione/build, schema log e un identificatore casuale valido soltanto per l'apertura corrente. La raccolta è event-driven e non mantiene servizi o polling aggiuntivi. Una sola volta per giorno, all’apertura, l’app propone facoltativamente di esportare il file e offre un prompt pronto da copiare; la data dell’ultimo avviso resta locale in `app_settings`.

Dalla 2.24.2 Android pianifica inoltre con WorkManager una copia nella stessa
cartella Drive già autorizzata per i test Movimento. Dalla 2.25.4, durante la
fase di debugging, l'app la aggiorna all'avvio (dopo circa un minuto) e ogni tre
ore quando è disponibile una rete. Il job non richiede che l'app resti aperta;
Android può comunque differirlo secondo le proprie politiche energetiche. Il nome è
`todo_diagnostics_YYYY-MM-DD.jsonl`; la scrittura è idempotente per data e la
retention elimina soltanto i file con quel prefisso oltre i 15 più recenti.
Il lavoro non attiva GPS o BLE e Android può differirlo per risparmiare
batteria. Browser ed esportazione manuale restano invariati.

## Flusso OTA

1. Il client scarica il piccolo `manifest.json` pubblico.
2. Confronta semanticamente la versione installata e quella remota.
3. Su Android individua l’ABI e sceglie l’asset specifico; `android` è soltanto fallback per versioni precedenti.
4. `ota_update` scarica l’APK nella directory interna dell’app senza aprire GitHub.
5. Il client mostra la percentuale e passa lo SHA-256 dichiarato nel manifest.
6. Se l’hash non coincide, l’installazione viene interrotta.
7. Android mostra la conferma di sistema. Un’app normale sideloaded non può installarsi silenziosamente; servirebbero Play Store, MDM o privilegi da app di sistema.
8. L’APK usa un `versionCode` maggiore e la stessa chiave release. SQLite rimane nella directory dati dell’app.

## Firma e segreti

La chiave stabile è generata una sola volta. La copia locale è in `private_release_keys/`, ignorata da Git; GitHub Actions riceve materiale e password attraverso `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD` e `ANDROID_KEY_PASSWORD`. L’alias è `deterministic-todo`.

La perdita della chiave impedisce di aggiornare installazioni esistenti. Eseguire un backup cifrato esterno della directory privata. Non spostare mai password o keystore nel repository, negli artefatti CI o nei log.

## Procedura di ogni release Android

1. Aggiornare versione e build number in `pubspec.yaml` in modo monotono.
2. Aggiornare codice, test e documentazione nello stesso cambiamento.
3. Eseguire `dart format`, `flutter analyze` e `flutter test`.
4. Commit e push su un branch `agent/**`: questo avvia `Publish Android and Web Release`.
5. Il workflow esegue analisi, generazione e test una volta, poi costruisce in parallelo web e APK firmati.
6. Il client web viene distribuito e verificato tramite `release-info.json`; soltanto dopo vengono pubblicati APK e manifest Android.
7. Il controllo finale confronta versione, build e commit pubblici dei due canali,
   oltre a piattaforme, hash e URL degli APK. Anche il fallback universale viene
   ricostruito: nessun collegamento può restare ancorato a una release precedente.
8. Installare sopra la versione precedente su un dispositivo reale e verificare versione e conservazione di un task sentinella.

Il workflow usa esclusivamente `RELEASE_REPO_TOKEN`, un fine-grained token con accesso in scrittura alle release del solo repository pubblico. Non riutilizzare token amministrativi o la chiave Supabase. Ogni modifica funzionale viene collaudata prima su Android: versione e build devono quindi crescere a ogni push pubblicabile. La modalità manuale con conferma `PUBBLICA` resta un fallback di recupero.

Per contenere lavoro duplicato, `Verify` e `Build Android APK` restano manuali. La release coordinata esegue analisi e test una sola volta per entrambi i canali; non esiste più una build nativa macOS. La concurrency annulla build superate da push più recenti.

Dalla 2.16.16 la build web risolve le dipendenze una sola volta, passa
`--no-pub` alla compilazione e salta il dry-run WebAssembly perché il target
distribuito resta JavaScript. Android conserva la risoluzione automatica di
Flutter: disattivarla può lasciare nel registrant release plugin destinati ai
soli test. Firma, test, APK universale e per ABI, AAB Play e controlli di parità
restano invariati.

Il deployment Pages usa il limite massimo di 10 minuti imposto da GitHub.
Questo non allunga le build normali; una coda eccezionalmente più lunga resta
un limite esterno del servizio e richiede un nuovo tentativo di pubblicazione.
Poiché Pages identifica il deployment tramite il commit, dopo una cancellazione
il recovery usa un nuovo commit documentale e rilancia il workflow coordinato:
riutilizzare lo stesso SHA può riferirsi al deployment già annullato.

La stessa versione evita retry artificiali della sincronizzazione: le modifiche
ai soli metadati `attempts` e `last_error` dell'outbox non sono nuovo lavoro. Un
nuovo tentativo avviene soltanto per una nuova operazione, per il timer di retry
con backoff o per il controllo periodico.

## Ottimizzazioni future ammesse

- Profilare un dispositivo reale con Flutter DevTools in modalità profile prima di intervenire sulla UI.
- Paginare Completate se la cronologia supera diverse migliaia di record.
- Spostare la ricerca a query SQL/FTS5 se dataset reali dimostrano latenza misurabile.
- Valutare `--split-debug-info` e offuscamento conservando privatamente le symbol map.
- ~~Valutare `--split-debug-info`~~ attivo dalla 2.1.2: i simboli Dart vengono separati dall’APK e conservati per 30 giorni come artefatto privato della build. L’offuscamento resta escluso finché non è necessario.
- Rimuovere una dipendenza solo dopo aver verificato Android e la build web release.

Non sacrificare firma, hash, persistenza, funzioni corrette o determinismo per guadagni teorici non misurati.

## Audit finale 2.16.8

- startup e composer non attendono rete né query non necessarie sul thread UI;
- nessun servizio Android persistente, polling in background o timer inferiore
  a 15 minuti; retry sync annullati appena l'app va in background;
- stream attivi/completati e liste future restano filtrati o lazy;
- APK ARM64 resta sotto il budget di 25 MB con split ABI e simboli separati;
- rimossa una dipendenza diretta inutilizzata; le altre dipendenze hanno tutte
  un'integrazione applicativa effettiva;
- nessun upgrade major di pacchetti è stato eseguito alla cieca: richiederebbe
  collaudo Android reale e non offre un beneficio prestazionale dimostrato.
