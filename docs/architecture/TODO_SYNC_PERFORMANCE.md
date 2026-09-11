# Sincronizzazione compatta — build 177

## Problema e protocollo

Un archivio ampio veniva riscaricato integralmente a ogni controllo. Inoltre,
ogni riga richiedeva varie query SQLite e le richieste di controllo sovrapposte
potevano accodare un secondo giro completo.

`todo_task_fingerprints_v1()` confronta le attività in 256 gruppi, identificati
dai primi due caratteri dell'UUID. Ogni impronta SHA-256 copre la concatenazione
ordinata `id:logical_version:device_id;`. La RPC restituisce un unico valore JSON,
non un set di righe soggetto al limite PostgREST. È `security invoker`, filtra
`auth.uid()`, conserva RLS e non restituisce titoli, note o UUID individuali.
SQLite costruisce le stesse firme con soli metadati, in al massimo 256 stringhe.

Il client scarica soltanto i gruppi remoti differenti, con limiti UUID inferiori
inclusivi e superiori esclusivi, pagine da 500 e conclusione su pagina vuota.
Il limite server può essere inferiore senza troncare la lettura. Progetti,
sezioni e registro delle eliminazioni restano paginati integralmente.
Una RPC assente (`PGRST202`/`42883`) mantiene il pull completo compatibile;
errori di rete, autorizzazione o formato restano errori visibili.

Non viene salvato un cursore basato su orologio o massimo Lamport: un writer
offline con contatore basso modifica comunque l'impronta. Una copia locale
incompleta viene ricontrollata senza affidarsi a checkpoint precedenti. Un gruppo
assente sul server non autorizza cancellazioni locali: resta necessario il
registro `purged_entities`. Le modifiche dopo lo snapshot server sono recuperate
tramite Realtime o il controllo successivo. Il confronto presuppone l'invariante
già esistente: ogni modifica del contenuto incrementa la versione Lamport.

Ogni pagina viene confrontata in una transazione SQLite con query aggregate per
versioni, intenti pendenti e marker di eliminazione. Solo le righe nuove o più
recenti vengono scritte; il contatore Lamport è osservato una volta per pagina.
Restano attivi CAS, tombstone, ack selettivi e controlli di cancellazione/account.
Controlli completi sovrapposti condividono il ciclo; nuovi intenti locali durante
il pull mantengono invece il giro successivo di invio.

`crypto` era già una dipendenza transitiva alla stessa versione nel lockfile;
ora è dichiarata direttamente per usare SHA-256, senza nuovo pacchetto runtime.
Non cambia lo schema SQLite 9, non viene cancellato lo storico.

## Diagnostica sicura

Il provider ADB `todo_sync_debug/status` espone durata, righe task scaricate,
numero finale di intenti e build dell'ultimo successo. `last_success_remote_rows`
conta i download, non il numero di attività verificate tramite impronta.
`unfinished` indica un avvio più recente dell'ultimo esito/cancellazione:
può essere un ciclo attivo oppure interrotto, non prova da solo un processo vivo.
`active_stage` e `active_remote_rows` descrivono l'ultimo avanzamento;
`active_pending` è la coda catturata per quel ciclo, non un conteggio in tempo reale.
Il provider conserva separatamente problema Realtime storico e stato più recente.

Nelle build precedenti `last_pending` proveniva dall'ultimo errore e non provava
che la coda corrente fosse vuota. Ora usa l'ultimo ciclo pertinente e restituisce
null se un vecchio successo non aveva il conteggio. `last_failure_pending`
conserva il valore storico. Nessun contenuto utente entra nei log.

## Applicazione e recovery server

Sorgente: [migrazione 003](../../supabase/migrations/202609110003_task_fingerprints.sql).
Prerequisiti: schema Todo esistente, SHA-256 PostgreSQL, sessione amministrativa
Supabase autorizzata. Validazione locale: `make check-sql`, con PostgreSQL PGlite,
confronto SHA-256 indipendente, rollback e isolamento tra account.
Applicare il file canonico una volta, in transazione, dopo autorizzazione alla
migrazione in produzione. Verificare `authenticated` EXECUTE true, `anon` false,
e un nuovo ciclo APK tramite i soli metadati diagnostici. Stato effettivo e
misure hardware sono in [STATUS](../../STATUS.md).

Recovery, solo se necessario e autorizzato: rimuovere la sola funzione
`public.todo_task_fingerprints_v1()` ripristina il pull completo. Non modificare
attività, registro delle eliminazioni o RLS. Il primo caricamento su dispositivo
vuoto deve ancora scaricare tutte le attività: il controllo compatto velocizza
soprattutto archivi già presenti e cambiamenti piccoli, non elimina quel costo.

Test di regressione: `test/sync_pull_performance_test.dart`, suite CAS/data loss,
`tools/sql-tests/safe_purge.mjs`, `tools/test_todo_sync_timeline.py` e integrazione
Galaxy separata `integration_test/todo_validation_test.dart`.
