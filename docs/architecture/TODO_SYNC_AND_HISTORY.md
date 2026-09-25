# Sincronizzazione attività e storico locale

## Incidente e decisione — build 171

Il 7 settembre 2026 il ciclo Android delle 10:29:15–10:29:36 Europe/Rome ha
inviato nove attività con cinque tentativi di rebase. Il contatore diagnostico
`rebased_entities` storico contava tentativi, non necessariamente entità distinte.
Dalla 171 il campo mantenuto per compatibilità conta i retry CAS, non rebase
dell'intera riga. I log aggregati non permettono di attribuire ogni campo perso a una singola
attività. La riproduzione sintetica ha però confermato il difetto:
`activateScheduled` scriveva prima del primo pull; `_uploadTaskVerified`
rilanciava tutta la copia locale con un contatore superiore a quello remoto,
ripristinando anche campi mai modificati sul telefono.

La build 171 elimina questa mutazione di avvio. Una data civile programmata
minore o uguale a oggi rende l'attività visibile in Oggi senza cambiare stato,
versione o outbox. Il confronto usa la data civile corrente del dispositivo.

## Contratto di scrittura

SQLite resta la fonte della UI. Le modifiche volontarie e l'outbox sono una sola
transazione. Lo schema payload 2 distingue:

- `create`: snapshot iniziale, applicabile quando l'UUID non esiste sul server;
- `patch`: soltanto campi cambiati rispetto alla versione mostrata all'utente;
- `replace`: snapshot scelto esplicitamente tramite ripristino o importazione.

Una modifica da un editor rimasto aperto rilegge il record nella transazione:
i campi invariati nell'editor non sostituiscono modifiche ricevute nel frattempo.
I valori null sono scritti esplicitamente anche in Drift, mai convertiti in
campi assenti. Il contatore supera sia la riga attuale sia il massimo osservato.

Il writer legge l'ultima riga remota, applica gli intenti catturati e invia un
UPDATE condizionato a UUID, versione e dispositivo della riga appena letta.
La condizione viene valutata da Postgres nella stessa scrittura: se un altro
client è intervenuto, zero righe aggiornate significano rileggere e riprovare
(max quattro tentativi). Le INSERT conservano UUID e vincoli di unicità.
Per il writer delle attività introdotto nella 171 non occorrono nuove tabelle, credenziali amministrative o RPC sul server:
si usano le policy RLS esistenti per SELECT/INSERT/UPDATE dell'utente autenticato.

Politica dei conflitti: i campi toccati da un intento volontario pendente
prevalgono; gli altri campi provengono dalla versione remota corrente. Le
versioni contrapposte sono conservate nello storico. Una normale modifica non
resuscita una tombstone; solo un ripristino esplicito può sostituire la versione.
La creazione ripetuta dello stesso UUID non sovrascrive una riga già esistente.

La rete non viene attesa dentro transazioni SQLite. Il pull controlla outbox e
versione corrente nella stessa transazione della scrittura, anche per Realtime.
Una riga con intenti pendenti non può essere sovrascritta dal pull. L'ack elimina
solo gli operation ID catturati: modifiche durante l'invio restano pendenti.

## Retry ed esiti incerti

Prima dell'UPDATE, l'outbox conserva privatamente la coppia remota prima/dopo
attesa. Dopo una risposta accettata marca gli intenti `confirmed`, prima della
ricevuta tecnica: un fallimento successivo non riapplica modifiche già inviate.
Se la risposta va persa, il retry confronta la riga con quella attesa:

1. identica al risultato atteso: conferma senza riscrivere;
2. identica alla base precedente: può ritentare;
3. diversa da entrambe: conserva tutto e segnala un conflitto da risolvere.

Questo è un protocollo conservativo, non una garanzia di transazione distribuita
fra due database. L'incertezza viene resa visibile anziché risolta con un rebase
cieco. Gli errori transitori seguono il backoff esistente; i conflitti di intento
richiedono una scelta nello storico. Le ricevute `sync_operations` contengono
metadati e nomi dei campi, mai snapshot, titoli o note nei nuovi invii.

Le outbox precedenti non hanno intenti recuperabili: se il contenuto remoto è
diverso, il client conserva coda e copie e chiede una scelta esplicita. Anche
collisioni di ricorrenze con UUID differenti conservano entrambe le versioni:
non vengono più risolte sovrascrivendo automaticamente la copia canonica.

### Isolamento dei rifiuti e Realtime — build 181

Prima della 181 un `PostgrestException` non riconosciuto su una singola entità
interrompeva l'intero ciclo: le entità successive non venivano inviate e il
pull non partiva, a ogni tentativo. Una riga rifiutata per vincolo (per esempio
una collisione di ricorrenza non riconciliabile) poteva quindi fermare la
convergenza di tutto l'account, pur con la UI che dichiarava il contrario.

- SQLSTATE di classe `22` (dato) e `23` (integrità) riguardano la riga inviata:
  il gruppo viene marcato `server_rejected`, il ciclo prosegue con le altre
  entità e con il pull. La riga resta protetta dall'outbox e viene ritentata
  al ciclo successivo; non viene scartata né sovrascritta.
- Autenticazione, RLS (`42501`), `P0001` applicativi come `forbidden`, schema e
  trasporto continuano a interrompere il ciclo con backoff invariato.
- Un errore successivo nel ciclo non sovrascrive i marker per entità già scritti.
- Il fetch Realtime delle task usa lotti da 100 ID come progetti e sezioni. Se
  fallisce, gli ID già tolti dalla coda non vengono persi: parte un controllo
  completo, che con l'overview costa una richiesta se nulla è cambiato.
- `sync(freshSnapshot: true)`, usato all'evento `subscribed`, non si unisce a un
  controllo che ha già iniziato la lettura remota: accoda un ciclo successivo.
  Gli altri trigger continuano a condividere il ciclo in corso.

Test: `test/sync_isolation_test.dart` (rifiuto isolato e ritentato, marker
conservato dopo errore di trasporto, errore di account che ferma il ciclo,
snapshot fresco, lotti Realtime, fallback dopo fetch fallito).

### Ripresa breve allo sblocco — build 185

Sul Galaxy il provider ha registrato alle 19:24:59 e 19:37:00 UTC un solo
controllo completo fallito (`overview`, `ClientException`, coda zero) con lo
schermo spento. Il registro eventi Android (`logcat -b events`) mostra per
entrambi `wm_resume_activity` circa 7 s prima, seguito entro 1–1,3 s da
`wm_pause_activity userLeaving=true` e `wm_stop_activity`: allo sblocco il
sistema riporta brevemente in primo piano l'ultima attività. La ripresa avvia
Realtime e un controllo completo; `pause()` non interrompeva il ciclo, che
proseguiva in background fino al fallimento del trasporto, senza retry perché
in pausa, lasciando lo stato `error` fino alla riapertura. Il caso delle
18:51:32 precede il buffer eventi disponibile e non è ricostruito.

`pause()` annulla ora le richieste di un ciclo che non ha intenti in coda
(`_activeHasUploads` falso dopo la lettura dell'outbox; vero finché non è
letta). L'esito è `sync_cancelled`, non un errore; la ripresa successiva esegue
un nuovo controllo completo. Un ciclo con invii prosegue sempre.

### Avvio in background — build 184

`SyncService.start()` avviene nell'inizializzazione asincrona, prima che lo
stato dell'app registri l'osservatore del ciclo di vita; le transizioni
intermedie non vengono consegnate. `initState` legge ora
`WidgetsBinding.lifecycleState` e applica subito la pausa se lo stato è
`hidden`, `paused` o `detached` (`isBackgroundLifecycle`). Non era la causa
dei controlli falliti a schermo spento, descritti nella build 185.

### Invii in blocco, eco Realtime e divergenza — build 183

- All'inizio dell'invio le righe remote delle attività in coda sono lette con
  `id=in.(...)` a lotti di 100. Il writer usa la riga in blocco solo al primo
  tentativo e solo senza tentativi incerti; l'UPDATE resta condizionato a
  versione e dispositivo, quindi una scrittura concorrente produce zero righe,
  una nuova lettura e l'unione degli intenti come prima.
- Ricevute `sync_operations` in blocchi da 200 dopo l'ultimo gruppo, poi una
  sola transazione locale elimina esattamente gli operation ID catturati e
  unisce le righe accettate. Se l'invio si interrompe, le ricevute già
  maturate vengono tentate prima di propagare l'errore; in ogni caso le
  scritture restano `confirmed` e il ciclo successivo invia solo la ricevuta.
- Realtime conserva per ID la versione Lamport annunciata (null se assente,
  per esempio in una cancellazione). Una notifica con versione minore o uguale
  a quella locale non viene riscaricata; ogni caso incerto viene scaricato.
- `unresolvedTaskBuckets` ricalcola, dopo il download, le impronte dei soli
  gruppi scaricati ed esclude quelli con intenti locali in coda. Il valore è
  diagnostico: una scrittura successiva allo snapshot conta una volta, un valore
  ripetuto tra cicli indica una divergenza non riparabile dal pull.

Test: `test/sync_throughput_test.dart`.

### Ciclo di vita e indicatore — build 182

- `SyncService.pause()` e `resume()` sono idempotenti: `resume()` annulla solo
  una pausa effettiva. L'app sospende la sync su `hidden`, `paused` e
  `detached`, non su `inactive`, che su Android e sul Web indica un'interruzione
  con l'app ancora visibile.
- Se alla pausa esiste una modifica ancora in debounce, o accodata dietro il
  ciclo attivo, parte un solo invio senza pull. Il controllo completo resta
  richiesto e avviene alla ripresa. Nessun lavoro periodico in background.
- La connettività in background aggiorna solo lo stato `offline`; il controllo
  avviene alla ripresa.
- Il rinnovo di un token scaduto è già eseguito dal SDK prima di ogni richiesta
  (`GoTrueClient.getSession`, deduplicato). Un fallimento di trasporto durante il
  rinnovo resta un errore transitorio con retry; nessuna logica duplicata.
- `isBriefSyncRetry`: errore con retry programmato e al massimo due fallimenti
  consecutivi. L'indicatore è neutro e mostra l'orario del nuovo tentativo.

Test: `test/sync_foreground_test.dart`.

## Storico e privacy

### Recupero degli invii incerti — build 180

Un ripristino esplicito di attività delimita gli intenti da applicare: il writer
considera l'ultimo `replace` e le modifiche successive. I vecchi tentativi
incerti non possono bloccare la scelta già effettuata. Tutti gli operation ID
restano in coda fino alla ricevuta, e lo storico locale resta intatto. Il confine
vale anche se il ripristino è già confermato ma manca la ricevuta: non si
riattivano gli intenti precedenti. Un esito incerto del nuovo ripristino continua
invece a richiedere una nuova scelta se il server è cambiato nel frattempo.

La regressione è riprodotta in `test/sync_hardening_test.dart`: risposta persa,
modifica remota successiva, ripristini ripetuti e ulteriore modifica locale.
Prima della correzione la coda rimaneva bloccata; i test coprono anche ricevuta
persa e protezione delle modifiche remote successive. Nessuna migrazione o
risoluzione automatica di conflitti privi di una scelta esplicita è introdotta.

SQLite schema 7 aggiunge `activity_revisions`, con indici per entità/sequenza e
istante UTC. Trigger transazionali registrano insert, update e delete di
attività, progetti e sezioni; un rollback annulla anche le relative revisioni.
Ogni revisione conserva tipo/UUID, operazione, fonte, istante UTC in microsecondi
e snapshot prima/dopo. Gli invii aggiungono operation ID e fasi distinte:
`sync_attempt`, `sync_accepted`, `sync_confirmed`, `sync_conflict`.
I tentativi non sono presentati come modifiche sicuramente accettate dal server.

Lo storico è consultabile in **Impostazioni → Dati e manutenzione → Storico
attività**, oppure **editor → Altre azioni → Storico attività** per una singola
attività. La lista carica 50 revisioni per pagina con cursore sequenziale. Il
dettaglio mostra i campi cambiati. Per le attività, **Usa la versione precedente**
o **successiva** richiede una conferma e crea una nuova modifica sincronizzabile;
non cancella la cronologia. Dalla build 174 anche progetti e sezioni hanno ripristino esplicito della singola
riga; le relazioni non vengono ricreate automaticamente.

Le revisioni restano nel database locale e non entrano nei bundle diagnostici
Drive, nei log tecnici o nel normale export backup. **Esporta storico** crea un
JSON schema 1 soltanto su richiesta, avvisando che include contenuti privati.
Non inviarlo a GitHub, log o servizi di diagnostica automatica. La retention è
90 giorni, con pulizia indicizzata all'apertura del database. **Cancella tutti i
dati locali** elimina anche lo storico; svuotare il cestino lascia le revisioni
fino alla loro scadenza. Un backup dello storico va esportato separatamente.

Lo storico inizia dall'installazione: non ricostruisce revisioni precedenti né
versioni intermedie mai osservate da questo dispositivo mentre era offline.
I client vecchi conservano il proprio comportamento: per la protezione su tutti
i dispositivi occorre distribuire lo stesso aggiornamento anche sul Web.
L'app Movimento e i suoi dati/scheduler non sono modificati.

## Verifica e diagnosi futura

Comandi canonici: `make check`, `make check-generated`, `make todo-test`.
Test mirati: `test/sync_data_loss_test.dart`, `test/activity_history_test.dart`,
`test/database_migration_test.dart`, `test/task_editor_date_test.dart`.
Il trasporto simulato verifica la condizione CAS, mantiene un server sintetico e
copre concorrenza, tombstone, retry, risposta persa, coda legacy e recupero.
I test SQLite verificano rollback, riapertura, eliminazioni e migrazione.

Per un nuovo incidente: annotare ora/fuso e dispositivo; aprire lo storico
filtrato della task; confrontare fonte, versioni/dispositivi e operation ID.
Distinguere ricezione remota, tentativo, accettazione e conflitto. Esportare solo
il materiale autorizzato; i log tecnici aggregati continuano a descrivere
connessione, fase ed esito generale senza contenuti. Non usare retry manuali
ripetuti o ripristini massivi prima di avere conservato le copie utili.

## Persistenza Web — build 172

Il collaudo della 171 ha riprodotto separatamente la perdita di una modifica e
relativa revisione al refresh, senza Supabase configurato. La creazione iniziale
restava salvata. In Drift 2.34.3 `_WasmDelegate._runWithArgs` salta il flush
IndexedDB quando `isInTransaction` è true; `COMMIT` passa da quel ramo prima che
`_StatementBasedTransactionExecutor._release` azzeri il flag. Una lettura
successiva non esegue il flush, mentre una scrittura fuori transazione sì.

Riscontri canonici:
[delegate Wasm](https://github.com/simolus3/drift/blob/drift-2.34.3/drift/lib/wasm.dart),
[executor transazioni](https://github.com/simolus3/drift/blob/drift-2.34.3/drift/lib/src/runtime/executor/helpers/engines.dart),
[modalità di persistenza Web](https://drift.simonbinder.eu/platforms/web/).
La 2.34.4 documenta soltanto un cambiamento sull'estensione rowid: non viene
aggiornata una dipendenza senza evidenza che corregga questo problema.

`WebTransactionFlush` usa l'interfaccia pubblica `QueryInterceptor`, soltanto
sulla connessione Web. Dopo il completamento della transazione esterna esegue
`runCustom('SELECT 1')` sul parent: una query senza mutazioni che attraversa il
flush già implementato nel worker. Lo stesso vale per rollback; i savepoint
annidati non eseguono flush prematuri. Nessun timer, duplicazione del database,
patch della cache o aggiornamento degli asset vendorizzati. Un errore di storage
resta un errore, non viene ignorato. Test: `test/web_transaction_flush_test.dart`;
prova decisiva: modifica e storico conservati dopo refresh e chiusura scheda.

## Estensione build 174

Intenti progetti/sezioni, conflitti isolati, pull paginato e registro delle
eliminazioni definitive sono descritti in [Todo UX hardening](TODO_UX_HARDENING.md).
Il registro richiede una nuova migrazione server; disponibilità in
[STATUS](../../STATUS.md).
