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
2. `supabase/migrations/202608040002_todoist_import.sql`.

La creazione di nuovi account è disabilitata nel progetto Supabase. I dispositivi
esistenti si collegano con l’account personale già creato.

## Aggiornamenti

Ogni modifica funzionale verificata incrementa versione e build.

- Il workflow `Publish Android Release` esegue analisi, test, firma, build per
  ABI, pubblicazione e verifica del manifest.
- Il workflow `Publish Web App` esegue analisi, test, build web e deployment su
  GitHub Pages. Gli stessi percorsi che attivano una release Android attivano
  sempre anche il deployment web della medesima versione e dello stesso commit.
  Il browser riceve la versione nuova senza installer.

Android controlla gli aggiornamenti all’avvio e ogni sei ore mentre è in primo
piano. Il browser aggiorna la pagina direttamente dal sito.

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
- `lib/ui/`: componenti testuali e link;
- `web/`: shell browser e asset SQLite WebAssembly;
- `android/`: client Android;
- `supabase/migrations/`: schema remoto e RLS;
- `tools/launchers/`: utilità Android opzionali.

## Dati, privacy e limiti

Titoli e note restano nel database locale e, dopo il collegamento, nel progetto
Supabase personale. Non entrano nei log. La diagnostica registra soltanto
conteggi e metriche tecniche; su Android è rotante su file, nel browser resta in
memoria fino all’esportazione.

Il Cestino conserva tombstone sincronizzati. La cancellazione simultanea e
definitiva di dispositivo e cloud non è ancora offerta: richiede una funzione
Supabase transazionale. Il reset locale richiede prima di scollegare Supabase,
altrimenti i dati verrebbero scaricati nuovamente.

La documentazione tecnica è in [docs/ARCHITETTURA.md](docs/ARCHITETTURA.md), la
procedura Android in
[docs/ANDROID_PERFORMANCE_E_AGGIORNAMENTI.md](docs/ANDROID_PERFORMANCE_E_AGGIORNAMENTI.md)
e il lavoro residuo in [TODO_NEXT.md](TODO_NEXT.md).
