# Movimento autonomo: riscontri e piano

Audit del codice del 7 settembre 2026, base build 168. Obiettivo autorizzato:
usare Todo come unica app per passi, distanza camminata/corsa, rilevazione
passiva e sessioni esplicite, con calorie stimate. Amazfit è spento secondo
l'utente; la prima validazione deve quindi funzionare con il solo telefono.
Questo documento è il riferimento per il nuovo percorso; le descrizioni
storiche in HANDOFF non costituiscono prova di autonomia a processo chiuso.

## Riscontri confermati nel codice

| Area | Comportamento attuale | Limite |
| --- | --- | --- |
| Passi telefono | `PhoneDailyMovementGateway` legge un campione `TYPE_STEP_COUNTER`, poi scollega il listener | Raccolta intermittente, copertura dell'intera giornata non dimostrata |
| Giorno civile | Baseline per boot e chiave giorno/fuso | Un intervallo attraverso mezzanotte non è attribuibile esattamente |
| Totale quotidiano | Fonti locali, Fit escluso; `max(telefono, Bip)` | Il massimo giornaliero perde eventuali intervalli complementari |
| Distanza quotidiana | `MovementEstimate`: passi per lunghezza del passo camminata | La corsa non usa il proprio modello nel percorso del totale locale |
| Attività | Activity Recognition presente; modello misto usato negli audit | Serve una cronologia locale di passi attribuibili agli intervalli |
| Sessione GPS | Fix richiesti ogni secondo, filtro salti/rumore, gate passi in camminata | Valutare sensori asincroni e finestre di movimento; non modificare soglie senza prova |
| Calibrazione | Mediana di almeno tre sessioni, modelli camminata/corsa; purezza almeno 80% a soglia 135 passi/min | Manca calibrazione per cadenza e un gate esplicito sulla copertura/qualità GPS |
| Calorie | Peso fallback 70 kg; coefficienti 0,5 camminata e 1 corsa kcal/kg/km | Profilo personale assente; quotidiano ancora camminata; stime non misure |

La concordanza con Fit non basta come verità di riferimento. In passato i due
totali condividevano record Health Connect. Anche con totali ora locali,
un'altra app o la diagnostica possono mantenere il sensore attivo: questa è
un'ipotesi da verificare, non una dipendenza accertata sul Galaxy.

## Primo incremento: build 169

`PhoneDailyStepPolicy` conserva il subtotale già salvato quando si ritorna a
una chiave giorno/fuso osservata in precedenza. Prima restituiva zero a ogni
cambio chiave. Il delta attraverso il confine resta escluso: non si inventa
la sua ripartizione e non si cambia la migrazione storica della build 163.

La prima lettura assoluta può usare il contatore dal boot soltanto se il boot
è iniziato oggi e non esiste un subtotale. Questo ramo era irraggiungibile al
primo avvio normale perché il giorno precedente non esisteva. Non implica che
il sensore sia stato attivo durante tutto il boot. Reboot/reset conservano il
subtotale e ripartono da una baseline, senza ricostruire intervalli mancanti.

Il provider ADB aggiunge tre campi tecnici, disponibili anche senza Drive/Fit:

- `phone_collection_mode=one_shot_counter`;
- `phone_coverage=not_established` (mai confondere un campione con copertura);
- `phone_accounting_reason`: `not_observed`, `initial_boot_today`,
  `initial_baseline`, `civil_boundary_baseline`, `boot_baseline`,
  `counter_reset_baseline`, `counted`, `unchanged`, `accounting_migration`.

Il motivo riguarda l'ultimo aggiornamento persistito, non l'esito dell'ultimo
tentativo sensore. Non include conteggi, coordinate o cronologie personali.
La lettura del provider non attiva sensori, GPS, BLE o upload. Non cambia il
campionamento GPS, la calibrazione, i worker del test né le dipendenze.

## Incrementi successivi e criteri di accettazione

La build 170 realizza la raccolta autonoma e una prima versione del modello
quotidiano e del profilo. Restano le validazioni sul campo e gli affinamenti
dei punti sotto, descritti nella sezione implementazione.

1. **Acquisizione passiva autonoma.** Valutare Recording API locale di Play
   Services per i passi: senza account, storage sul dispositivo, raccolta
   background e disponibilità limitata a dieci giorni. Verificare versione sul
   Galaxy, granularità e consumo prima di aggiungere la dipendenza. Import
   idempotente periodico in Room; nessun GPS passivo. Rimuovere Fit come app
   non richiede rimuovere Play Services. Una soluzione senza Play Services
   richiede una valutazione distinta dei vincoli background Android.
2. **Cronologia canonica locale.** Migrazione Room con intervallo UTC, fuso,
   boot, sorgente, versione algoritmo, copertura e qualità. Gestire campioni
   duplicati/fuori ordine, timestamp sensore rispetto all'ora di ricezione e
   cambio ora/fuso. Non dedurre una cadenza precisa da lunghi delta aggregati.
3. **Classificazione e distanza.** Attribuire gli intervalli a camminata,
   corsa o incerto usando Activity Recognition e cadenza; velocità solo quando
   disponibile da una sessione. Calibrazione personale per cadenza con dati
   sufficienti e GPS affidabile; fallback esplicito altrimenti.
4. **Contabilità unica.** Una sessione è parte della giornata. Sostituire la
   stima dello stesso intervallo con GPS valido, senza aggiungerla due volte.
   Integrare orologio solo in seguito, per intervallo e copertura, senza somme
   né massimi automatici che favoriscano fonti rumorose.
5. **Calorie.** Profilo personale locale, durata e intensità, modello MET
   valutato su camminata/corsa; distinguere calorie attive e riposo. Conservare
   versione e parametri del modello, non riscrivere silenziosamente lo storico.
   Il battito eventuale non è una misura diretta delle calorie.

## Implementazione build 170

- **Raccolta:** `LocalStepRecording` sottoscrive `TYPE_STEP_COUNT_DELTA` della
  Recording API locale. La sottoscrizione già esistente è un no-op secondo il
  contratto del fornitore; Play Services raccoglie fuori dal processo Todo.
  Richiede Attività fisica, non account Fit, Health Connect, Drive o GPS.
  Versione Play Services verificata a runtime, attese limitate a 12 secondi per
  chiamata; errori esposti come codici tecnici, senza dati nei log.
- **Import:** worker univoco ogni tre ore, differibile da Android; aggiornamento
  al massimo ogni minuto quando visibile. La UI legge subito Room e non aspetta
  l'API. Nessun timer aggiuntivo a schermo spento, foreground service o BLE.
  Le letture riacquisiscono due ore sovrapposte o il periodo dall'ultimo import,
  fino a nove giorni per restare entro la retention del fornitore.
- **Persistenza:** Room 5 aggiunge `local_step_minutes` (chiave minuto UTC) e
  `local_step_state` (confine di attivazione e cursore). Una risposta sostituisce
  i valori delle stesse chiavi, non li somma. Righe e cursore sono atomici;
  un errore conserva l'import precedente. Una risposta vuota non avanza il
  cursore e non prova zero passi. Minuti parziali/invalidi non vengono arrotondati.
- **Passaggio:** il subtotale preesistente resta separato, attribuito al suo
  giorno/fuso. La nuova fonte comincia dal minuto completo successivo alla
  sottoscrizione. L'intervallo prima di quel confine non viene ricostruito;
  possibili lacune preesistenti restano dichiarate. Le preferenze storiche non
  vengono cancellate. La vecchia lettura one-shot non è più usata per aggiungere
  passi. Se il servizio non è disponibile, i dati salvati restano visibili e
  l'interfaccia segnala il problema, senza inventare un conteggio nuovo.
- **Modello quotidiano:** Activity Recognition attribuisce i minuti locali a
  camminata/corsa/incerto. Gli intervalli GPS accettati sostituiscono la quota
  temporale della stima dei passi sovrapposta; non si sommano passi di sessione
  al totale giornaliero. Segmenti GPS sovrapposti non vengono sommati. Attraverso
  confini di minuto/giorno, la ripartizione della distanza è proporzionale al
  tempo: è una stima di attribuzione, non ricostruzione del percorso.
- **Profilo:** la schermata offre peso e lunghezza del passo camminata/corsa,
  validati e salvati solo localmente. La calibrazione esistente può aggiornare
  il passo. Calorie attive: coefficienti espliciti 0,5/1 kcal/kg/km rispettivamente
  per camminata/corsa, applicati alla distanza risultante. Non è ancora un
  modello MET per intensità/pendenza o un calcolo del metabolismo a riposo.
  `daily_movement` conserva versione modello e parametri usati. Il totale del
  giorno consultato viene ricalcolato; gli export già prodotti restano immutabili.
- **Diagnostica:** `phone_collection_mode=local_recording_api`, ultimo import,
  stato della sottoscrizione e copertura dal momento dell'attivazione. La
  copertura dichiarata non dimostra accuratezza o assenza di interruzioni del
  sensore. Il confronto sperimentale Fit/Drive è etichettato separatamente e
  può restare spento senza fermare la raccolta locale. Gli audit leggono le
  stesse stime locali della UI; la ripartizione dei conteggi nell'audit storico
  resta prudenzialmente `unknown` e non è una nuova validazione del classificatore.

La dipendenza `play-services-fitness:21.2.0` è confinata al modulo Android:
Google Maven dichiara Android Software Development Kit License. Motivazione:
raccolta delegata e parsimoniosa in background senza servizio permanente
dell'app. Non usa le API Fit con account; costo APK e prove hardware sono
registrati in STATUS. Il fallback Amazfit resta il massimo conservativo
giornaliero: la fusione temporale multi-dispositivo non è implementata nella 170.

Resta da validare il modello su passi contati, percorsi noti e batteria. La
calibrazione per cadenza, il modello calorico MET, la fusione temporale Amazfit
e la copertura durante revoche permesso/arresto forzato sono affinamenti futuri.

## Procedura di verifica

```sh
make check
cd android
./gradlew :runtracker:testDebugUnitTest :runtracker:connectedDebugAndroidTest
```

Le prove strumentali creano e cancellano esclusivamente database sintetici
nel package di test. Verificano migrazione 4→5, dati storici preservati, import
idempotente, rollback e riapertura. Per lo stato reale, senza leggere passi/GPS:

```sh
adb shell content query --uri content://app.deterministic.todo.deterministic_todo.dev.movement_debug/status --projection phone_collection_mode:phone_coverage:phone_accounting_reason:phone_last_import_ms
adb shell content call --uri content://app.deterministic.todo.deterministic_todo.dev.movement_debug/status --method refresh_steps
```

`refresh_steps` richiede lo stesso import locale, soggetto a throttle; non
avvia upload, GPS o BLE. `awaiting_complete_minute` è atteso all'attivazione,
`subscribed_no_samples` distingue l'assenza di dati; `subscribed` indica import
riuscito, non precisione dei passi. Se appare `permission_required`, usare il
pulsante in Movimento; per `play_services_unavailable_*` aggiornare Play Services.
Un gap oltre retention resta segnalato. Non cancellare storage o disinstallare
per risolvere un errore: conservarne lo stato tecnico e riprovare normalmente.

### Collaudo sul campo ancora necessario

Non attivare o fermare esperimenti esistenti implicitamente. Prova dedicata
con Fit disattivato e diagnostica intensiva spenta, telefono in tasca, schermo
spento, processo ricreato, reboot, mezzanotte e cambio fuso. Distinguere processo
terminato da arresto forzato Android. Verificare anche auto, immobilità e assenza
del telefono: passi non osservabili non devono essere inventati.

Usare passi contati e percorsi di lunghezza nota per camminata, corsa e tratti
misti. Registrare errori assoluti/relativi, copertura, duplicati e consumo a
riposo rispetto alla stessa configurazione senza raccolta. Definire soglie
dopo la baseline; nessuna percentuale di accuratezza è già dimostrata.
Fixture sintetiche per test automatici, mai GPS o dati sanitari nel repository.

## Fonti tecniche

Consultate il 7 settembre 2026:

- [Android: sensori di movimento](https://developer.android.com/develop/sensors-and-location/sensors/sensors_motion): il contatore accumula mentre il sensore è attivo.
- [Recording API locale](https://developer.android.com/health-and-fitness/recording-api): raccolta background, dati locali, niente account, Play Services e finestra di conservazione.
- [Activity Recognition](https://developers.google.com/location-context/activity-recognition): transizioni di attività senza servizio dell'app costantemente attivo per il riconoscimento.
- [Compendium e MET personalizzati](https://pacompendium.com/corrected-mets/): la personalizzazione non elimina l'errore della stima energetica individuale.

Stato delle verifiche e del dispositivo: [STATUS](../../STATUS.md).
