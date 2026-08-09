# Modulo corsa Amazfit Bip U

## Decisione

Il modulo vive in `android/runtracker` come libreria Android autonoma. Il client
Flutter possiede soltanto un canale per aprirne l'Activity e una voce nelle
Impostazioni. Database, servizio, interfaccia e BLE non dipendono dal modello
Todo e non vengono sincronizzati con Supabase. Per rimuoverlo bastano la
dipendenza Gradle, il canale e la singola voce UI.

Gadgetbridge è stato consultato nel repository ufficiale Codeberg al commit
`c585908b1c38d949273e8d277208a1fd548d6271` per verificare le capacità dichiarate
del Bip U: chiave obbligatoria, attività registrate e misurazione cardiaca. Il
codice è AGPLv3. Non è stato copiato, adattato o incorporato. Il progetto resta
MIT e il protocollo Huami verrà implementato indipendentemente da osservazioni
del proprio dispositivo e fixture sintetiche. Questa è una scelta prudenziale,
non un parere legale.

## Flusso GPS

`RunTrackerActivity` avvia esplicitamente `RunRecordingService` mentre è
visibile. Il servizio si promuove immediatamente a foreground di tipo
`location`, espone una notifica persistente e riceve campioni solo dal provider
GPS. `GpsTrackFilter` decide in modo deterministico senza alterare coordinate:

1. coordinate e accuratezza valide (massimo 35 m);
2. timestamp strettamente crescente;
3. spostamento superiore al rumore derivato dall'accuratezza;
4. velocità non superiore a 12 m/s;
5. esclusione dei ritorni brevi compatibili con zigzag.

Durante una sessione, un incremento del contatore passi hardware costituisce
una prova locale di movimento. In quel caso soltanto la soglia minima
anti-rumore viene ridotta, per riacquisire rapidamente una camminata dopo una
sosta quando il fix GPS si muove poco. Il segnale passi non aggira mai i limiti
di accuratezza, velocità, discontinuità o zigzag e non viene convertito
direttamente in metri GPS.

Ogni campione produce una riga `TrackPoint`; `accepted=false` conserva sempre
`rejectionReason`. Soltanto i punti accettati incrementano `distanceMeters`.
La sessione e i punti sono archiviati in `run_tracker.sqlite` tramite Room.

Il GPX 1.1 contiene punti accettati in `trkseg` e scarti come `wpt` con tipo
`rejected:<reason>`. In questo modo il file è utilizzabile normalmente ma
conserva evidenza per affinare le soglie.

Le sessioni persistono il tipo `walk` o `run`. Il filtro camminata limita a
6 m/s i segmenti GPS plausibili, mentre il profilo corsa mantiene 12 m/s; la scelta
esplicita evita che salti GPS incompatibili con una camminata vengano sommati.

## Passi e stime quotidiane

Dallo schema Room 3 `daily_movement` conserva giorno civile, fuso IANA,
provenienza, passi e stime di distanza e calorie attive. La sorgente primaria è
l'aggregazione `StepsRecord.COUNT_TOTAL` di Health Connect: l'aggregatore di
sistema riduce il rischio di doppio conteggio tra sorgenti sovrapposte e può
continuare ad acquisire passi anche quando il processo dell'app non è attivo.
L'app riconcilia con un upsert idempotente quando la schermata Movimento viene
aperta.

Le stime iniziali usano 0,72 metri per passo, 70 kg e 0,50 kcal/(kg·km). Sono
fallback dichiarati, non un profilo personale né una misura clinica. Il
prossimo schema dovrà versionare parametri e algoritmo, aggiungere calibrazione
tramite sessioni GPS e conservare il valore precedente per la riproducibilità.

## BLE e confine di sicurezza

La prima fase BLE richiede solo scansione e connessione, seleziona un nome che
contiene `Bip U` e tenta la lettura del servizio standard Battery. Non scrive
caratteristiche. La chiave Huami, inserita manualmente, deve essere di 16 byte
esadecimali e viene cifrata AES-GCM con una chiave non esportabile in Android
Keystore. Valore, MAC, titoli e coordinate non entrano nei log.

L'autenticazione, il fetch delle attività e il live HR sono deliberatamente
spenti. La futura autenticazione richiederà messaggi di controllo BLE: andrà
abilitata solo dopo test sul Bip U e limitata al minimo necessario. Sono vietate
scritture firmware, aggiornamenti, factory reset e modifiche di risorse.

## Allineamento futuro

GPS del telefono e campioni sportivi dell'orologio conserveranno timestamp UTC
originali. L'allineamento non cambierà gli istanti: userà una stima robusta di
offset iniziale, segnalerà drift o discontinuità e lascerà entrambe le serie
grezze disponibili. Una corsa può iniziare prima su uno dei due dispositivi;
l'intersezione temporale costituisce il tratto combinato.
