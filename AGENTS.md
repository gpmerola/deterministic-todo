# Istruzioni permanenti per gli agenti

Queste regole si applicano a ogni modifica nel repository.

All’inizio di ogni nuova sessione leggere integralmente `TODO_NEXT.md` e
`docs/HANDOFF.md` oltre a questo file: contengono stato reale, blocchi esterni,
priorità, architettura e verifiche ancora mancanti.

Durante una conversazione lunga rileggere `TODO_NEXT.md` indicativamente ogni
5–6 prompt dell'utente e dopo cambi di obiettivo o compattazioni. Completata la
risposta al task corrente, proporre facoltativamente al massimo una voce
pertinente e non bloccata. Non interrompere attività urgenti, non ripetere la
stessa proposta e non suggerire modifiche che contaminino test attivi.

## Obblighi di consegna

- Ogni modifica completata e verificata deve essere committata e pubblicata sul repository GitHub; non lasciare lavoro valido soltanto nella copia locale.
- Usare un branch `agent/*`, pushare il branch e mantenere aggiornata la pull request. Non pushare modifiche non verificate.
- La documentazione fa parte del codice: ogni modifica di comportamento, architettura, schema, build, release o limitazione deve aggiornare nello stesso commit almeno README, `docs/` e/o `CHANGELOG.md` secondo pertinenza.
- Non dichiarare completata una funzione senza analisi statica e test proporzionati. Ogni regressione deterministica deve avere un test.
- Non committare keystore, password, token o chiavi amministrative. La chiave Android resta in `private_release_keys/` e nei GitHub Actions Secrets.

## Android: leggerezza e aggiornamenti

- Sul Galaxy S21 il canale operativo di sviluppo è **Todo Test**, package
  `.dev`, aggiornato via ADB con firma diretta stabile. La build Google Play è
  un fallback installato ma disabilitato e non va riattivato, disinstallato o
  usato per Movimento senza seguire
  `docs/operations/ANDROID_DEV_CHANNEL.md`. Un solo package alla volta può
  eseguire raccolte Movimento.

- Android è il primo canale di collaudo dell'utente: ogni modifica funzionale verificata deve incrementare `version` e `build` in `pubspec.yaml`, essere pubblicata automaticamente come aggiornamento Android e provata sul dispositivo prima di essere considerata conclusa.
- Per consegnare Todo Test usare `make todo-test`: installa via ADB quando un
  dispositivo autorizzato è presente, altrimenti pubblica direttamente dal Mac
  l'APK locale sul manifest rolling. `make todo-test-ci` è solo il fallback
  quando il Mac non può compilare. Non ricreare manualmente questa logica.
- Un push funzionale su un branch `agent/**` avvia il canale rapido Todo Test:
  controlli mirati, APK arm64 `.dev` e manifest rolling dedicato. La release
  stabile coordinata (Play, Web, APK direct e tutte le ABI) è manuale e richiede
  conferma `PUBBLICA`. macOS e Windows nativi non sono target supportati. Non
  riutilizzare mai una versione Android già pubblicata e non affidarsi al solo
  artefatto CI, che non alimenta l'updater.
- Raggruppare modifiche correlate in un incremento Android collaudabile. Non pubblicare commit intermedi incompleti; push ravvicinati annullano la build obsoleta tramite concurrency.
- Android è la piattaforma con priorità massima per dimensione, RAM, CPU, batteria e rapidità percepita. Ogni nuova dipendenza deve essere giustificata e valutata rispetto al costo nell’APK e a runtime.
- Generare sempre APK release separati per ABI con `--split-per-abi`. L’APK universale è ammesso soltanto come fallback di transizione per client vecchi e non deve essere il download normale.
- Il manifest pubblico deve offrire asset `android-arm64-v8a`, `android-armeabi-v7a` e `android-x86_64`, relativi SHA-256 e numeri versione/build monotoni.
- La web app deve mantenere SQLite locale persistente; se Drift seleziona soltanto storage in memoria deve fallire chiaramente. Ogni modifica web va verificata con build release, avvio HTTPS e persistenza dopo refresh.
- Gli aggiornamenti devono essere seamless: controllo non bloccante e limitato nel tempo, download interno all’app, progresso visibile, verifica SHA-256 e una sola conferma Android finale. Non reindirizzare normalmente l’utente a una pagina GitHub.
- Ogni canale deve conservare la propria linea di firma stabile. Google Play App
  Signing e APK diretto non sono intercambiabili in-place: non proporre l'APK
  GitHub a un dispositivo installato da Play. Prima della pubblicazione
  verificare che CI, manifest, `versionCode`, hash, canale e firma siano coerenti.
- Non aggiungere polling frequente, timer non necessari, inizializzazioni pesanti all’avvio o query che caricano cronologie non visibili. Preferire lavoro differito, stream persistenti e query SQLite filtrate/indicizzate.
- Prima di rendere una release `latest`, verificare che la versione attualmente installata possa raggiungerla. Conservare un fallback universale soltanto quando serve a una transizione.

## Determinismo e dati

- La UI usa SQLite locale come fonte di verità e non aspetta mai la rete.
- Non introdurre riordini, riprogrammazioni, completamenti o eliminazioni implicite.
- Il calendario Android è un’integrazione esplicita: SQLite resta fonte di verità. Preferire il calendario Google primario già configurato nel sistema, memorizzare l’ID evento e aggiornare lo stesso evento senza duplicati.
- Usare sempre identificatori IANA del fuso forniti dal sistema operativo; non salvare abbreviazioni ambigue e non usare Google Calendar come fonte dell’ora.
- Preservare versioni Lamport, tombstone, UUID e idempotenza di outbox e ricorrenze.
- Non registrare titoli o note nei log e non introdurre analytics o tracking.

Il riferimento operativo per performance e release Android è `docs/ANDROID_PERFORMANCE_E_AGGIORNAMENTI.md`.
Il comando locale canonico è `make check`; `make check-generated` verifica
separatamente che il codice Drift generato sia aggiornato.

## Modulo movimento e Amazfit

- Sulla rete domestica il Galaxy S21 di collaudo ha la prenotazione DHCP
  `192.168.1.120`; provare per prima cosa `adb connect 192.168.1.120:5555`
  oppure l'alias personale `adbtodo`. La porta 5555 sopravvive ai cambi Wi-Fi
  ma non al riavvio del telefono. Per ripristino, sicurezza e fallback leggere
  integralmente `docs/operations/ADB_WIFI.md`; non salvare MAC, codici di
  pairing o credenziali del router.

- Il codice salute/movimento deve restare confinato in `android/runtracker` e
  nel suo sottile canale Flutter. Non mescolare database, permessi, log o sync
  con il dominio Todo o Supabase.
- Distinguere sempre: passi quotidiani del telefono, distanza quotidiana
  stimata, sessioni GPS esplicite e dati sportivi importati dall’orologio. Non
  presentarli come misure equivalenti o fonderli senza provenienza.
- Il GPS in foreground è ammesso soltanto durante una sessione avviata
  esplicitamente. Il conteggio quotidiano non deve mantenere GPS, BLE o polling
  continuo e deve rispettare i vincoli di batteria Android.
- Conservare timestamp UTC e data civile/fuso di attribuzione; gestire reboot,
  reset del contatore hardware, cambio di giorno e cambio di fuso senza creare
  passi negativi o doppi.
- Dati di posizione, attività e battito sono sensibili e solo locali per
  impostazione predefinita. Non inserirli nei log, nel repository o in
  Supabase; export e condivisione devono essere espliciti.
- L’integrazione Amazfit/Huami resta in sola lettura. Sono vietati firmware,
  reset e scritture rischiose. Non copiare codice Gadgetbridge AGPLv3 nel
  progetto MIT: continuare con implementazione indipendente oppure adottare
  AGPLv3 soltanto dopo una decisione esplicita e documentata.
