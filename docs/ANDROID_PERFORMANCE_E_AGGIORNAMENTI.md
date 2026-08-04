# Android: performance, dimensioni e aggiornamenti

## Obiettivi e budget

Android è ottimizzato prima per uso offline rapido e poi per dimensione. I budget attuali sono:

- APK per ABI inferiore a 25 MB;
- nessuna rete nel percorso di creazione, modifica o consultazione locale;
- nessun polling continuo quando la sincronizzazione non è configurata;
- un solo controllo leggero del manifest a ogni apertura, oltre al comando manuale;
- nessun caricamento della cronologia completata nelle viste attive;
- nessuna inizializzazione del database completo dei fusi orari finché non viene pianificata una notifica.
- timeline futura lazy fino a dieci anni, con salto data e senza stream aggiuntivi.

Ogni aumento significativo va misurato e documentato. Flutter porta un costo minimo non eliminabile: ogni APK include motore Flutter, snapshot AOT Dart e librerie native necessarie. Cambiare toolkit potrebbe ridurre il minimo, ma eliminerebbe la base di codice multipiattaforma richiesta.

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

Il bootstrap apre Drift su un isolate nativo in background e attiva WAL. Il database dei fusi orari non viene caricato in `main()`: viene inizializzato una sola volta al primo task che richiede una notifica. Anche le richieste dei permessi di notifica sono differite fino a quel momento.

Il controllo aggiornamenti parte dopo il primo frame, non blocca la UI e memorizza `last_update_check_us` in `app_settings`. I controlli automatici successivi sono saltati per sei ore. Il controllo manuale nelle Impostazioni ignora intenzionalmente questo limite.

Non aggiungere servizi Android persistenti per gli aggiornamenti. La sincronizzazione reagisce a modifica, riconnessione e ritorno in primo piano. Il controllo di sicurezza ogni 15 minuti esiste soltanto mentre l’app è visibile e viene sospeso in background. Progetti e sezioni già confermati dal server sono identificati tramite la coppia Lamport `(logical_version, device_id)` e non vengono reinviati finché non cambiano.

Prima del push, l’outbox viene compattata logicamente per `entity_id`: più modifiche pendenti della stessa attività causano un solo `merge_task` della versione finale, mentre tutte le operazioni vengono comunque riconosciute e rimosse soltanto dopo il successo. Il pull carica le attività locali interessate con una sola query SQLite e applica poi il confronto Lamport in memoria, evitando una query per ogni riga remota.

## RAM e query SQLite

`TaskShell` conserva due stream Drift creati una sola volta:

- `watchActive()` esclude tombstone e completate;
- `watchCompleted()` carica esclusivamente la cronologia completata.

Il cambio schermata seleziona lo stream pertinente. Questo evita di tenere in RAM tutta la cronologia durante Inbox, Oggi, Prossime e In attesa. Gli indici SQLite della migrazione 2 sono:

- `tasks_status_order_idx (deleted_at, status, position, created_at, id)`;
- `tasks_dates_idx (deleted_at, show_date, due_date)`.

Il riordino confronta la posizione desiderata con quella persistita e non scrive né aggiunge outbox per righe già nella posizione corretta. Tutte le scritture necessarie restano transazionali e deterministiche.

## Profilo Galaxy S21

Il Galaxy S21 usa un processore ARM a 64 bit e riceve quindi `android-arm64-v8a`, non il fallback universale. Lo schermo adattivo può arrivare a 120 Hz: l’interfaccia evita timer di animazione decorativa e mantiene liste lazy, così Flutter produce frame solo in risposta a input o cambiamenti dati. Non viene forzato un refresh rate specifico, lasciando ad Android/Samsung la gestione energetica adattiva.

L'animazione di completamento della 2.3.1 dura complessivamente 480 ms ed è avviata esclusivamente dal tocco dell'utente: prima conferma spunta, colore e testo barrato, poi dissolve e sposta la riga. Usa transizioni implicite Flutter, non mantiene ticker o timer a riposo e applica la scrittura SQLite al termine. Le frasi di ricorrenza e le priorità derivano dai campi già caricati nella riga e non aggiungono query.

Il fuso IANA viene letto tramite un singolo platform channel soltanto quando si salva una task con ora o si crea una notifica. L’accesso al calendario avviene esclusivamente premendo “Salva + calendario”; non introduce servizi, polling, OAuth o processi Google aggiuntivi. La sincronizzazione remota dell’evento è quella già gestita dall’account calendario del telefono.

## Telemetria prestazionale locale

Dalla 2.2.0 la diagnostica registra solo sul dispositivo, senza timer o invii esterni:

- `performance_snapshot`: millisecondi di avvio, RAM RSS, byte SQLite, attività attive/completate e outbox, raccolti ad avvio e cambio foreground/background;
- `frame_sample`: media e massimo dei tempi build/raster e frame oltre 16,67 ms, emesso ogni 120 frame o andando in background;
- `sync_completed`: durata, righe remote, entità effettivamente caricate e progetti/sezioni saltati perché invariati;
- `sync_failed`: tipo/codice tecnico e durata prima dell’errore.

I dati restano nei due file rotanti da 512 KiB già previsti e si esportano esplicitamente da Impostazioni. Non contengono titoli, note, email, URL, token, identificatori di attività o identificatori dispositivo. La raccolta è event-driven e non mantiene servizi o polling aggiuntivi. Una sola volta per giorno, all’apertura, l’app propone facoltativamente di esportare il file e offre un prompt pronto da copiare; la data dell’ultimo avviso resta locale in `app_settings`.

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
4. Commit e push su un branch `agent/**`: questo avvia automaticamente l'unico percorso CI ordinario, `Publish Android Release`.
5. Il workflow riesegue analisi e test, ricompila con la chiave stabile, calcola SHA-256, pubblica asset e manifest nel repository pubblico e confronta il manifest riscaricato byte per byte.
7. Verificare anche `/releases/latest/download/manifest.json` e la coerenza di versione, URL e hash.
8. Rendere `latest` soltanto dopo la verifica della catena dalla release precedente.
9. Installare sopra la versione precedente su un dispositivo reale e verificare versione e conservazione di un task sentinella.

Il workflow usa esclusivamente `RELEASE_REPO_TOKEN`, un fine-grained token con accesso in scrittura alle release del solo repository pubblico. Non riutilizzare token amministrativi o la chiave Supabase. Ogni modifica funzionale viene collaudata prima su Android: versione e build devono quindi crescere a ogni push pubblicabile. La modalità manuale con conferma `PUBBLICA` resta un fallback di recupero.

Per contenere i minuti GitHub Actions, `Verify`, `Build Android APK` e `Build macOS` non reagiscono ai push o alla PR: sono strumenti manuali. La pubblicazione Android comprende già analisi, test e build, quindi resta l'unica pipeline automatica. La concurrency annulla una build superata da un push più recente. macOS va compilato solo ai checkpoint che richiedono davvero un collaudo desktop.

## Ottimizzazioni future ammesse

- Profilare un dispositivo reale con Flutter DevTools in modalità profile prima di intervenire sulla UI.
- Paginare Completate se la cronologia supera diverse migliaia di record.
- Spostare la ricerca a query SQL/FTS5 se dataset reali dimostrano latenza misurabile.
- Valutare `--split-debug-info` e offuscamento conservando privatamente le symbol map.
- ~~Valutare `--split-debug-info`~~ attivo dalla 2.1.2: i simboli Dart vengono separati dall’APK e conservati per 30 giorni come artefatto privato della build. L’offuscamento resta escluso finché non è necessario.
- Rimuovere una dipendenza solo dopo aver verificato che la funzione non sia richiesta su macOS, Windows o Android.

Non sacrificare firma, hash, persistenza, funzioni corrette o determinismo per guadagni teorici non misurati.
