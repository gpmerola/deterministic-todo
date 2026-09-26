# Backup Todo e ciclo di vita della sincronizzazione

## Backup JSON 2

`ExportService` esporta in una singola transazione SQLite attività (incluse le
completate e il cestino), progetti, sezioni e preferenze Todo trasferibili. Le
liste sono ordinate per ID e le preferenze per chiave. Il formato 1 resta
importabile, con avviso perché può non contenere la struttura dei progetti.

Le preferenze trasferibili sono `last_quick_project` e `project_view:*`.
Identità del dispositivo, sessioni, contatori Lamport, ricevute, associazioni al
calendario, marker di manutenzione e bozze non vengono trasferiti. Movimento
resta separato. Non è un'immagine del database: storico locale, outbox e registro
delle eliminazioni non sono inclusi; il ripristino genera nuovi intenti espliciti.
Il file contiene titoli e note personali in chiaro: esportazione solo esplicita,
nessun invio automatico o backup cloud aggiunto.

Prima di scrivere vengono decodificate tutte le righe, verificati formato,
campi obbligatori e ID duplicati. L'anteprima distingue attività nuove/aggiornate,
progetti, sezioni, preferenze ed elementi esclusi perché già eliminati
definitivamente sul dispositivo. Il ripristino è una singola transazione:
un errore annulla anche gerarchie, preferenze, storico aggiunto e outbox.

Gli UUID rimangono stabili. Le righe locali con versione uguale o superiore
rimangono invariate; le preferenze trasferibili del file vengono applicate.
Task/progetti/sezioni importati producono intenti `replace`, perché il ripristino
è una scelta esplicita dell'utente. I trigger SQLite riconoscono la provenienza
`backup_import`; l'import Todoist conserva il proprio comportamento. Un secondo
import dello stesso file non duplica righe o intenti. Le relazioni preesistenti
mancanti nei backup vecchi non vengono ricostruite con dati inventati.

I marker locali di purge prevalgono sul backup. Su un dispositivo nuovo il
registro server può impedire un ripristino con UUID già eliminato: non cancellare
la protezione per forzarlo; eventualmente copiare esplicitamente il contenuto in
un nuovo elemento. Ripristinare un backup non ricollega account o calendari.

## Richieste e chiusura

Ogni ciclo ordinario, pull Realtime e purge possiede uno `SyncRequestScope`,
associato all'account iniziale. Il contesto asincrono conserva questo scope anche
quando più operazioni si sovrappongono; non viene letto da un campo mutabile
condiviso con il ciclo seguente. Writer e paginazione ricevono lo stesso scope.

Logout/cambio account e `dispose` invalidano gli scope e completano il segnale
`abortSignal` del client PostgREST. Le richieste Todo hanno timeout effettivo di
20 secondi e nessun retry HTTP interno; il retry resta al servizio, con la
cadenza esistente 2/10/30/120 secondi. Il timeout abortisce il trasporto supportato
dall'SDK; non è un semplice `Future.timeout` con scritture ancora attive.

Un invio potrebbe essere già stato accettato dal server: l'annullamento non
cancella l'intento né il suo preimage. Prima di confermare o unire una risposta
si verifica che lo scope sia ancora valido. Il ciclo successivo riconcilia
l'esito incerto usando CAS e snapshot già persistiti. `dispose` interrompe timer
e sottoscrizioni, attende le operazioni tracciate e chiude gli stream; chiamate
successive non riavviano lavoro. `purgeRemoteTrash` annullato fallisce, invece di
consentire alla UI di procedere con la cancellazione locale.

La pausa in background conserva il ciclo eventualmente già avviato e sospende
la cadenza ordinaria come prima. Non sono aggiunti timer permanenti o sensori.

## Outbox e schema SQLite 9

Lo stream che rileva nuovo lavoro seleziona soltanto `operation_id`; non carica
più note e snapshot JSON ad ogni aggiornamento dei metadati. Il confronto degli
ID impedisce che aggiornare ricevute/tentativi programmi altro lavoro.

L'indice `outbox_entity_operation_idx(entity_id, operation)` serve sia la ricerca
per entità sia quella per progetti/sezioni. La migrazione 8→9 aggiunge l'indice
e aggiorna i trigger degli import preservando righe, intenti e metadati. Il ciclo
di upload continua a catturare gli intenti completi per raggrupparli e confermare
soltanto gli ID osservati: non viene introdotto un batching che separi una
sequenza di modifiche della stessa entità.

## Verifica

- `test/export_service_test.dart`: round-trip, gerarchie, preferenze,
  compatibilità v1, reimport idempotente, file malformati, rollback e purge.
- `test/sync_lifecycle_test.dart`: accettazione tardiva task/progetti, cambio
  account, purge dopo dispose, timeout/abort su server HTTP loopback reale.
- `test/outbox_efficiency_test.dart`: upgrade 8→9 preservando la coda, piano query
  indicizzato e stream su 10.000 intenti con 20 MB di payload sintetico.
- `integration_test/todo_validation_test.dart`: stessi casi sul Galaxy nel
  package isolato; nessun database personale o canale Movimento.

Eseguire `make check`, `make check-generated` e il collaudo isolato documentato in
[Todo UX hardening](TODO_UX_HARDENING.md). Usare JDK 17 per Gradle.
Esiti hardware, browser e distribuzione: [STATUS](../../STATUS.md).
