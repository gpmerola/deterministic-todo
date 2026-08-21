# Canale Android rapido di collaudo

## Regola operativa corrente

Sul Galaxy S21 esistono intenzionalmente **due installazioni diverse**. Non
sono due versioni aggiornabili l'una sopra l'altra e non condividono il sandbox
Android.

| Ruolo | Nome nel launcher | Application ID | Firma/aggiornamento | Stato d'uso |
|---|---|---|---|---|
| sviluppo quotidiano | **Todo Test** | `app.deterministic.todo.deterministic_todo.dev` | firma diretta stabile; `adb install -r` | **unico client attivo** |
| fallback stabile | **Deterministic Todo** | `app.deterministic.todo.deterministic_todo` | Google Play App Signing; Play Store | installato ma `disabled-user` |

Dal 21 agosto 2026 Todo Test è l'unica app da aprire e l'unica autorizzata a
eseguire monitor passivo, diagnostica intensiva, GPS, Health Connect, Drive e
Bip U. La build Play non va disinstallata: conserva database, configurazione e
Keystore storici ed è un rollback recuperabile.

## Scopo

Il flavor `dev` produce **Todo Test** con application ID
`app.deterministic.todo.deterministic_todo.dev`. Può convivere con la build
Google Play, che resta il canale stabile, e può essere sostituito in-place via
ADB usando la linea di firma diretta stabile.

I sandbox Android sono intenzionalmente separati. Database Todo e Movimento,
sessione Supabase, Android Keystore, permessi, notifiche e diagnostica di Todo
Test non leggono né modificano quelli della build Play. Disinstallare Todo Test
non elimina i dati della build Play.

La parola “allineate” ha una semantica precisa:

- le attività Todo convergono attraverso Supabase quando ciascun client è
  abilitato, aperto e autenticato; i database SQLite non sono condivisi;
- Movimento, diagnostica, permessi SAF/Health Connect e chiavi Keystore **non
  vengono sincronizzati** fra le app;
- i report Movimento storici della build Play restano immutabili su Drive e i
  nuovi report di Todo Test usano la stessa cartella principale. L'analisi può
  concatenare temporalmente i segmenti, ma non li importa nel database `.dev`;
- la chiave Huami deve essere inserita separatamente tramite UI e non deve mai
  essere copiata con ADB, file, log o repository.

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

La cartella SAF da selezionare è la radice **Deterministic Todo Movement
Tests**, non `01 Sessions`, `02 Passive`, `03 Intensive`, `04 App diagnostics`,
`05 Bip U` né `00 Archive pre-build-120`. Le sottocartelle vengono risolte o
create automaticamente.

## Aggiornamenti successivi

Dalla build 128 il manifest pubblico contiene asset `android-dev-*` firmati e
con package `.dev`. L'updater di Todo Test seleziona esclusivamente questi
asset e rifiuta implicitamente il fallback `android-*` della linea principale:
questo evita l'errore Android “package conflicts with an existing package”.

L'aggiornamento in-app è il percorso normale e conserva dati, login,
autorizzazioni e chiave Keystore. `adb install -r` con l'APK `dev` resta un
fallback rapido. Non usare `adb uninstall` e non tentare di installare un APK
`DeterministicTodo-Android-*` dentro Todo Test.

Dalla build 129 Todo Test usa il manifest rolling dedicato:

`releases/download/todo-test-latest/manifest.json`

Ogni push sul branch operativo costruisce soltanto l'APK arm64 necessario al
Galaxy S21 e lo pubblica nella prerelease `todo-test-latest`. La pipeline
stabile non parte più automaticamente: richiede `workflow_dispatch` e la
conferma `PUBBLICA`, poi costruisce Web, Google Play, APK direct e tutte le ABI.
La build 128 è l'unico ponte che permette alla vecchia 126 di passare dal
manifest stabile a quello rapido.

## Passaggio e rollback

- Prima di attivare il monitor passivo o intensivo in Todo Test, fermarlo nella
  build Play. Due client attivi produrrebbero raccolte e upload concorrenti.
- I report già caricati su Drive e tutti i dati locali della build Play restano
  invariati. Non occorre migrare la baseline esistente per conservarla.
- Per tornare al canale stabile, fermare i servizi di Todo Test e riaprire la
  build Play. La promozione di una modifica a Play continua a usare il normale
  bundle firmato da Google Play App Signing.

### Disabilitare Play senza perdere dati

Dopo avere fermato monitor passivo e diagnostica intensiva nella build Play:

```sh
adb -s SERIAL shell pm disable-user --user 0 \
  app.deterministic.todo.deterministic_todo
```

Lo stato atteso è `disabled-user` / `enabled=3`. Questo rimuove l'app dal
launcher e impedisce processi e job, ma conserva package e directory dati. Non
usare `adb uninstall`, “Clear data” o la disinstallazione Play.

### Ripristinare temporaneamente Play

Prima fermare ogni raccolta Movimento in Todo Test, quindi:

```sh
adb -s SERIAL shell pm enable app.deterministic.todo.deterministic_todo
```

Aprire la build Play, attendere la convergenza Supabase e usare Movimento in
un solo client. Riabilitare Play non trasferisce automaticamente diagnostica o
chiavi da Todo Test. Per tornare allo sviluppo, fermare nuovamente i servizi
Play e ripetere `pm disable-user`.

## Failure mode

Se ADB segnala `INSTALL_FAILED_UPDATE_INCOMPATIBLE`, non disinstallare: si sta
usando una firma diversa da quella della precedente Todo Test. Ricostruire con
la chiave diretta stabile. Se il login non riallinea le task, lasciare intatta
la build Play e diagnosticare Supabase prima di attivare Movimento.

Controlli rapidi:

```sh
# Todo Test: snapshot passivo e configurazione Drive
adb -s SERIAL shell content query --uri \
  content://app.deterministic.todo.deterministic_todo.dev.movement_debug/status

# Play: deve restare disabled-user
adb -s SERIAL shell dumpsys package \
  app.deterministic.todo.deterministic_todo | grep 'enabled='
```
