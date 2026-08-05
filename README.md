# Attività deterministiche

Applicazione Flutter nativa per Android, macOS e Windows. Non contiene target web, analytics, pubblicità, AI o collaborazione. Il principio è: **“Ogni attività resta dove l’hai messa. Ogni regola fa esattamente ciò che dichiara.”**

Distribuita con licenza [MIT](LICENSE).

## Avvio facile con doppio clic

I launcher sono nella cartella principale, così sono immediatamente visibili:

- macOS: doppio clic su `AVVIA_MAC.command`;
- controllo macOS: `CONTROLLA_REQUISITI_MAC.command` distingue Xcode completo dai soli Command Line Tools;
- Android da macOS: collega il telefono o avvia un emulatore, poi doppio clic su `AVVIA_ANDROID.command`;
- APK senza Android SDK locale: `SCARICA_APK_ANDROID.command` scarica la build ARM64 per Galaxy S21; `INSTALLA_APK_ANDROID.command` la installa via ADB quando disponibile oppure apre la cartella da trasferire al telefono;
- Windows: doppio clic su `AVVIA_WINDOWS.bat`;
- per generare file installabili: usa `CREA_APP_INSTALLABILI.command` su macOS oppure `CREA_APP_WINDOWS.bat` su Windows.
- senza Xcode locale: usa `SCARICA_APP_MAC.command`; scarica e apre l'ultima build prodotta dal repository GitHub privato.
- dopo il primo download: usa semplicemente `APRI_ATTIVITA_MAC.command` per aprire l'app; se manca, avvia automaticamente il download.

Al primo avvio il sistema può chiedere di autorizzare l’esecuzione. Su macOS, se Finder la blocca, fai clic destro sul file `.command`, scegli **Apri**, quindi conferma **Apri**.

### Propagare una modifica a macOS e Android

Android è il primo canale di collaudo. Ogni incremento funzionale completo e verificato incrementa obbligatoriamente versione e build in `pubspec.yaml`; il push su un branch `agent/**` avvia automaticamente test, compilazione firmata, APK separati per CPU, pubblicazione `latest` e verifica del manifest pubblico. Non serve più avviare manualmente la pubblicazione ordinaria. Verify, build APK separata e macOS restano manuali per evitare di compilare due volte lo stesso commit; il workflow manuale con conferma `PUBBLICA` è un recupero controllato.

L'app Android controlla il piccolo manifest pubblico a ogni apertura, dopo il primo frame e senza bloccare l'interfaccia. Se trova una versione superiore, seleziona l’APK per la CPU, verifica SHA-256 e lo scarica dentro l’app senza aprire GitHub. Il controllo manuale resta nelle Impostazioni. Android richiede comunque una sola conferma di sistema finale: un'app installata fuori dal Play Store non può sostituirsi silenziosamente.

Perché una modifica sia visibile, il numero versione/build deve essere nuovo: il workflow rifiuta una release duplicata invece di pubblicare un aggiornamento invisibile. `RELEASE_REPO_TOKEN` resta limitato in scrittura al solo repository `deterministic-todo-releases`; chiave di firma e password restano nei GitHub Actions Secrets.

### macOS senza sudo o Mac App Store

Scarica `Xcode.xip` dalla pagina [Apple Developer Downloads](https://developer.apple.com/download/all/) con un Apple Account gratuito, estrailo e sposta `Xcode.app` in `~/Applications/`. Apri Xcode una volta per accettare licenza e componenti. I launcher rilevano questa posizione e impostano `DEVELOPER_DIR` soltanto per il processo corrente: non chiamano `sudo` e non cambiano `xcode-select` globale. Apple conferma che `xcodebuild` è incluso soltanto nell'app Xcode completa; i Command Line Tools non bastano.

## Architettura

La UI usa sempre SQLite locale tramite Drift. `TaskRepository` applica comandi transazionali e registra la stessa modifica nell'outbox persistente. Il repository contiene `SyncService`, merge Lamport, migrazione Supabase e accesso persistente: dopo un solo collegamento la sessione viene conservata nel keychain/keystore e rinnovata automaticamente. La sincronizzazione live richiede ancora un progetto Supabase configurato e una prova reale tra due dispositivi. Le regole complete sono in [docs/ARCHITETTURA.md](docs/ARCHITETTURA.md); il prossimo lavoro è in [TODO_NEXT.md](TODO_NEXT.md).

Directory principali:

- `lib/domain`: tipi e regole pure;
- `lib/data/local`: schema SQLite Drift e migrazione iniziale;
- `lib/data/sync`: conflitti e worker offline-first;
- `lib/services`: calendario, diagnostica e import/export;
- `lib/main.dart`: bootstrap, navigazione e composizione delle viste;
- `lib/ui/`: componenti UI riutilizzabili per link Todoist e input naturale;
- `supabase/migrations`: schema PostgreSQL, funzione di merge e RLS.

## Avvio locale

Richiede Flutter stable 3.44 o compatibile e Dart 3.12.

```sh
flutter pub get
dart run build_runner build
flutter analyze
flutter test
flutter run -d macos       # su macOS
flutter run -d windows     # su Windows
flutter run -d <android-device-id>
```

Il database è creato nella directory Application Support della piattaforma con WAL e foreign key abilitate. Il device UUID è nel secure storage di sistema.

## Collegamento Supabase persistente

La build configurata mostra in Impostazioni il collegamento a un account personale. Si crea o collega l'account una sola volta su ogni dispositivo; il refresh della sessione è automatico e la sessione è salvata nel secure storage nativo. “Scollega questo dispositivo” è l'unica azione che rimuove volontariamente la sessione locale. Non esiste ancora pairing tramite QR/codice né un registro server per revocare a distanza un singolo dispositivo.

URL e publishable key Supabase sono configurazioni client pubbliche incluse in `supabase/config.json`; non concedono poteri amministrativi e le tabelle restano protette da RLS. Chi pubblica un fork deve collegarlo a un proprio progetto Supabase. Non usare mai `service_role` nel client.

Prima di usare la sincronizzazione, eseguire una volta nell'SQL Editor, come proprietario del progetto, `supabase/migrations/202608040001_initial.sql` e poi `supabase/migrations/202608040002_todoist_import.sql`. La seconda migrazione è obbligatoria prima dell'import Todoist e aggiunge progetti, sezioni, priorità e relativi merge protetti. I launcher e le build CI passano automaticamente la configurazione tramite `--dart-define-from-file=supabase/config.json`. Per una configurazione alternativa:

```sh
flutter run -d macos \
  --dart-define-from-file=supabase/config.example.json
```

Le policy RLS limitano entrambe le tabelle a `auth.uid() = user_id`. `merge_task` accetta soltanto record dell'utente autenticato e aggiorna solo se `(logical_version, device_id)` è maggiore. La chiave pubblica può stare nella configurazione di build; sessioni e device ID sono nel keychain/keystore. Nessuna chiave amministrativa è necessaria o ammessa.

## Inserimento rapido e agenda Android

La riga “Nuova attività” crea con Invio e interpreta localmente, senza rete, espressioni italiane comuni: `oggi`, `domani`, `dopodomani`, giorni della settimana, date `GG/MM` e mesi in lettere. Prima di salvare, una riga di anteprima mostra la pianificazione riconosciuta. L'app non supporta orari: espressioni come `alle 18` restano testo normale, Todoist viene importato come data civile e Google Calendar riceve eventi giornalieri. Le vecchie colonne SQLite/Supabase restano soltanto per compatibilità di schema e vengono normalizzate a `null`. Il parser rimuove dal titolo soltanto le espressioni riconosciute e rifiuta date impossibili.

Le ricorrenze rapide accettano `ogni giorno`, `ogni martedì`, `ogni 4 giorni`, `ogni 3 settimane`, `ogni 2 mesi`, `ogni 3 del mese`, `ogni terzo martedì`, `ogni 3 luglio` e `ogni anno`. La frase viene evidenziata e rimossa dal titolo. Completare un'occorrenza la conserva nella cronologia e crea automaticamente la successiva, avanzando oltre eventuali date arretrate senza generare duplicati.

In elenco, le attività ricorrenti mostrano la frase riconosciuta, per esempio **↻ ogni giorno**, **↻ ogni domenica** o **↻ ogni terzo martedì del mese**. Il completamento conferma visivamente la spunta con colore, impulso e testo barrato, quindi dissolve la riga; non introduce timer quando l'app è inattiva. P1, P2 e P3 usano una sottile banda e una tinta rispettivamente rossa, arancione e blu; P4 resta neutra. Le attività sono ordinate automaticamente dalla priorità più alta alla più bassa, mantenendo un ordine stabile a parità di livello. L'import Todoist conserva lo stesso mapping (`priority: 4` nel JSON corrisponde a P1).

Toccando un'attività su Android si apre un foglio minimale dal fondo, alto al massimo 460 px: titolo e una barra compatta per data, priorità e ripetizione restano immediatamente raggiungibili; note, scadenza, progetto e stato sono raccolti nella sezione comprimibile **Altri dettagli**. La lista non ripete più “Mostra” quando il giorno è già espresso dalla vista Oggi o Prossime. Il colore della priorità è applicato direttamente al cerchio di completamento, senza una bandierina separata.

Sono supportati anche `ogni giorno feriale`, `ogni weekend` (sabato), `ogni ultimo giorno del mese`, `ogni ultimo venerdì del mese`, `ogni 3 giorni dopo il completamento`, `stasera` (20:00), `questo weekend`, `inizio settimana prossima`, `fine mese`, `tra 3 giorni` e `fra 2 settimane`.

“Prossime” è una timeline verticale lazy che include anche i giorni senza attività con un'indicazione discreta. Non usa più una seconda barra di quadratini: **Vai a data** è l'unico comando superiore e sposta direttamente l'inizio della timeline senza aggiungere un livello alla navigazione Indietro. Su Android il menu `⋮` dell'editor consente di creare o aggiornare esplicitamente l'attività nel Google Calendar primario; non avviene alcun export automatico. L'ingranaggio nell'AppBar apre Impostazioni anche sugli schermi mobili.

Su telefono, il pulsante `+` apre in 80 ms un composer compatto dal bordo inferiore, sopra la tastiera: titolo, riconoscimento naturale e invio restano in un solo passaggio. Un pulsante Note apre immediatamente una descrizione opzionale e il pallino priorità permette di scegliere P1–P4 senza aprire l'editor completo. Le espressioni comprese — per esempio `oggi`, `domani` e `venerdì` — vengono evidenziate in tempo reale e poi rimosse dal titolo; una sintassi non valida non riceve il falso segnale visivo.

La navigazione Android è ridotta a **Oggi**, **Prossime** e **Progetti**. Completate è raggiungibile dalle Impostazioni senza occupare la navigazione primaria; Inbox e In attesa restano stati compatibili nel database e nella versione desktop. Le attività Inbox senza data compaiono in Oggi, ma l'eventuale progetto tecnico “Inbox” importato da Todoist non viene mostrato come progetto autonomo. Prossime genera pigramente giorni fino a dieci anni, senza contatori o il filtro ridondante “Tutte”, e offre **Vai a data** per saltare immediatamente lontano nel calendario. Progetti appare come vista dedicata e mantiene sezioni e attività attive importate.

Il tasto **Indietro** di Android chiude prima dialoghi e menu, poi ripercorre le sezioni visitate; in Prossime rimuove prima l'eventuale filtro sul giorno. Soltanto dalla radice Oggi, esaurita la cronologia interna, lascia chiudere normalmente l'app.

Nel composer mobile una sola pressione di **Indietro** chiude tastiera e foglio insieme; le transizioni sono 30/20 ms e l'adeguamento alla tastiera non è animato, evitando il breve accavallamento tra IME e foglio. I testi di esempio e le istruzioni permanenti sotto i campi sono rimossi: appare soltanto l'esito utile di una data o ricorrenza effettivamente riconosciuta.

Le Impostazioni mostrano lo stato reale del worker in una sola riga con icona: sincronizzazione in corso, numero di modifiche in attesa, ultimo completamento oppure errore. Account e comandi meno frequenti restano nel menu contestuale. Trigger simultanei di accesso, riconnessione e timer confluiscono in una sola esecuzione, evitando lavoro di rete duplicato.

Progetti usa una navigazione gerarchica minimale: un elenco iniziale con colore e nome apre il dettaglio del progetto; Indietro torna all'elenco prima di lasciare la sezione. Il dettaglio mostra soltanto nome, sezioni e attività, senza dropdown, conteggi o bacheca. ID, colori, sezioni e mapping esterni restano invariati e compatibili con import e reimport Todoist.

La schermata Impostazioni mantiene in primo piano soltanto collegamento, aggiornamenti e attività completate. Backup, CSV, import Todoist e diagnostica sono raccolti nella sezione comprimibile **Dati e manutenzione**; il testo Privacy ridondante è stato rimosso dall'interfaccia, senza cambiare le garanzie descritte in questo documento.

## Build installabili

```sh
flutter build macos --release
flutter build windows --release
flutter build apk --release
# distribuzione Android raccomandata, circa 19–23 MB per file:
flutter build apk --release --split-per-abi
# oppure Android App Bundle:
flutter build appbundle --release
```

Windows va compilato su Windows con Visual Studio 2022 e workload “Desktop development with C++”. macOS va compilato su macOS con Xcode/CocoaPods. Android richiede Android SDK e JDK compatibile con Gradle (JDK 17–25 per il wrapper generato). Firma e identity di distribuzione vanno configurate localmente prima della pubblicazione.

La CI Android usa una chiave release stabile salvata esclusivamente nei GitHub Actions Secrets e genera APK separati `arm64-v8a`, `armeabi-v7a` e `x86_64`. Il fallback universale serve soltanto a portare updater precedenti alla versione capace di scegliere l’ABI. Regole, misure e procedura completa sono in [docs/ANDROID_PERFORMANCE_E_AGGIORNAMENTI.md](docs/ANDROID_PERFORMANCE_E_AGGIORNAMENTI.md).

## Dati e backup

Localmente sono salvati task, note, date, ricorrenze, tombstone, impostazioni e outbox. Finché Supabase e pairing non sono configurati, nessun task viene sincronizzato remotamente. Nessun contenuto viene inviato altrove o scritto nei log.

Le notifiche orarie sono state rimosse insieme ai relativi plugin, permessi, receiver Android e database dei fusi. Le date restano civili e non cambiano attraversando fusi orari o ora legale.

Su Android, “Salva + calendario” crea esplicitamente un evento nel calendario Google primario già configurato sul dispositivo; in assenza di Google usa il primo calendario modificabile secondo un ordine stabile. L’ID restituito dal provider Android viene conservato localmente: ripetere il comando aggiorna lo stesso evento e non crea duplicati. Non esiste importazione automatica dal calendario e SQLite resta la fonte di verità. Il fuso viene letto come identificatore IANA nativo (`Europe/London`, per esempio), funziona offline e segue le regole DST senza dipendere da Google o dall’orologio di rete.

Impostazioni consente export JSON completo/versionato, export CSV e import JSON. Prima dell'import mostra conteggi di aggiunte, aggiornamenti e record invariati; vince solo una versione logica superiore, quindi non avvengono sovrascritture silenziose.

“Importa da Todoist” accetta l'export JSON, mostra obbligatoriamente il riepilogo e importa soltanto attività attive insieme a progetti, sezioni, descrizioni, priorità, date civili e ricorrenze. **Aggiorna** esegue un reimport incrementale: aggiunge le novità e aggiorna solo i record Todoist modificati, senza duplicati e senza riaprire le attività già completate nell'app. **Sostituisci** richiede una seconda conferma e ricostruisce da zero esclusivamente i dati provenienti da Todoist, rimuovendo quelli assenti dal nuovo file; le attività native dell'app non vengono toccate. L'operazione SQLite è atomica. Prima di confermare sul telefono va applicata la seconda migrazione Supabase indicata sopra.

Titolo e descrizione sono importati separatamente da Todoist. La descrizione appare sotto il titolo su una sola riga; il testo completo resta disponibile aprendo l'attività. I link Markdown presenti in entrambi vengono mostrati con la sola parola associata, sottolineata e cliccabile; l'URL completo resta nel dato originale ma non ingombra l'elenco. L'export attualmente supportato non contiene commenti, allegati o sotto-attività importabili.

Anche nell'editor le descrizioni mostrano soltanto il testo leggibile: gli URL Todoist non appaiono più in chiaro. Per collegare o scollegare una parola basta selezionarla e usare **Aggiungi link** o **Togli link**; il formato Markdown compatibile con Todoist viene ricostruito soltanto al salvataggio.

Lo swipe sposta l'attività nel cestino soltanto da destra verso sinistra e dopo aver superato il 62% della riga; mostra sempre **Annulla**. Il ripristino riusa la stessa attività e lo stesso identificatore, preservando la sincronizzazione.

La vista Progetti usa un elenco verticale con sezioni comprimibili. Si possono creare progetti con colore, aggiungere sezioni e attività direttamente nella destinazione usando lo stesso composer rapido, e spostare un'attività cambiando progetto/sezione dall'editor. Il menu `⋮` di progetti e sezioni permette di rinominare, spostare su/giù ed eliminare con **Annulla**; l'eliminazione è un'archiviazione reversibile e non cancella le attività associate. L'eventuale preferenza elenco/bacheca importata da Todoist resta nei metadati per compatibilità, ma non condiziona più la UI mobile. Funzioni collaborative come condivisione e commenti restano intenzionalmente escluse.

L'editor espone una sola data civile di pianificazione: da questa deriva automaticamente lo stato interno. “Stato” e “Scadenza” non sono più controlli separati. Le colonne legacy restano nello schema per permettere aggiornamenti sicuri delle installazioni esistenti, ma `due_date` viene normalizzata a `null` nelle modifiche e nella sincronizzazione.

Completate carica al massimo le 200 attività più recenti, in ordine di completamento e con righe più dense. Le attività completate da oltre 365 giorni vengono archiviate con tombstone sincronizzato, così la cronologia non cresce senza limite. In **Dati e manutenzione** è disponibile **Cancella tutti i dati locali**: opera in una transazione unica e conserva soltanto l'identità tecnica del dispositivo; richiede prima di scollegare Supabase per evitare che il cloud ripristini subito i dati.

Il controllo aggiornamenti avviene all'avvio, al ritorno in primo piano se sono trascorse almeno sei ore e ogni sei ore mentre l'app è visibile. Dieci minuti sarebbero troppo frequenti per una release che cambia raramente.

Android e macOS mantengono un log diagnostico locale JSONL con rotazione automatica a 512 KiB e una sola copia precedente. Registra soltanto eventi tecnici, conteggi, piattaforma e tipi/codici di errore; non registra titoli, note, email, token o URL. Il file può essere condiviso esplicitamente da Impostazioni → Esporta diagnostica.

## Limiti noti della prima versione

- Il collegamento account è persistente, ma QR/codice monouso, revoca remota del singolo dispositivo e verifica end-to-end contro un progetto Supabase reale non sono ancora completati.
- Lo stato sync nell'interfaccia è informativo ma non è ancora collegato in tempo reale allo stream del worker.
- Il cestino conserva correttamente tombstone, ma manca la schermata di ripristino.
- La selezione multipla e l'undo generale non sono ancora implementati.
- Le ricorrenze da calendario sono generate dal motore idempotente, ma manca ancora il job periodico che estende automaticamente l'orizzonte.
- La cifratura dei backup è predisposta come confine di servizio, non implementata.

## Verifica

`flutter analyze` applica lint rigorosi. `flutter test` copre date civili/DST, anni bisestili, mensili ancorati, arretrati, conflitti, persistenza/outbox, tombstone, idempotenza delle ricorrenze e creazione rapida UI. Le verifiche effettivamente eseguite sono registrate in [COMPLETATO.md](COMPLETATO.md).

Per riprendere il lavoro in una nuova sessione, iniziare da [TODO_NEXT.md](TODO_NEXT.md).
