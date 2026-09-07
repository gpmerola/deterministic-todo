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
Non occorrono nuove tabelle, credenziali amministrative o RPC sul server:
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

## Storico e privacy

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
non cancella la cronologia. Progetti e sezioni sono consultabili, non ripristinati
automaticamente con le loro relazioni.

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
