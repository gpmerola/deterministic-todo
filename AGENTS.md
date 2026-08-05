# Istruzioni permanenti per gli agenti

Queste regole si applicano a ogni modifica nel repository.

All’inizio di ogni nuova sessione leggere integralmente `TODO_NEXT.md` oltre a questo file: contiene stato reale, blocchi esterni, priorità e verifiche ancora mancanti.

## Obblighi di consegna

- Ogni modifica completata e verificata deve essere committata e pubblicata sul repository GitHub; non lasciare lavoro valido soltanto nella copia locale.
- Usare un branch `agent/*`, pushare il branch e mantenere aggiornata la pull request. Non pushare modifiche non verificate.
- La documentazione fa parte del codice: ogni modifica di comportamento, architettura, schema, build, release o limitazione deve aggiornare nello stesso commit almeno README, `docs/` e/o `COMPLETATO.md` secondo pertinenza.
- Non dichiarare completata una funzione senza analisi statica e test proporzionati. Ogni regressione deterministica deve avere un test.
- Non committare keystore, password, token o chiavi amministrative. La chiave Android resta in `private_release_keys/` e nei GitHub Actions Secrets.

## Android: leggerezza e aggiornamenti

- Android è il primo canale di collaudo dell'utente: ogni modifica funzionale verificata deve incrementare `version` e `build` in `pubspec.yaml`, essere pubblicata automaticamente come aggiornamento Android e provata sul dispositivo prima di essere considerata conclusa.
- Un push funzionale su un branch `agent/**` avvia i due percorsi automatici: verifica/build/pubblicazione Android e verifica/build/deployment web. macOS e Windows nativi non sono target supportati. Non riutilizzare mai una versione Android già pubblicata e non affidarsi al solo artefatto CI, che non alimenta l'updater.
- Raggruppare modifiche correlate in un incremento Android collaudabile. Non pubblicare commit intermedi incompleti; push ravvicinati annullano la build obsoleta tramite concurrency.
- Android è la piattaforma con priorità massima per dimensione, RAM, CPU, batteria e rapidità percepita. Ogni nuova dipendenza deve essere giustificata e valutata rispetto al costo nell’APK e a runtime.
- Generare sempre APK release separati per ABI con `--split-per-abi`. L’APK universale è ammesso soltanto come fallback di transizione per client vecchi e non deve essere il download normale.
- Il manifest pubblico deve offrire asset `android-arm64-v8a`, `android-armeabi-v7a` e `android-x86_64`, relativi SHA-256 e numeri versione/build monotoni.
- La web app deve mantenere SQLite locale persistente; se Drift seleziona soltanto storage in memoria deve fallire chiaramente. Ogni modifica web va verificata con build release, avvio HTTPS e persistenza dopo refresh.
- Gli aggiornamenti devono essere seamless: controllo non bloccante e limitato nel tempo, download interno all’app, progresso visibile, verifica SHA-256 e una sola conferma Android finale. Non reindirizzare normalmente l’utente a una pagina GitHub.
- Tutti gli APK successivi devono essere firmati con la stessa chiave release stabile. Prima della pubblicazione verificare che CI, manifest, `versionCode`, hash e firma siano coerenti.
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
