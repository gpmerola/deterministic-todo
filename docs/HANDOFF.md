# Handoff tecnico e di prodotto

Aggiornato il 10 agosto 2026. Questo documento è il punto di ingresso per una
nuova chat o un nuovo agente. Va letto integralmente insieme ad
[`AGENTS.md`](../AGENTS.md), [`STATUS.md`](../STATUS.md) e
[`TODO_NEXT.md`](../TODO_NEXT.md).

## Obiettivo dell’app

Deterministic Todo è un gestore personale Flutter offline-first. Android è il
client nativo prioritario; su macOS e Windows si usa la stessa app via browser.
SQLite locale è sempre la fonte immediata dell’interfaccia e Supabase è una
replica personale opzionale. Il prodotto è volutamente minimale, senza
analytics, collaborazione o dipendenza dalla rete per l’uso ordinario.

Il prossimo obiettivo prioritario è ampliare il modulo Android isolato per:

1. contare i passi quotidiani;
2. calcolare la distanza percorsa camminando e correndo;
3. mantenere le sessioni GPS manuali affidabili anche a schermo spento;
4. integrare in futuro i dati dell’**Amazfit Bip U**.

Nel messaggio originale “Amazon fit” è interpretato come “Amazfit”. Se invece
si intende Amazon Health, Google Fit o Health Connect, chiedere conferma prima
di cambiare architettura.

## Stato distribuibile

- Repository sorgente: `gpmerola/deterministic-todo`.
- Repository degli APK diretti: `gpmerola/deterministic-todo-releases`.
- Branch operativo al momento dell’handoff:
  `agent/verify-public-release-token`.
- Versione coordinata corrente: **2.23.5 build 102**. La base funzionale
  **2.22.3 build 95** ha superato test, build firmate, pubblicazione diretta,
  Google Play interno, Web e controllo di parità; la 96 consolida codice,
  test e documentazione.
- Android viene pubblicato nel test interno Google Play e come APK firmato;
  Web viene distribuito su GitHub Pages dallo stesso workflow coordinato.
- Telefono reale di riferimento: Samsung Galaxy S21, `arm64-v8a`.
- Orologio: Amazfit Bip U senza GPS integrato.
- Il Galaxy S21 è già associato al Mac per ADB wireless. La connessione va
  ristabilita dopo cambi di rete, IP o porta seguendo
  [`operations/ADB_WIFI.md`](operations/ADB_WIFI.md); non conservare nel
  repository l'indirizzo runtime del telefono.

Ogni modifica funzionale Android deve incrementare versione/build, superare i
test e arrivare sul telefono tramite il workflow. Una modifica soltanto
documentale non richiede una nuova build.

## Come funziona il Todo

- Schema e query locali: `lib/data/local/` con Drift/SQLite.
- Sincronizzazione: `lib/data/sync/`, outbox persistente, UUID, versioni
  Lamport, tombstone e operazioni idempotenti.
- Replica: Supabase con RLS e Realtime; recupero completo ogni dieci minuti
  soltanto mentre l’app è visibile.
- Dominio puro: `lib/domain/` per date civili, parser e ricorrenze.
- Interfaccia: `lib/ui/`; Android e Web condividono comportamento e modello.
- Import Todoist: aggiornamento oppure sostituzione idempotente dei soli dati
  provenienti da Todoist.
- Le date Todo sono date civili senza ora. Non vanno convertite implicitamente
  in istanti né spostate al cambio di fuso.

Dettagli completi in [`ARCHITETTURA.md`](ARCHITETTURA.md). Non modificare il
modulo movimento per risolvere problemi Todo e viceversa.

## Modulo movimento esistente

Il modulo nativo vive in `android/runtracker` ed è separabile. Flutter espone
solo `lib/services/run_tracker_service.dart`, il channel Android e una
destinazione principale Movimento accanto a Progetti. Il database
`run_tracker.sqlite` è Room, locale e distinto dal
database Todo; non è sincronizzato con Supabase.

### Cosa funziona oggi

- Avvio manuale distinto di camminata o corsa dall’app.
- `RunRecordingService` foreground di tipo `location`, compatibile con Android
  14 e persistente a schermo spento.
- Posizione dal solo provider GPS del telefono ogni secondo.
- Filtro deterministico per accuratezza, timestamp, rumore da fermo, velocità
  impossibile e zigzag.
- Conservazione in Room sia dei punti accettati sia degli scarti con motivo.
- Distanza cumulativa dai soli punti accettati.
- UI con durata, distanza, passo medio, accuratezza e stato del GPS.
- Export GPX 1.1 esplicito tramite FileProvider e auto-export GPX+JSON opzionale
  nella cartella Drive autorizzata dall’utente. La build 91 mantiene il servizio
  attivo fino all'esito, rende le scritture idempotenti e consente di riesportare
  l'ultima attività con stato o codice errore visibile.
- Prova BLE in sola lettura: scansione, connessione e tentativo di leggere la
  batteria standard.
- Inserimento facoltativo della chiave Huami, validata come 16 byte
  esadecimali e cifrata con Android Keystore. La chiave non viene ancora
  trasmessa.

### Evidenza reale già raccolta

Una breve prova sul Galaxy S21 ha prodotto GPX validi. Nel campione principale
sono stati accettati 31 punti e scartati 70 punti come rumore da fermo, con
circa 117 m in 99 secondi, accuratezza mediana 6 m e massimo intervallo tra
punti accettati di 14 s. Un secondo campione aveva 11 punti accettati, 32
scartati e circa 47 m in 40 s. Un confronto successivo ha trovato 711 m contro
550 m di Google Fit (+29%), inclusa una discontinuità di circa 110 m in 10 s.
La 2.20.1 separa il profilo camminata (soglia segmento GPS 6 m/s) da quello
corsa (12 m/s)
e ri-ancora la traccia dopo due fix coerenti senza sommare il salto. Serve
ancora conferma su hardware.

I GPX contengono soltanto GPS, timestamp, accuratezza e motivi di scarto. **Non
contengono passi, cadenza o frequenza cardiaca e non provengono da Google Fit o
dal Bip U.** Non committare GPX reali: rivelano il percorso personale.

### Incremento passi in verifica

La 2.21.0 legge tramite l'API di aggregazione il totale passi della giornata da
Health Connect e lo salva nello schema Room 3 con giorno civile, fuso e
provenienza. Health Connect può continuare il conteggio di sistema quando
l'app è chiusa; l'app riconcilia il totale quando viene aperta. Distanza e
calorie attive sono stime esplicitamente etichettate, per ora basate sui valori
provvisori di 0,72 m per passo e 70 kg. Manca ancora il profilo personale e non
esiste ancora una calibrazione personale sufficientemente lunga.

La build 97 conserva `TYPE_STEP_COUNTER` direttamente nel servizio delle
sessioni: il delta è visibile nella UI, continua a schermo spento e viene
esportato nel JSON con stato esplicito. Un confronto in-app aggrega inoltre,
nello stesso intervallo locale, passi, distanza e calorie attive filtrati per
l'origine Google Fit. Durante una camminata, i fix senza nuovi passi non
incrementano la distanza; alla ripresa il collegamento plausibile riparte
dall'ultima ancora valida. La disponibilità del confronto dipende dalla
sincronizzazione Google Fit → Health Connect.

La 2.23.1 rende camminata l'azione primaria e sposta Drive, export manuale e
BLE in strumenti avanzati comprimibili. Dopo lo stop un `WorkManager` unico
per sessione attende Google Fit, applica timeout e retry esponenziale e
rigenera il JSON Drive includendo `google_fit_comparison`. Non dipende più
dall'Activity aperta. La schermata mostra lo stato persistito del job.

La 2.23.2 aggiunge il consenso Health Connect separato per le letture in
background, necessario perché WorkManager possa leggere i dati attribuiti a
Google Fit quando Movimento non è visibile. Dopo la concessione viene
riprogrammata l'ultima sessione terminata. Il JSON Drive conserva anche stato,
numero e istante dei tentativi, rendendo la diagnosi indipendente da ADB.

Sul Galaxy S21 la 2.23.2 non ha riesportato la sessione 14 dopo il consenso.
La 2.23.3 aggiunge quindi un fallback deterministico: dopo il consenso, o
aprendo Movimento con stato `permission_required`, confronta immediatamente in
primo piano e aggiorna Drive; WorkManager resta il percorso automatico futuro.
La 2.23.4 estende il recupero a ogni stato diverso da `success`, perché la
sessione 14 era rimasta su `scheduled` dopo la concessione.

Il controllo ADB sulla 2.23.4 ha confermato tutti i permessi, incluso quello in
background, e due esecuzioni del job, ma il JSON Drive era ancora quello
originario. La 2.23.5 rende quindi osservabile il confine Health Connect:
registra nel JSON un codice derivato soltanto dalla classe dell'eccezione,
riesporta ogni fallimento prima del retry e marca `success` anche nel fallback
in primo piano. Non è necessaria una nuova camminata per diagnosticare la
sessione 14.

Il JSON della build 94 conserva inoltre la timeline delle variazioni dei passi
con timestamp e stato. Rimane diagnostica locale della sessione: il telefono e
Health Connect continuano a contare a processo chiuso, mentre l'app riconcilia
il totale quando viene aperta, senza servizio permanente o GPS quotidiano.

Nelle camminate della build 95, quando il sensore è attivo, i fix ricevuti
senza nuovi passi restano nella diagnostica come `stationary_step_gate` ma non
aggiungono metri. Il primo nuovo passo riabilita il segmento GPS plausibile.

I test reali brevi hanno mostrato passi entro circa 0,5–3,5% da Google Fit. La
distanza è variata da -8,2% a +19,1%: la timeline della build 94 ha attribuito
la sovrastima maggiore al drift GPS durante due soste senza passi. La build 95
introduce il gate conseguente; manca ancora il test definitivo di 10–15 minuti
a schermo spento con una sosta di circa 30 secondi.

### Cosa non esiste ancora

- attribuzione quotidiana completa del contatore hardware attraverso
  mezzanotte, reboot e periodi senza campioni;
- calibrazione personale di falcata, peso e modello calorico;
- riconoscimento automatico camminata/corsa (la selezione manuale è disponibile);
- autenticazione BLE Huami;
- download delle sessioni sportive dal Bip U;
- battito, cadenza o passi dell’orologio;
- allineamento temporale orologio↔GPS;
- battito in tempo reale;
- export GPX con estensioni HR/cadenza.

## Architettura proposta per passi e distanza

Non usare il GPS continuamente: consumerebbe batteria ed è incompatibile con
il carattere minimale dell’app.

### 1. Passi quotidiani

Usare `Sensor.TYPE_STEP_COUNTER` come sorgente primaria e
`TYPE_STEP_DETECTOR` solo come fallback. Richiedere `ACTIVITY_RECOGNITION` su
Android 10+. Il contatore hardware è cumulativo dal reboot: salvare ogni
lettura con `bootId`, timestamp UTC, fuso IANA e giorno civile attribuito.
Calcolare solo delta monotoni; dopo reboot/reset iniziare una nuova baseline e
non produrre delta negativi.

Room deve avere una migrazione versionata e almeno:

- `daily_movement(day, zoneId, steps, estimatedDistanceMeters, updatedAt)`;
- `step_counter_samples(id, bootId, timestamp, rawCounter, delta, source)`;
- provenienza della distanza (`gps`, `step_estimate`, in futuro `amazfit`).

Una sola lettura dopo il riavvio dell’app non permette di ricostruire con
precisione il confine di mezzanotte se il processo non era attivo. Non
nascondere questo limite. Prima MVP: conteggi affidabili mentre il servizio
leggero è attivo e riconciliazione al successivo campione. In seguito valutare
Health Connect per uno storico di sistema, oppure un job molto parsimonioso;
non mantenere un foreground service permanente solo per ottenere il totale
giornaliero.

### 2. Distanza camminata e corsa

Tenere due misure esplicite:

- **sessione GPS**: distanza misurata dal telefono durante una camminata/corsa
  avviata manualmente; è la misura primaria per percorso e passo;
- **giornaliera stimata**: passi × lunghezza del passo calibrata, senza
  percorso. Etichettarla sempre come stima.

Prevedere lunghezze del passo separate per camminata e corsa, configurabili e
calibrabili confrontando passi e distanza di una sessione GPS sufficientemente
lunga. La classificazione può partire manuale (`Camminata`/`Corsa`); una
classificazione automatica va aggiunta soltanto con test e soglie trasparenti.
Mai sommare la stima dei passi alla distanza GPS dello stesso intervallo:
deduplicare per intervallo e provenienza.

### 3. UX minima

Aggiungere una schermata `Movimento` separata dal Todo con:

- passi di oggi;
- distanza stimata di oggi, chiaramente marcata;
- pulsanti `Avvia camminata` e `Avvia corsa`;
- sessione attiva con durata, distanza, passo e accuratezza;
- cronologia locale compatta ed export esplicito.

Nessuna card salute nella home Todo, nessuna notifica persistente fuori da una
sessione GPS e nessun polling BLE in background.

## Roadmap Amazfit Bip U

Gadgetbridge su Codeberg è stato studiato al commit
`c585908b1c38d949273e8d277208a1fd548d6271`. È AGPLv3: non copiarne o adattarne
codice nel progetto MIT. La decisione attuale è un’implementazione indipendente
basata su osservazioni autorizzate del proprio Bip U e fixture sintetiche. Se
si desidera riusare Gadgetbridge, fermarsi e documentare prima il passaggio
dell’intero lavoro derivato ad AGPLv3.

Ordine sicuro:

1. collaudare scansione e batteria con Zepp chiusa;
2. implementare autenticazione Huami minima con test a byte e chiave solo dal
   Keystore, senza log;
3. acquisire e documentare servizi/caratteristiche del proprio dispositivo,
   rimuovendo MAC, chiave e dati sanitari dalle fixture;
4. scaricare in sola lettura l’elenco e i campioni delle attività;
5. conservare record grezzi immutabili e una rappresentazione normalizzata con
   provenienza;
6. allineare GPS e campioni dell’orologio usando timestamp UTC, stimando offset
   e segnalando drift/discontinuità;
7. importare battito, passi/cadenza e durata solo quando realmente presenti;
8. mostrare battito live esclusivamente se il protocollo del Bip U lo supporta
   in modo verificato;
9. estendere il GPX con namespace standard compatibile, mantenendo un test di
   round-trip.

Restano vietati aggiornamenti firmware, factory reset, scrittura di risorse o
impostazioni e comandi BLE non indispensabili alla lettura.

## Test richiesti per il prossimo incremento

- delta del contatore, duplicati, valori fuori ordine, reboot e reset;
- attraversamento della mezzanotte, cambio Europe/London↔Europe/Rome e ora
  legale/solare;
- nessun doppio conteggio tra stima e sessione GPS;
- migrazione Room da database esistente con sessioni e punti;
- permission denied/permanently denied e dispositivo senza step counter;
- consumo a riposo misurato su Galaxy S21;
- camminata reale, corsa reale, due minuti da fermo e schermo spento;
- GPX senza coordinate personali nelle fixture;
- BLE soltanto con fixture sintetiche e prova hardware esplicita.

Comandi minimi prima del push:

```sh
flutter analyze
flutter test
./gradlew :runtracker:testDebugUnitTest
flutter build apk --release --split-per-abi \
  --dart-define-from-file=supabase/config.json
```

Per una modifica funzionale aggiornare anche README, STATUS, TODO_NEXT,
CHANGELOG e versione/build. Non dichiarare superato un collaudo GPS, sensori o
BLE senza prova sul Galaxy S21/Bip U reale.

## Segreti e dati sensibili

Non inserire mai in chat, Git, log, diagnostica o fixture:

- chiave Huami;
- MAC dell’orologio;
- coordinate/GPX reali;
- battito o dati sanitari personali;
- credenziali Supabase, GitHub o Play Console.

La publishable key Supabase è configurazione client; service role, chiavi di
firma e token di release restano segreti. Il modulo movimento rimane locale per
impostazione predefinita e richiede una decisione distinta prima di qualunque
backup cloud.

## Primo task consigliato al nuovo agente

Implementare un MVP di passi **solo telefono**, senza BLE:

1. definire schema/migrazione Room e API repository;
2. aggiungere il lettore `TYPE_STEP_COUNTER` con gestione reboot e data civile;
3. esporre passi odierni e distanza stimata nella schermata Movimento;
4. rinominare l’avvio corrente in `Avvia corsa` e aggiungere
   `Avvia camminata` riusando lo stesso servizio GPS parametrico;
5. aggiungere test deterministici e misure batteria;
6. pubblicare una build Android collaudabile;
7. solo dopo il collaudo iniziare l’autenticazione Huami in sola lettura.
