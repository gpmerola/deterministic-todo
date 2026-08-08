# Distribuzione Google Play

## Stato

- Account sviluppatore: Merola Software, personale.
- App Play Console: `4973696592110383145`.
- Package ID immutabile: `app.deterministic.todo.deterministic_todo`.
- Lingua predefinita: italiano; app gratuita.
- Protezione automatica Play disattivata per conservare il canale APK diretto.
- Test interno attivo dal 5 agosto 2026; lista `Test interno` configurata e
  pubblicazione automatica verificata fino alla build 70 (2.17.4) l'8 agosto
  2026.

## Firma e transizione

La pipeline coordinata genera APK e AAB dallo stesso commit. Entrambi sono
firmati con la chiave Android conservata nell'environment GitHub
`android-release`; per Play questa è la chiave di upload.

Il flavor `direct` conserva aggiornamento OTA e permesso
`REQUEST_INSTALL_PACKAGES`. Il flavor `play` rimuove quel permesso dal manifest
e disattiva timer e controllo degli aggiornamenti GitHub. La build Play usa
invece l'API ufficiale In-App Updates all'avvio e alla ripresa (al massimo ogni
sei ore nella stessa sessione), mostrando il flusso flessibile solo se
necessario. Nelle Impostazioni
espone `Aggiorna da Google Play`; la scheda ufficiale viene aperta solo come
fallback se l'API nativa non è disponibile. L'integrazione è confinata al
source set `android/app/src/play` e alla dipendenza `playImplementation`; non
apre mai lo Store automaticamente. Il fallback manuale usa `market://` e poi
HTTPS. Non caricare mai su Play il flavor `direct`.

La chiave privata non è disponibile localmente e non è esportabile dai secret
GitHub. Alla prima configurazione Play App Signing usare quindi la chiave
generata da Google per la distribuzione. La firma Play sarà diversa da quella
degli APK diretti: per passare dall'APK già installato alla build Play occorre
sincronizzare, disinstallare una sola volta e reinstallare dal link di test.
Non tentare un aggiornamento in-place tra i due canali.

## Pubblicazione automatica

La pipeline pubblica automaticamente l'AAB firmato nel track `internal` solo
dopo che test, build Android e deploy Web sono riusciti. L'identità dedicata
`deterministic-todo-play-publis@deterministic-todo-play-api.iam.gserviceaccount.com`
ha accesso esclusivamente a Deterministic Todo e alle release dei canali di
test: non possiede autorizzazioni di produzione o finanziarie. La credenziale è
conservata soltanto nel secret `PLAY_SERVICE_ACCOUNT_JSON` dell'environment
GitHub `android-release`.

Il job `publish-google-play` è una dipendenza obbligatoria del controllo finale
di parità: una release non risulta completata se Play rifiuta l'AAB. La
produzione resta sempre manuale.

## Procedura di release

1. Incrementare versione e build in `pubspec.yaml`.
2. Commit e push avviano `.github/workflows/publish-android-release.yml`.
3. Verificare test, deploy web e parità pubblica.
4. La pipeline carica automaticamente `DeterministicTodo-Android.aab` nel test
   interno e verifica che Google Play accetti la build.
5. Verificare la disponibilità ai tester prima di promuovere manualmente verso
   un altro canale.

## Vincolo nuovo account personale

Prima dell'accesso alla produzione Google richiede un test chiuso con almeno
12 tester aderenti per 14 giorni consecutivi. Il test interno è disponibile
subito ma non sostituisce questo requisito. Conservare in Play Console evidenza
dei tester, delle date e del feedback usato nella richiesta di produzione.

## Recovery

Il canale GitHub resta operativo finché la versione Play non è stata collaudata.
In caso di errore Play, non cambiare package ID e non rigenerare la chiave di
upload: correggere l'app, incrementare la build e caricare un nuovo AAB.
