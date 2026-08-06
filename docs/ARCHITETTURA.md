# Architettura tecnica

## Confini

Un solo client Flutter/Dart genera l’app nativa Android e la web app per Chrome/Edge su macOS e Windows. La UI legge e scrive esclusivamente SQLite locale; Supabase non è mai nel percorso critico dell'interfaccia. Android usa `NativeDatabase` in background e il browser usa `WasmDatabase` con OPFS o IndexedDB. Se il browser offre soltanto memoria volatile, il bootstrap fallisce esplicitamente per evitare falsi salvataggi. Il codice è diviso in `domain` (regole pure), `data/local` (Drift/SQLite), `data/sync` (outbox e Supabase), `services` (calendario, diagnostica e import/export) e `ui`.

## Dati e tempo

`tasks` conserva UUID v4, proprietario, titolo, note, stato, `show_date` e `due_date` legacy come date civili ISO `YYYY-MM-DD`, posizione manuale, ricorrenza, serie/occorrenza, metadati di versione e tombstone. Le colonne orarie legacy restano nullable solo per compatibilità. Le date civili non vengono convertite in UTC: questo impedisce che cambino giorno attraversando un fuso. Gli istanti (`created_at`, `updated_at`, `completed_at`, `deleted_at`) sono microsecondi UTC Unix.

Lo schema locale 4 prepara importazioni esterne complete e rende idempotente il recupero di migrazioni interrotte: `projects` e `project_sections` conservano gerarchia e ordine, mentre `tasks` aggiunge priorità, riferimenti progetto/sezione e la coppia univoca `external_source`/`external_id`. Gli identificativi esterni servono soltanto a rendere l'import idempotente; gli UUID interni restano l'identità usata dall'app e dalla sincronizzazione.

L'import Todoist separa tre fasi: parsing/anteprima senza scritture, piano tipizzato validato e applicazione in una singola transazione SQLite. Importa solo record attivi; progetti, sezioni e task ricevono UUID v5 stabili derivati dall'ID Todoist. I checkpoint `updated_at` permettono reimport incrementali senza duplicati. La modalità di sostituzione riattiva e sovrascrive i record presenti nel file e applica tombstone/archiviazione ai soli record Todoist assenti, così la cancellazione si propaga in modo sicuro nella sincronizzazione. Il sync remoto applica lo stesso confronto Lamport a task, progetti e sezioni.

La posizione è un intero a 64 bit. Il riordino assegna posizioni spaziate in una transazione atomica, ma salta righe che hanno già il valore desiderato per evitare scritture e outbox inutili. I pareggi sono risolti sempre da `created_at`, quindi UUID.

## Macchina degli stati

Gli stati persistiti sono `inbox`, `available`, `scheduled`, `waiting`, `completed`. Solo comandi espliciti completano, eliminano o spostano una task. La vista effettiva tratta una task `scheduled` con `show_date <= data locale corrente` come `available`; una manutenzione idempotente materializza la transizione impostando `available`. Nessuna scadenza viene modificata. Ripetere la manutenzione produce lo stesso risultato.

## Viste e ordine

Oggi usa gruppi esclusivi con precedenza: (1) scadenza oggi, (2) scaduta, (3) mostra oggi, (4) disponibile senza data. Dentro ogni gruppo: posizione, creazione, UUID. Prossime raggruppa `scheduled` con `show_date > oggi`, prima per data e poi con lo stesso ordinamento manuale. Ricerca titolo/note è locale, case-insensitive, e ordina per stato, posizione, creazione, UUID.

Le viste attive osservano uno stream SQLite che esclude completate e tombstone; Completate usa uno stream separato. Gli stream sono creati una volta per shell e supportati dagli indici della migrazione locale 2. Questo mantiene fuori dalla RAM la cronologia non pertinente.

Il controller del composer usa gli stessi pattern del parser per costruire gli span evidenziati, mantenendo feedback visivo e salvataggio coerenti. L'agenda genera pigramente soltanto i giorni visibili, fino a dieci anni, e usa un date picker per i salti lunghi: non apre stream, timer o richieste di rete aggiuntivi.

Dalla 2.9.0 l'unica data applicativa visibile è `show_date`, una data civile senza ora. Lo stato operativo viene derivato da essa nell'editor (`inbox` senza data, `available` fino a oggi, `scheduled` nel futuro). `due_date` resta una colonna legacy nullable per compatibilità con database e backend già distribuiti, ma il client la normalizza a `null` e non la usa per liste, ordinamento o calendario. I componenti riutilizzabili del testo Todoist e dell'evidenziazione naturale vivono in `lib/ui/`, separati dall'orchestrazione di `main.dart`.

Progetti e sezioni non vengono cancellati fisicamente: “Elimina” imposta `is_archived`, conserva attività e identificatori esterni e offre Undo immediato. Rinomina, archiviazione e scambio delle posizioni incrementano `logical_version` e aggiornano `device_id`, così il merge Supabase conserva l'ordinamento scelto e resta deterministico.

La cronologia completata è una vista limitata alle 200 righe più recenti. All'avvio, i completamenti oltre 365 giorni diventano tombstone tramite lo stesso repository e la stessa outbox delle eliminazioni normali; non vengono rimossi direttamente dal file SQLite. Il reset locale usa una singola transazione e preserva `device_id`; è bloccato nella UI finché Supabase è collegato, perché una cancellazione soltanto locale verrebbe altrimenti annullata dal pull remoto.

Le note continuano a usare Markdown Todoist come formato persistente canonico, ma `LinkTextEditingController` lo converte in testo semplice durante l'editing e ricostruisce i link al salvataggio. La UI non espone URL grezzi e non richiede un nuovo schema o una dipendenza Markdown.

Il Cestino è una proiezione di tombstone attività (`deleted_at`) e archivi di progetto/sezione (`is_archived`). Il ripristino aggiorna lo stesso record e lo stesso ID; non crea copie. L'eliminazione fisica non è esposta perché rimuovere prima SQLite e poi Supabase, o viceversa, lascerebbe uno stato parziale in caso di rete interrotta. Un reset totale richiederà una RPC Supabase eseguita in una singola transazione server-side, seguita dal reset locale soltanto dopo conferma del commit remoto.

Le ricorrenze naturali sono regole calendario persistite, non testo decorativo. Al completamento l'occorrenza corrente diventa storica e il repository inserisce atomicamente la successiva con la stessa serie. L'ID dell'occorrenza è un UUID v5 derivato da `(series_id, occurrence_key)`: Android e browser generano lo stesso record anche offline. L'indice sugli stessi campi rende l'operazione idempotente; per i record storici creati prima dell'ID deterministico, un eventuale conflitto `23505` viene riconciliato sul record remoto canonico applicando il confronto Lamport e sostituendo localmente l'alias perdente. Giorni e settimane avanzano come date civili, mesi e anni mantengono il giorno ancora con clamp deterministico per mesi corti e anni bisestili.

## Budget runtime e aggiornamenti

Il bootstrap non carica database dei fusi e non richiede permessi di notifica: il supporto orario è assente e le date sono sempre civili. Il controllo del piccolo manifest release avviene una volta a ogni apertura, post-frame e senza bloccare la UI. Un unico workflow verifica il codice una volta, costruisce web e APK per ABI, distribuisce prima il browser e pubblica Android soltanto dopo il successo web. Manifest Android e `release-info.json` web espongono versione, build e commit e vengono confrontati pubblicamente. Il dettaglio operativo e i budget sono in [ANDROID_PERFORMANCE_E_AGGIORNAMENTI.md](ANDROID_PERFORMANCE_E_AGGIORNAMENTI.md).

Le migrazioni locali verificano colonne e tabelle prima di crearle. Dallo schema 4 una migrazione interrotta può quindi riprendere senza cancellare il database o ripetere operazioni già applicate.

## Fuso del dispositivo e calendario Android

Le pianificazioni sono esclusivamente date civili `YYYY-MM-DD`: non contengono un istante né un fuso e quindi non slittano attraversando mezzanotte, ora legale o confini geografici. Gli anni bisestili sono gestiti dal calendario civile locale. Le colonne legacy `time_minutes` e `time_zone` restano nello schema sincronizzato per compatibilità, ma ogni nuovo comando le normalizza a `null`.

Il comando esplicito “Salva + calendario” interroga il Calendar Provider Android, preferisce deterministicamente un calendario Google primario e crea un evento di 30 minuti oppure un evento giornaliero se manca l’ora. La coppia task/evento è salvata in `app_settings`; ripetere il comando aggiorna l’evento esistente. Non c’è pull dal calendario, nessun evento modifica una task e nessun export parte automaticamente.

## Ricorrenze

Una serie ha UUID e tipo esplicito. `calendar` supporta giorno, settimana e mese con intervallo e ancoraggio. Il giorno mensile viene limitato all'ultimo giorno del mese (es. 31 gennaio → 29 febbraio bisestile → 31 marzo, sempre calcolato dall'ancora). Ogni occorrenza ha chiave univoca `(series_id, occurrence_key)`, dove la chiave è la data civile prevista. La generazione inserisce senza modificare le occorrenze precedenti e ignora una chiave già presente.

`afterCompletion` genera solo al completamento; la data deriva dalla data civile locale del completamento più l'intervallo. Anche qui la chiave stabile rende il comando idempotente. I calcoli avvengono su date civili, non aggiungendo 24 ore a un istante, quindi i cambi DST non spostano l'ora locale.

## Sincronizzazione e conflitti

Ogni transazione utente aggiorna SQLite e aggiunge un'operazione all'outbox persistente. `operation_id` è UUID e il server lo registra con vincolo univoco: ritentare dopo crash non duplica l'operazione. L'outbox avvia subito il push; gli eventi PostgreSQL Realtime filtrati per `user_id` accodano soltanto gli ID modificati. Dopo 120 ms il ricevente esegue query `IN` separate per task, progetti e sezioni e applica il merge Lamport; gli stream Drift aggiornano quindi la UI senza refresh. Chiusure, errori e timeout del canale causano una nuova sottoscrizione dopo due secondi; la sottoscrizione riuscita forza un pull completo. Il timer di un minuto è una seconda rete di recupero in foreground per eventi persi, rete assente o processi sospesi. Eventi arrivati durante un sync impostano un secondo passaggio, evitando finestre di perdita. L'ack rimuove l'elemento solo dopo conferma remota.

Ogni record porta una versione Lamport `(logical_version, device_id)`. Prima di modificare, il client imposta `logical_version = max(versione locale, massimo remoto osservato) + 1`. Vince la coppia massima in ordine lessicografico: prima contatore, poi UUID stabile del dispositivo. Questa regola include i tombstone e rende la convergenza indipendente dall'orologio. Gli orari UTC sono audit, mai arbitri del conflitto.

Supabase usa JWT client e RLS `auth.uid() = user_id`; nel client entrano soltanto URL e chiave anon/publishable. Il primo collegamento usa l'account personale condiviso sui propri dispositivi. La sessione viene rinnovata automaticamente e persiste tramite `flutter_secure_storage`: keystore su Android e storage cifrato dal browser. Non è richiesto un login quotidiano. La disconnessione è esplicita e locale; QR/codice monouso e revoca remota per dispositivo richiedono ancora Edge Functions e schema server dedicato. I tombstone restano almeno 90 giorni; la pulizia fisica è una futura procedura server consapevole dei checkpoint dei dispositivi.

## Inserimento rapido e agenda

`QuickAddParser` è una regola pura, locale e testabile. Estrae dal testo italiano una data civile, poi restituisce il titolo ripulito; la stessa regola alimenta l'anteprima durante la digitazione. URL `http://`, `https://` e `www.` vengono convertiti localmente nel formato Markdown canonico e resi cliccabili in titolo e descrizione, inclusi gli import Todoist. Una data futura crea direttamente una task `scheduled`; oggi crea `available`; senza data resta `inbox`. Il repository salva titolo, stato e pianificazione nella stessa transazione con l'outbox. La vista Prossime ordina prima per `show_date` e presenta gruppi giornalieri, senza introdurre query di rete. L'esportazione calendario crea un evento giornaliero per singola attività e non altera la fonte di verità SQLite.

La creazione usa lo stesso modal bottom sheet rapido su Android e browser. Sopra 900 px il browser adatta soltanto navigazione e larghezza al mouse e alla tastiera; dominio e comandi restano identici. La timeline futura deriva dai task attivi già osservati e materializza pigramente soltanto i giorni visibili: non apre nuovi stream, timer o query di rete.

## Privacy e backup

Titoli e note risiedono nel database locale e, dopo login/sync, nel progetto Supabase dell'utente. Non ci sono analytics né logging del contenuto. La diagnostica salva esclusivamente eventi e conteggi consentiti, con versione/build e un ID casuale limitato alla singola apertura; ruota su file Android o IndexedDB browser e viene esportata soltanto su comando. JSON versionato è il formato completo e validato; CSV è interoperabile ma non costituisce un backup completo. L'interfaccia di backup separa serializzazione e destinazione, così potrà aggiungere cifratura autenticata senza cambiare il dominio.
