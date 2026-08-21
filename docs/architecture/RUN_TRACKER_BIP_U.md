# Modulo corsa Amazfit Bip U

## Diagnostica remota unificata

Dalla build 134 `DiagnosticDriveWorker` produce ogni ora in
`04 App diagnostics` un report compatto che accoppia per timestamp lo stato
telefono/Google Fit con gli aggregati Bip U delle ultime 3 e 24 ore. Registra
copertura al minuto, passi, sintesi del battito, anzianità dell'ultimo campione,
stato intensivo, chunk in attesa e metadati dei log.

Il riepilogo unificato non contiene timeline puntuali, coordinate, MAC, chiave
Huami o contenuti Todo.
I JSONL intensivi orari rimangono separati perché voluminosi. L'import Bip U
resta esplicito e idempotente: nessuna connessione BLE viene mantenuta in
background. Vengono conservati gli ultimi 15 report unificati.

Ogni sessione terminata ha inoltre un report canonico `*_three_way.json` in
`01 Sessions`, sovrascritto in modo verificato invece di creare copie. Usa
finestre UTC di un minuto e contiene totali, copertura, scarti a coppie e la
timeline nativa Bip necessaria al collaudo: passi, battito, tipo, intensità e
campi sonno. Google Fit resta a risoluzione di sessione finché Health Connect
non attribuisce intervalli più granulari alla sorgente. Questo report contiene
dati sanitari personali sul Drive scelto dall'utente, ma mai coordinate, MAC,
chiave, pacchetti BLE o contenuti Todo.

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

Per diagnosticare le ripartenze, ogni variazione del contatore durante una
sessione viene conservata con timestamp e stato. La timeline vive in memoria,
ha un limite esplicito e viene salvata al massimo ogni 30 secondi e alla fine;
non aggiunge polling né mantiene il processo attivo fuori dalle sessioni.

Nel profilo camminata, se il contatore hardware è attivo, ogni intervallo GPS
privo di nuovi passi viene escluso dalla distanza con motivo
`stationary_step_gate`. Il punto non diventa una nuova ancora: alla ripresa il
filtro può recuperare il collegamento plausibile dall'ultimo fix in movimento.
Il gate non si applica alla corsa né quando il sensore è indisponibile.
`StepMotionGate` mantiene questa politica separata dal lifecycle del servizio:
riceve il totale monotono della sessione, il tipo attività e lo stato sensore,
e restituisce evidenza di nuovi passi e obbligatorietà del gate. Reset del
contatore e fallback sono coperti da test JVM senza dipendenze Android.

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

La Transition API di Activity Recognition conserva localmente una timeline di
14 giorni con `walking`, `running`, `vehicle`, `bicycle`, `still` e `unknown`.
Non mantiene GPS o un servizio foreground: il lavoro di riconoscimento è
delegato al sistema. I record passi Health Connect vengono ripartiti in
proporzione alla durata delle attività sovrapposte e poi riconciliati con il
totale aggregato, che resta la fonte canonica del conteggio.

Le stime iniziali usano 0,72 m/passo camminando, 1,05 m/passo correndo, 70 kg,
0,50 kcal/(kg·km) per cammino e 1,00 per corsa. Veicolo e bicicletta dominanti
sono esclusi dalla distanza; `unknown` usa il fallback da camminata. Se
Activity Recognition segnala `still` ma esistono passi, il sensore prevale e
la quota conflittuale entra in `unknown`. Dopo tre
sessioni esplicite valide (almeno 1 km/1.000 passi per cammino o 3 km/2.000
passi per corsa), la mediana degli ultimi sette rapporti GPS/passi calibra il
solo profilo corrispondente. Ogni sessione viene acquisita una sola volta.

I report schema 7 `passive_intraday_snapshot` e `passive_daily_audit`
registrano categorie, esclusioni separate veicolo/bicicletta, conflitti
`STILL + passi`, baseline all-steps e parametri applicati. Conservano inoltre
finestra effettiva, latenze delle query, record grezzi, valori pre/post
riconciliazione, fattore di scala, durate per stato, falcate implicite, flag di
qualità e differenze assolute/percentuali. I record Health
Connect che attraversano transizioni vengono ripartiti per durata; veicolo o
bicicletta escludono passi soltanto con dominanza temporale almeno dell'80%,
mentre la quota ambigua resta `unknown_steps`. Durante il test di sette giorni uno
snapshot cumulativo e immutabile viene creato per ogni fascia oraria; include
anche un delta validato rispetto allo snapshot precedente. Cambio giorno,
reset dei contatori e dati Fit mancanti invalidano esplicitamente il delta. Il
giorno concluso conserva un report finale distinto.

Lo schema 6 aggiunge `minute_timeline`, allineata a minuti UTC. I passi dei
record Health Connect che attraversano più minuti vengono distribuiti per
durata con arrotondamento deterministico e poi riconciliati esattamente al
totale aggregato. Per ogni minuto restano distinti categorie Todo, passi grezzi
attribuiti a Google Fit e distanza Fit. Questa granularità è ricostruita dai
timestamp dei record, quindi resta utile anche se la lettura avviene molto dopo
la camminata; non richiede un job al minuto.

Lo schema 7 affianca a ogni minuto i campioni Bip U già importati, senza
attivare BLE. Un analizzatore esclusivamente diagnostico raggruppa minuti attivi
in episodi e può colmare una sola pausa intermedia; non modifica categorie,
passi o distanza mostrati. Ogni episodio conserva valori Todo/Fit/Bip, battito
medio disponibile, sovrapposizioni e flag. `source_coverage` distingue assenza
di campioni da valore zero e misura freschezza/ritardo; `model_provenance`
identifica la configurazione tramite SHA-256; `diagnostic_resources` chiarisce
che CPU/rete sono attribuibili al processo/UID mentre la batteria è soltanto
contesto dell'intero dispositivo.

Dal 21 agosto 2026 la radice `02 Passive` contiene soltanto report schema 7
prodotti dalla build 139 o successive. I 27 report precedenti sono conservati
immutabili nella sottocartella `Archive - schema 6 and earlier`; gli strumenti
di analisi correnti devono ignorare quella sottocartella salvo confronti
storici espliciti. L'app continua a scrivere nella radice autorizzata, quindi
l'archiviazione non modifica né interrompe gli upload automatici.

## BLE e confine di sicurezza

La prima fase BLE cerca prima tra i dispositivi già associati ad Android un
nome che contiene `Bip U`; soltanto se non lo trova avvia una scansione di 12
secondi. Questa precedenza è necessaria perché un Bip U già collegato come
Battery/HID può non pubblicare nuovi annunci. Il modulo apre quindi una
connessione GATT e tenta la lettura del servizio standard Battery. Non scrive
caratteristiche. La chiave Huami, inserita manualmente, deve essere di 16 byte
esadecimali e viene cifrata AES-GCM con una chiave non esportabile in Android
Keystore. Valore, MAC, titoli e coordinate non entrano nei log.

Ogni tentativo terminale produce in `05 Bip U` un JSON con timestamp, durata,
origine `bonded`/`scan`, esito, batteria opzionale e codice GATT opzionale. Il
report dichiara esplicitamente l'assenza di MAC, chiave e scritture verso
l'orologio. Se Drive non è configurato, la prova BLE resta utilizzabile e lo
segnala nell'interfaccia.

La build 122 abilita una prova cardiaca esplicita e limitata a 60 secondi. Usa
la chiave soltanto in memoria per il challenge-response AES, sottoscrive la
caratteristica Bluetooth SIG Heart Rate Measurement e invia esclusivamente i
comandi temporanei di avvio/arresto necessari. L'arresto e la disconnessione
sono automatici anche senza campioni. Il report conserva conteggio, minimo,
massimo e media, ma non chiave, MAC o pacchetti grezzi; dichiara esplicitamente
le scritture di controllo transitorie e l'assenza di configurazioni persistenti.

La build 125 aggiunge l’importazione manuale iniziale. Dalla build 134 la
richiesta parte dall'ultimo campione conservato meno un'ora di sovrapposizione
e recupera fino a sette giorni: una disconnessione più lunga viene dichiarata
come troncata, non nascosta. Dopo
l’autenticazione abilita i due canali attività, richiede i campioni di un
minuto e li conserva in `bip_u_activity_samples` con timestamp UTC, sorgente e
istante di importazione. L’inserimento `IGNORE` sulla chiave composta rende i
retry idempotenti. Dopo un inserimento vengono rigenerati i report a tre delle
sessioni temporalmente sovrapposte. Non viene inviato il comando finale di conferma: i dati non
sono marcati come consumati o rimossi dall’orologio. Il report tecnico Bip
contiene aggregati; la timeline sanitaria compare soltanto nei report sessione
esplicitamente destinati al confronto.

Sul Bip U reale il campo di lunghezza vale 1.440 per una giornata, mentre il
payload contiene 11.520 byte: è quindi un conteggio di campioni da otto byte,
non di byte. La build 126 accetta esplicitamente entrambe le semantiche
osservabili e continua a rifiutare qualunque altra lunghezza.

Il modello resta **phone-first**: Health Connect, sensori del telefono e GPS
manuale funzionano senza orologio. Bip U è una sorgente opzionale conservata
separatamente; finché la fusione per intervalli non sarà validata, i suoi passi
non vengono sommati o sostituiti automaticamente a quelli del telefono.
Battito continuo in background resta spento. Sono vietate scritture firmware,
aggiornamenti, factory reset, modifica di risorse e impostazioni persistenti.

L’ultimo tentativo di recupero Bip è persistito separatamente con fase,
timestamp, esito, campioni, passi, battito ed esito Drive. Gli stessi campi
appaiono nel provider diagnostico ADB e nel riepilogo Drive orario: `running`
rimasto senza conclusione è quindi distinguibile da `activity_empty`, errore
BLE, successo locale o errore dell’export.

## Allineamento diagnostico

GPS del telefono e campioni dell'orologio conservano timestamp UTC originali.
La build 134 non altera gli istanti e dichiara che non applica ancora una
correzione di clock: raggruppa i dati in finestre di un minuto e segnala
copertura e risoluzione. Un'eventuale stima robusta di offset o drift sarà una
trasformazione futura esplicita, mai una modifica dei campioni originali.
