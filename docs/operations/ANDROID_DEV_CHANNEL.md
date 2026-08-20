# Canale Android rapido di collaudo

## Scopo

Il flavor `dev` produce **Todo Test** con application ID
`app.deterministic.todo.deterministic_todo.dev`. Può convivere con la build
Google Play, che resta il canale stabile, e può essere sostituito in-place via
ADB usando la linea di firma diretta stabile.

I sandbox Android sono intenzionalmente separati. Database Todo e Movimento,
sessione Supabase, Android Keystore, permessi, notifiche e diagnostica di Todo
Test non leggono né modificano quelli della build Play. Disinstallare Todo Test
non elimina i dati della build Play.

## Prima installazione

1. Costruire il flavor con la configurazione Supabase client e la chiave di
   firma diretta locale, entrambe fuori dal repository:

   ```sh
   flutter build apk --release --flavor dev --split-per-abi \
     --dart-define=DISTRIBUTION_CHANNEL=dev \
     --dart-define-from-file=supabase/config.json
   ```

2. Installare sull'arm64 del Galaxy S21:

   ```sh
   adb -s SERIAL install -r \
     build/app/outputs/flutter-apk/app-arm64-v8a-dev-release.apk
   ```

3. Aprire **Todo Test**, autenticarsi a Supabase e attendere il riallineamento
   delle task. Autorizzare Health Connect e scegliere la cartella Drive solo
   se questo è il client che deve eseguire i test Movimento.
4. La chiave Bip U resta nel Keystore della build Play: inserirla nuovamente in
   Todo Test tramite la UI, senza esportarla in file o log.

## Aggiornamenti successivi

Ricostruire e ripetere `adb install -r`. Firma e application ID devono restare
gli stessi. Il comando conserva dati, login, autorizzazioni e chiave Keystore
di Todo Test. Non usare `adb uninstall` come procedura di aggiornamento.

## Passaggio e rollback

- Prima di attivare il monitor passivo o intensivo in Todo Test, fermarlo nella
  build Play. Due client attivi produrrebbero raccolte e upload concorrenti.
- I report già caricati su Drive e tutti i dati locali della build Play restano
  invariati. Non occorre migrare la baseline esistente per conservarla.
- Per tornare al canale stabile, fermare i servizi di Todo Test e riaprire la
  build Play. La promozione di una modifica a Play continua a usare il normale
  bundle firmato da Google Play App Signing.

## Failure mode

Se ADB segnala `INSTALL_FAILED_UPDATE_INCOMPATIBLE`, non disinstallare: si sta
usando una firma diversa da quella della precedente Todo Test. Ricostruire con
la chiave diretta stabile. Se il login non riallinea le task, lasciare intatta
la build Play e diagnosticare Supabase prima di attivare Movimento.
