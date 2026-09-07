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

## Validazione indipendente

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
