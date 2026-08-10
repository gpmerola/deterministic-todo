# Deterministic Todo

Gestore personale di attività Flutter, offline-first e senza pubblicità,
analytics o collaborazione. Android è l’app nativa principale; macOS e Windows
usano la stessa interfaccia dal browser.

Distribuito con licenza [MIT](LICENSE).

## Piattaforme

- **Android 8 o successivo:** app firmata, aggiornata automaticamente tramite
  il manifest pubblico e APK separati per CPU. Il minimo API 26 deriva dal
  client stabile Health Connect usato dal modulo Movimento.
- **Browser desktop:** web app Flutter pubblicata su GitHub Pages. Usa la stessa
  struttura minimale di Android con un adattamento per mouse, tastiera e
  schermi larghi; conserva un database SQLite locale persistente e si
  sincronizza con Android tramite Supabase.
- **macOS e Windows nativi:** non più distribuiti. I vecchi launcher e target
  sono stati rimossi per evitare versioni divergenti.

URL web previsto:

`https://gpmerola.github.io/deterministic-todo/`

Informativa privacy:

`https://gpmerola.github.io/deterministic-todo/privacy.html`

### Aprirla automaticamente con Chrome

In Chrome apri **⋮ → Impostazioni → All’avvio**, scegli **Apri una pagina
specifica o un insieme di pagine**, premi **Aggiungi una nuova pagina** e
incolla l’URL web qui sopra. Da quel momento la web app si aprirà come scheda
ogni volta che avvii Chrome.

## Uso quotidiano

Al primo accesso da un nuovo browser vai in **Impostazioni**, inserisci la stessa
email e la stessa password personale usate su Android e premi **Collega**. La
sessione resta memorizzata nel browser; non usare la password GitHub.

SQLite locale resta la fonte immediata dell’interfaccia. Supabase replica task,
progetti, sezioni, ricorrenze e tombstone tra dispositivi senza bloccare l’uso
offline. Non aprire la web app in navigazione in incognito e non cancellare i
dati del sito se vuoi conservare la copia offline.

## Funzioni principali

- Oggi, Prossime e Progetti con UI minimale;
- date civili senza ora, stabili tra fusi e ora legale;
- linguaggio naturale italiano evidenziato (`oggi`, `domani`, `ogni martedì`,
  `ogni 3 giorni`, `ogni terzo martedì`, date annuali e altre varianti);
- ricorrenze che generano la prossima occorrenza al completamento;
- priorità P1–P4 con ordinamento automatico;
- Undo e Cestino per attività, progetti e sezioni;
- descrizioni e link Todoist leggibili senza URL estesi;
- import Todoist incrementale oppure **Sostituisci** solo per i dati Todoist;
- export/import JSON e CSV;
- export esplicito verso Google Calendar esclusivamente su Android.
- modulo Android isolato **Movimento** con passi del telefono tramite Health
  Connect, distanza e calorie attive stimate, sessioni GPS, archivio Room
  separato ed export GPX.

## Movimento e corsa (Android)

La sezione principale **Movimento**, accanto a **Progetti**, richiede una
volta l'accesso ai passi in Health Connect. Il conteggio di sistema può quindi
continuare anche quando l'app non è aperta; alla riapertura l'app importa in
modo idempotente il totale aggregato della giornata, evitando la somma diretta
di record sovrapposti.

Durante una sessione i passi sono letti anche direttamente dal contatore
hardware Android e mostrati come **Passi sessione · sensore telefono**. Il
valore continua ad aggiornarsi a schermo spento insieme al servizio GPS e resta
distinto dal totale giornaliero Health Connect.

Nelle camminate, quando il contatore hardware è disponibile, gli intervalli
GPS senza nuovi passi restano nella diagnostica ma non incrementano la
distanza. Alla ripartenza il primo passo riabilita il collegamento GPS
plausibile; corsa e dispositivi senza sensore conservano il filtro GPS come
fallback.

La distanza quotidiana e le calorie attive sono per ora stime esplicite basate
su passi, falcata e peso predefiniti. Non sono ancora calibrate sul profilo
personale e non vanno considerate misure cliniche o equivalenti a Google Fit
finché non superano il confronto controllato sul Galaxy S21.

Da **Movimento** si avvia una traccia GPS del
telefono. Una notifica persistente mantiene la registrazione attiva anche a
schermo spento e consente di terminarla. La schermata mostra durata, distanza,
passo medio e accuratezza corrente.

Alla fine della sessione l'app attende la sincronizzazione, legge da Health
Connect i record attribuiti a Google Fit nello stesso intervallo e mostra
distanza, passi, calorie attive e scarto. Il confronto viene inoltre aggiunto
automaticamente al JSON diagnostico su Drive. Il comando manuale resta negli
strumenti avanzati come recupero. Google Fit deve aver condiviso quei dati con
Health Connect; i valori assenti restano esplicitamente non disponibili.

Il modulo conserva localmente in `run_tracker.sqlite` tutti i campioni: quelli
validi alimentano la distanza, quelli esclusi conservano il motivo
(`poor_accuracy`, `implausible_speed_jump`, `gps_zigzag`, rumore da fermo o
timestamp non valido). L'export GPX include la traccia accettata e i punti
scartati come waypoint diagnostici. Questi dati non entrano nel database Todo,
nei backup Todo o nella sincronizzazione Supabase.

Per i collaudi ripetuti selezionare una sola volta **Collega cartella Google
Drive per i test** e scegliere `Deterministic Todo Movement Tests`. Al termine
di ogni sessione l’app crea automaticamente due file omonimi: GPX e JSON
diagnostico completo. La schermata mostra l'esito della scrittura e permette di
riesportare idempotentemente l'ultima attività se il provider era temporaneamente
indisponibile. Il provider Drive gestisce la sincronizzazione; l’app non contiene
credenziali Google. I file includono dati personali di posizione e non devono
essere resi pubblici o versionati.

La prima prova BLE cerca il Bip U e legge soltanto il servizio standard della
batteria, quando esposto. La chiave Huami opzionale viene cifrata con Android
Keystore e non viene mai inserita in log o repository. Autenticazione Huami,
download delle sessioni, allineamento con GPS e battito live restano disattivati
finché l'implementazione indipendente non sarà validata su hardware. Non sono
presenti funzioni di aggiornamento firmware.

## Import e reimport Todoist

Da **Impostazioni → Dati e manutenzione → Importa da Todoist** seleziona il JSON
più recente.

- **Aggiorna** aggiunge e aggiorna i record Todoist senza duplicati.
- **Sostituisci** ricostruisce progetti, sezioni e attività provenienti da
  Todoist, eliminando quelle assenti dal nuovo export. Le task create
  direttamente nell’app restano intatte.

Titolo, descrizione, link Markdown, progetto, sezione, priorità, data civile e
ricorrenza sono conservati. Commenti, allegati, filtri, reminder e sotto-attività
non sono ancora modellati.

## Sincronizzazione Supabase

La configurazione client usa soltanto Project URL e publishable key. Sono valori
pubblici protetti dalle policy RLS; una `service_role` non deve mai entrare nel
client. Sul progetto personale devono essere state applicate, nell’ordine:

1. `supabase/migrations/202608040001_initial.sql`;
2. `supabase/migrations/202608040002_todoist_import.sql`;
3. `supabase/migrations/202608050001_realtime_sync.sql`.
4. `supabase/migrations/202608080001_references.sql`.

Le modifiche locali vengono inviate appena entrano nell’outbox. Supabase
Realtime avvisa immediatamente gli altri dispositivi, che aggiornano SQLite e
quindi l’interfaccia senza ricaricare la pagina. Il canale si riapre dopo
errori o timeout; il controllo ogni dieci minuti mentre l'app è visibile rimane come
recupero dopo assenza di rete o sospensione del processo.
Gli eventi ravvicinati vengono accorpati e scaricano soltanto gli ID cambiati.

Il composer accetta data e ricorrenza naturali insieme a `#Nome progetto` e
`p1`–`p4`, ricorda il progetto recente ma parte sempre senza priorità e rende
leggibili i link incollati. Su desktop `Esc` torna indietro; selezionare una
task apre sulla destra l'editor completo senza un
secondo dialogo. Invio fisico conferma il titolo sia in creazione sia in modifica;
nelle descrizioni rimane un normale a capo. Non sono attive scorciatoie globali
di creazione o ricerca: `Esc` chiude o torna indietro senza interferire con la
scrittura. Clic destro e pressione lunga
aprono le sole azioni essenziali.
Gli avvisi temporanei possono essere chiusi immediatamente con la `X`; quando
si completa una ricorrenza mostrano anche la data della prossima occorrenza.
In Oggi, le attività non concluse nei giorni precedenti restano visibili in un
gruppo Arretrate separato, senza modificare automaticamente la loro data.
La cancellazione tramite swipe richiede un gesto lungo da destra verso sinistra:
la riga rivela chiaramente Cestino, conferma la soglia con feedback tattile e si
riassesta con un movimento controllato; Undo rimane disponibile.
Il completamento usa invece una spunta circolare immobile: conferma subito il
tocco e chiude gradualmente la riga soltanto dopo aver mostrato il risultato,
senza rimbalzi o cambi di dimensione del controllo.
Titolo e descrizione rispondono con un feedback leggero sull'intera riga; gli
stati vuoti restano una sola riga discreta. Sul Web una sincronizzazione non
interrompe la bozza aperta nel pannello laterale.
La ricerca copre anche progetti e URL e offre filtri compatti. “Salute dati”
nelle Impostazioni raccoglie sync, outbox, backup, quantità locali e versione
senza aggiungere indicatori alla home.
Priorità, date e ricorrenze hanno anche descrizioni accessibili indipendenti
dal colore; l'app rispetta testo di sistema, alto contrasto e navigazione da
tastiera. Sul Web SQLite WebAssembly e il worker Drift vengono precaricati,
mentre le inizializzazioni indipendenti partono in parallelo.

La creazione di nuovi account è disabilitata nel progetto Supabase. I dispositivi
esistenti si collegano con l’account personale già creato.

## Aggiornamenti

Ogni modifica funzionale verificata incrementa versione e build.

- L'unico workflow `Publish Android and Web Release` esegue analisi e test una
  volta, compila entrambe le piattaforme e pubblica Android soltanto dopo che il
  nuovo client web è online.
- `release-info.json` sul sito e il manifest Android devono dichiarare la stessa
  versione, build e commit; la pipeline li confronta dopo la pubblicazione.
- Il browser riceve la versione nuova senza installer.

La build Android diretta controlla gli aggiornamenti all’avvio e ogni sei ore
mentre è in primo piano. La build Google Play interroga l’API ufficiale dopo il
primo frame e al ritorno in primo piano: se esiste una nuova versione, mostra il
prompt flessibile dello Store senza interrompere l’uso. Il controllo manuale è
disponibile nelle Impostazioni. Il browser aggiorna la pagina direttamente dal
sito.

## Sviluppo

Richiede Flutter stable 3.44.7 o compatibile e Dart 3.12.

```sh
flutter pub get
dart run build_runner build
flutter analyze
flutter test
flutter run -d chrome --dart-define-from-file=supabase/config.json
flutter run -d <android-device-id> --dart-define-from-file=supabase/config.json
```

Build locali:

```sh
flutter build web --release --dart-define-from-file=supabase/config.json
flutter build apk --release --split-per-abi \
  --dart-define-from-file=supabase/config.json
```

Struttura canonica:

- `lib/domain/`: date, ricorrenze e parser puro;
- `lib/data/local/`: schema Drift e connessioni SQLite native/web;
- `lib/data/sync/`: outbox, conflitti Lamport e Supabase;
- `lib/services/`: import/export, diagnostica, calendario e aggiornamenti;
- `lib/ui/`: impostazioni, editor, task, componenti testuali e link;
- `assets/branding/`: sorgenti SVG canoniche dell'icona, da cui derivano i PNG
  Android e web;
- `web/`: shell browser e asset SQLite WebAssembly;
- `android/`: client Android;
- `android/runtracker/`: modulo corsa nativo, database Room, GPS, GPX e BLE;
- `supabase/migrations/`: schema remoto e RLS;
- `tools/launchers/`: utilità Android opzionali.

## Dati, privacy e limiti

Titoli e note restano nel database locale e, dopo il collegamento, nel progetto
Supabase personale. Non entrano nei log. La diagnostica registra soltanto
conteggi e metriche tecniche in due blocchi rotanti da 512 KiB: file applicativi
su Android e IndexedDB nel browser. Nessun log viene inviato automaticamente.

Il Cestino conserva tombstone sincronizzati. La cancellazione simultanea e
definitiva di dispositivo e cloud non è ancora offerta: richiede una funzione
Supabase transazionale. Il reset locale richiede prima di scollegare Supabase,
altrimenti i dati verrebbero scaricati nuovamente.

Il punto di ingresso per riprendere lo sviluppo è
[docs/HANDOFF.md](docs/HANDOFF.md). La documentazione tecnica è in
[docs/ARCHITETTURA.md](docs/ARCHITETTURA.md), le procedure sono in
[docs/operations/](docs/operations/), lo stato corrente in [STATUS.md](STATUS.md),
le versioni in [CHANGELOG.md](CHANGELOG.md) e il lavoro residuo in
[TODO_NEXT.md](TODO_NEXT.md).
