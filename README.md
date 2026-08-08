# Deterministic Todo

Gestore personale di attività Flutter, offline-first e senza pubblicità,
analytics o collaborazione. Android è l’app nativa principale; macOS e Windows
usano la stessa interfaccia dal browser.

Distribuito con licenza [MIT](LICENSE).

## Piattaforme

- **Android:** app firmata, aggiornata automaticamente tramite il manifest
  pubblico e APK separati per CPU.
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

Le modifiche locali vengono inviate appena entrano nell’outbox. Supabase
Realtime avvisa immediatamente gli altri dispositivi, che aggiornano SQLite e
quindi l’interfaccia senza ricaricare la pagina. Il canale si riapre dopo
errori o timeout; il controllo ogni minuto mentre l'app è visibile rimane come
recupero dopo assenza di rete o sospensione del processo.
Gli eventi ravvicinati vengono accorpati e scaricano soltanto gli ID cambiati.

Il composer accetta data e ricorrenza naturali insieme a `#Nome progetto` e
`p1`–`p4`, ricorda il progetto recente ma parte sempre senza priorità e rende
leggibili i link incollati. Su desktop `N` crea, `/` cerca ed `Esc` torna
indietro; selezionare una task apre sulla destra l'editor completo senza un
secondo dialogo. Invio conferma il titolo sia in creazione sia in modifica;
nelle descrizioni rimane un normale a capo. Clic destro e pressione lunga
aprono le sole azioni essenziali.
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

La documentazione tecnica è in [docs/ARCHITETTURA.md](docs/ARCHITETTURA.md), le
procedure sono in [docs/operations/](docs/operations/), lo stato corrente in
[STATUS.md](STATUS.md), le versioni in [CHANGELOG.md](CHANGELOG.md) e il lavoro
residuo in [TODO_NEXT.md](TODO_NEXT.md).
