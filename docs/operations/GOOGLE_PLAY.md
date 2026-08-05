# Distribuzione Google Play

## Stato

- Account sviluppatore: Merola Software, personale.
- App Play Console: `4973696592110383145`.
- Package ID immutabile: `app.deterministic.todo.deterministic_todo`.
- Lingua predefinita: italiano; app gratuita.
- Protezione automatica Play disattivata per conservare il canale APK diretto.
- Test interno attivo dal 5 agosto 2026; lista `Test interno` configurata e
  build 55 (2.16.11) disponibile ai tester autorizzati.

## Firma e transizione

La pipeline coordinata genera APK e AAB dallo stesso commit. Entrambi sono
firmati con la chiave Android conservata nell'environment GitHub
`android-release`; per Play questa è la chiave di upload.

Il flavor `direct` conserva aggiornamento OTA e permesso
`REQUEST_INSTALL_PACKAGES`. Il flavor `play` rimuove quel permesso dal manifest
e disattiva timer e controllo degli aggiornamenti GitHub. Nelle Impostazioni
espone invece `Aggiorna da Google Play`, che apre la scheda ufficiale tramite
`market://` con fallback HTTPS; non apre mai lo Store automaticamente. Non
caricare mai su Play il flavor `direct`.

La chiave privata non è disponibile localmente e non è esportabile dai secret
GitHub. Alla prima configurazione Play App Signing usare quindi la chiave
generata da Google per la distribuzione. La firma Play sarà diversa da quella
degli APK diretti: per passare dall'APK già installato alla build Play occorre
sincronizzare, disinstallare una sola volta e reinstallare dal link di test.
Non tentare un aggiornamento in-place tra i due canali.

## Procedura di release

1. Incrementare versione e build in `pubspec.yaml`.
2. Commit e push avviano `.github/workflows/publish-android-release.yml`.
3. Verificare test, deploy web e parità pubblica.
4. Scaricare `DeterministicTodo-Android.aab` dalla release corrispondente.
5. Caricare l'AAB nel track interno o chiuso di Play Console.
6. Verificare versione, package ID e certificato di upload prima di promuovere.

## Vincolo nuovo account personale

Prima dell'accesso alla produzione Google richiede un test chiuso con almeno
12 tester aderenti per 14 giorni consecutivi. Il test interno è disponibile
subito ma non sostituisce questo requisito. Conservare in Play Console evidenza
dei tester, delle date e del feedback usato nella richiesta di produzione.

## Recovery

Il canale GitHub resta operativo finché la versione Play non è stata collaudata.
In caso di errore Play, non cambiare package ID e non rigenerare la chiave di
upload: correggere l'app, incrementare la build e caricare un nuovo AAB.
