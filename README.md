# Deterministic Todo

Gestore personale di attività Flutter, offline-first e senza pubblicità,
analytics o collaborazione. Android è l’app nativa principale; macOS e Windows
usano la stessa interfaccia dal browser.

Distribuito con licenza [MIT](LICENSE).

Passi: dalla build 190 Android conserva solo il conteggio quotidiano dei passi
del telefono; GPS, Amazfit, Health Connect e diagnostica Movimento sono
[archiviati](docs/archive/MOVIMENTO.md) per ridurre peso e consumo di batteria.

Dalla build 172 la sincronizzazione applica solo i campi modificati e impedisce
che il cambio di giorno ripubblichi copie vecchie. **Impostazioni → Dati e
manutenzione → Storico attività** conserva 90 giorni di revisioni locali,
consultabili, esportabili e ripristinabili per singola attività. Architettura,
privacy e limiti: [sincronizzazione e storico](docs/architecture/TODO_SYNC_AND_HISTORY.md).

La build 179 corregge una scansione remota incompleta causata dall'ordinamento
delle pagine e rende osservabili pagine, righe e conflitti. Diagnosi, test e
limiti: [paginazione sync](docs/architecture/TODO_SYNC_PAGINATION.md).
Disponibilità effettiva Android/Web: [STATUS](STATUS.md).

La build 189 fa dipendere la pianificazione dalla sola data, definisce le viste
una sola volta in SQLite, rimuove `due_date` e il riconoscimento dell'Inbox per
nome: un vecchio progetto "Inbox" si converte con **Azioni progetto → Sposta in
Inbox**. Dettagli: [pianificazione e viste](docs/architecture/TODO_PLANNING_MODEL.md).

La build 180 corregge il ripristino di attività dopo un invio incerto: la scelta
fatta nello storico supera gli intenti precedenti e conserva le modifiche
successive. Cronologia e ricevute restano protette; dettagli nel
[contratto di sincronizzazione](docs/architecture/TODO_SYNC_AND_HISTORY.md).

## Piattaforme

- **Android 8 o successivo:** app firmata, aggiornata automaticamente tramite
  il manifest pubblico e APK separati per CPU (minimo API 26).
- **Browser desktop:** web app Flutter pubblicata su GitHub Pages. Usa la stessa
  struttura minimale di Android con un adattamento per mouse, tastiera e
  schermi larghi; conserva un database SQLite locale persistente e si
  sincronizza con Android tramite Supabase.
- **macOS e Windows nativi:** non più distribuiti. I vecchi launcher e target
  sono stati rimossi per evitare versioni divergenti.

URL web previsto:

`https://gpmerola.github.io/deterministic-todo/`

Le attività storiche rimaste senza data e non assegnate a un progetto sono
gestibili da **Impostazioni → Attività senza data**. Possono essere rimosse
singolarmente o tutte insieme; la cancellazione viene sincronizzata e resta
recuperabile dal Cestino finché questo non viene svuotato esplicitamente.

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

Per togliere la pianificazione, apri l’attività, premi **Senza data** (oppure la
**X** accanto alla data) e **Salva**. La scelta resta anche dopo la riapertura:
un’attività di progetto rimane nel progetto e non compare più in Oggi o Prossime.
Puoi assegnarle di nuovo una data dal pulsante **Data**.

## Funzioni principali

- Oggi, Prossime e Progetti con UI minimale;
- date civili senza ora, stabili tra fusi e ora legale;
- linguaggio naturale italiano evidenziato (`oggi`, `domani`, `ogni martedì`,
  `ogni 3 giorni`, `ogni terzo martedì`, date annuali e altre varianti);
- data odierna implicita nelle nuove attività del composer; nell’editor la
  scelta **Senza data** resta salvata, con comportamento identico su Android e Web;
- ricorrenze che generano la prossima occorrenza al completamento;
- priorità P1–P4 con ordinamento automatico;
- Undo e Cestino per attività, progetti e sezioni;
- descrizioni e link Todoist leggibili senza URL estesi;
- import Todoist incrementale oppure **Sostituisci** solo per i dati Todoist;
- backup JSON versionato con attività, progetti, sezioni e preferenze Todo;
  ripristino atomico e compatibilità con il formato precedente; export CSV;
- export esplicito verso Google Calendar esclusivamente su Android.
- contapassi Android isolato: passi del telefono tramite la Recording API
  locale e obiettivo giornaliero, in un archivio Room separato.

## Calendario (Android)

Il Calendario ha una palette dedicata: superfici neutre, fasce delle date
in grigio-azzurro e accenti blu per «Oggi» e comandi. I colori dei calendari
restano distinti, con fondi più tenui per gli eventi, nei temi chiaro e scuro.
I testi degli eventi restano a piena opacità anche nei giorni passati.
La conferma «Nascosto in Todo» sparisce dopo 6 secondi, con X e «Annulla»;
gli eventi nascosti restano ripristinabili da «Calendari e filtri».

La sezione **Calendario** riunisce i calendari già sincronizzati dal telefono:
Google e gli account Microsoft 365 configurati nelle app di sistema. Offre
4 settimane (predefinito iniziale: corrente più le tre successive), mese,
3 settimane (corrente più due), 2 settimane,
settimana, 3 giorni ed elenco. Il cambio
vista conserva la data selezionata. L’ultima vista scelta viene salvata sul
dispositivo e ripristinata alla riapertura; i filtri sono espliciti e azzerabili.

In tutte le viste del Calendario, almeno tre visite consecutive dello stesso
calendario, con pause fino a 15 minuti tra la fine di una visita e l’inizio
della successiva, diventano un blocco con intervallo e numero di visite. Toccandolo
si vedono tutti gli orari e si apre il singolo evento. Pause oltre 15 minuti, sovrapposizioni
e altri tipi di appuntamento restano separati; nessun evento viene modificato.
Su Android, **Calendario → ⋮ → Aggiungi alla schermata Home** propone un'icona
che apre direttamente questa sezione, previa conferma del launcher.

L'editor conserva una bozza locale recuperabile e rimane aperto se il
salvataggio fallisce. Mostra calendario di destinazione, data finale e durata;
Android permette di scegliere un fuso IANA per nuovi eventi. Una copia «solo
in Todo» è indipendente dall'originale, che viene nascosto soltanto in Todo;
un tentativo ripetuto aggiorna la stessa copia. «Nascondi» offre «Annulla».

Con sincronizzazione attiva, il telefono invia a Supabase una copia per il
Web; le scritture Web vengono applicate dal telefono. Il backup Agenda
comprende gli eventi del calendario locale e le scelte, mentre le bozze
restano sul dispositivo. I calendari esterni continuano a usare la propria
sincronizzazione. Dettagli e limiti: [agenda unificata](docs/architecture/AGENDA.md).

## Passi (Android)

L'anello nell'AppBar mostra i passi del giorno civile rispetto all'obiettivo
(10.000 se non impostato, da 1.000 a 100.000). Toccandolo si apre un pannello
con il totale, lo stato della raccolta, il pulsante per concedere il permesso
**Attività fisica** quando manca e la modifica dell'obiettivo, disponibile anche
in **Impostazioni**.

I passi vengono dalla Recording API locale di Play Services, senza account,
GPS, Bluetooth o servizi in primo piano. Android importa i minuti completi ogni
3 ore in background; con l'app visibile l'anello si aggiorna una volta al
minuto. I dati restano sul dispositivo nel database `run_tracker.sqlite`,
separato dal dominio Todo e mai sincronizzato con Supabase.

Il vecchio modulo **Movimento** (sessioni GPS, Amazfit Bip U, Health Connect,
distanza e calorie stimate, export Drive) è archiviato nel tag
`archive/movimento-completo-b189`; contenuto, dati conservati e ripristino in
[Movimento archiviato](docs/archive/MOVIMENTO.md).

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
3. `supabase/migrations/202608050001_realtime_sync.sql`;
4. `supabase/migrations/202608080001_references.sql`;
5. `supabase/migrations/202608310001_purge_trash.sql`;
6. `supabase/migrations/202609110001_safe_purge.sql`;
7. `supabase/migrations/202609110002_ledger_privileges.sql`;
8. `supabase/migrations/202609110003_task_fingerprints.sql`;
9. `supabase/migrations/202609110004_sync_overview.sql`;
10. `supabase/migrations/202610040001_agenda_mirror.sql` (Agenda sul Web);
11. `supabase/migrations/202610050001_agenda_requests.sql` (modifiche
    all'Agenda dal Web).

Procedura e recovery: [registro delle eliminazioni](docs/operations/SAFE_PURGE.md).

Le modifiche locali vengono inviate appena entrano nell’outbox. Supabase
Realtime avvisa immediatamente gli altri dispositivi, che aggiornano SQLite e
quindi l’interfaccia senza ricaricare la pagina. Il canale si riapre dopo
errori o timeout; il controllo ogni dieci minuti mentre l'app è visibile rimane come
recupero dopo assenza di rete o sospensione del processo.
Gli eventi ravvicinati vengono accorpati e scaricano soltanto gli ID cambiati.
Il client conserva il massimo contatore Lamport osservato e applica gli intenti
per campo alla versione remota corrente con UPDATE condizionale. L'outbox viene
riconosciuta soltanto dopo conferma; una modifica concorrente causa rilettura,
mentre un esito incerto conserva le copie nello storico per una scelta esplicita.

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
La ricerca copre anche progetti e URL, offre filtri compatti e mostra prima
le attività attive, fino a 100 risultati. “Salute dati”
nelle Impostazioni raccoglie sync, outbox, backup, quantità locali e versione
senza aggiungere indicatori alla home. Dalla build 154 conserva nell'apertura
corrente anche fase e ora dell'ultimo problema Todo, retry, recupero e ultimo
successo, senza mostrare o registrare contenuto delle attività.
Il bundle diagnostico rolling su Drive, configurato dalla scheda Movimento, è
archiviato dalla build 190: la diagnostica Todo resta locale e leggibile via ADB.
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

Per sviluppo rapido il flavor Android `dev` appare come **Todo Test** e si
installa accanto alla versione Google Play senza toccarne dati o firma.
Database, sessione, Keystore, permessi e servizi sono separati; procedura ADB e
passaggio sicuro sono in
[`docs/operations/ANDROID_DEV_CHANNEL.md`](docs/operations/ANDROID_DEV_CHANNEL.md).
Sul telefono di collaudo Todo Test è l'unico client da usare; la build Play è
conservata disabilitata come fallback. Non sono intercambiabili in-place e non
condividono database, Keystore, permessi o diagnostica. Solo le attività Todo
convergono tramite Supabase quando un client viene aperto e autenticato.

## Sviluppo

Richiede Flutter stable 3.44.7 o compatibile e Dart 3.12.

La [mappa della documentazione](docs/README.md) distingue fonti correnti,
architettura, runbook ed evidenze storiche. Il controllo locale canonico è:

```sh
flutter pub get
make check-generated
make check
```

```sh
flutter pub get
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
- `android/runtracker/`: contapassi nativo (Recording API) e database Room;
- `supabase/migrations/`: schema remoto e RLS;
- `tools/launchers/`: utilità Android opzionali.

## Dati, privacy e limiti

Titoli e note restano nel database locale e, dopo il collegamento, nel progetto
Supabase personale. Non entrano nei log. La diagnostica registra soltanto
conteggi e metriche tecniche in due blocchi rotanti da 512 KiB: file applicativi
su Android e IndexedDB nel browser. Sul canale Android di collaudo questi eventi
minimizzati confluiscono nel bundle privato Drive già autorizzato; un provider
ADB protetto espone soltanto il riepilogo tecnico del sync e non apre SQLite.

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

### Todo: editor e sincronizzazione

Descrizione e collegamenti sono direttamente accessibili nell’editor; le bozze
restano locali. Prossime riparte in cima al cambio schermata e carica 30 giorni
per volta. Il pulsante cloud mostra gli elementi in attesa e rimanda allo storico.
Contratto, migrazione server e collaudo sintetico: [Todo UX hardening](docs/architecture/TODO_UX_HARDENING.md).

Backup e gestione delle richieste: [contratto Todo](docs/architecture/TODO_BACKUP_AND_LIFECYCLE.md).

La sincronizzazione dalla build 177 confronta impronte delle versioni prima di
scaricare le attività; protocollo, compatibilità e recovery sono descritti in
[sincronizzazione compatta](docs/architecture/TODO_SYNC_PERFORMANCE.md).

Dalla build 178 un controllo unificato evita le richieste delle tabelle invariate;
SQLite 10 conserva le impronte con invalidazione transazionale. Stato e collaudi
sono in [STATUS](STATUS.md).
