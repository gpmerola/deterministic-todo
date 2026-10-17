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
Il file esportato a mano contiene titoli e note personali in chiaro:
esportazione solo esplicita. Il backup automatico (sotto) è sempre cifrato.

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

## Backup automatico cifrato (Android, build 255)

Una volta attivato da Impostazioni → Dati e manutenzione → Backup automatici,
il telefono salva ogni settimana una copia cifrata del backup JSON 2, senza
altre azioni dell'utente. Il controllo avviene soltanto all'apertura e al
ritorno in primo piano, dopo il lavoro di avvio esistente: nessun timer, job,
WorkManager o polling. Se il contenuto (escluso `exported_at`) non è cambiato il
file non viene riscritto, quindi le ultime sei copie coprono più settimane. Un
errore viene ritentato al massimo una volta al giorno e non blocca l'interfaccia.

**Destinazione scelta: `Documenti/Todo backup` sul telefono, tramite
MediaStore.** Motivi: i file restano dopo una disinstallazione o la
cancellazione dei dati dell'app, sono visibili nell'app File e copiabili su un
computer o in un cloud a scelta dell'utente, non richiedono permessi di
archiviazione (Android 10+) e non aggiungono un nuovo servizio esterno. Una
copia su Supabase è stata scartata per ora: stesso fornitore della replica
principale (non protegge dalla perdita dell'account) e richiederebbe una
migrazione di produzione. Su Android 8–9 i file vanno nella cartella
documenti privata dell'app, rimossa con la disinstallazione. L'app elenca,
ruota e cancella soltanto i propri file `todo-AAAAMMGGTHHMMSSZ.tdb`.

**Cifratura.** Formato `TDB2`: intestazione di 24 byte (magic, identificativo
della chiave, IV casuale) autenticata come AAD, poi AES‑256‑GCM del JSON
compresso con gzip. La chiave dati è casuale (256 bit); per i backup non
presidiati è salvata nelle preferenze dell'app cifrata da una chiave AES non
esportabile di Android Keystore. All'attivazione l'utente vede il **codice di
ripristino** (52 caratteri base32 Crockford in gruppi di quattro), unico modo
per aprire i backup su un altro telefono o dopo una reinstallazione: va
conservato nel gestore password. Il JSON in chiaro attraversa il canale
nativo solo in memoria e non viene mai scritto su disco. Una sola chiave
Android Keystore diversa (preferenze ripristinate da un backup cloud di
Android) rende la configurazione locale non valida e richiede una nuova
attivazione; errori transitori del Keystore non cancellano nulla.

**Ripristino.** Dal foglio Backup automatici si sceglie una copia di questa
installazione oppure «Ripristina da file .tdb»: con una chiave diversa viene
chiesto il codice. In entrambi i casi segue la stessa anteprima e la stessa
importazione transazionale del backup JSON (righe locali più recenti invariate,
eliminazioni definitive rispettate). Sul Web il backup automatico non è
disponibile: la copia Web resta la replica Supabase e l'esportazione manuale.

In Salute dati «Ultimo backup» è considerato a posto con un'esportazione
manuale oppure con un backup automatico controllato nelle ultime due
settimane **e la cui ultima copia risulta ancora disponibile**. Dalla build
262 sono distinti ultimo controllo dei contenuti, ultima copia creata e
presenza della copia attesa. Le date future e l'ultimo tentativo fallito non
producono uno stato sano. Se MediaStore non risponde, lo stato è sconosciuto,
non «non attivo». La verifica legge solo metadati dei file: non certifica la
leggibilità crittografica del contenuto, che resta verificata all'anteprima.

`auto_backup_last_at` mantiene la semantica di controllo riuscito e la cadenza
esistente; `auto_backup_created_at` e `auto_backup_file` sono aggiornati solo
dopo una scrittura riuscita. `auto_backup_failed_at` registra il fallimento e
viene svuotato dopo un successo. Se manca la copia attesa, «Crea ora» la ricrea
anche quando restano copie vecchie con hash dei contenuti invariato. Su
installazioni precedenti alla 262 si mostra la data dei file esistenti; al
prossimo backup dovuto/manuale viene creata una copia con provenienza esplicita.
Nessuna migrazione SQL, modifica al formato o nuove copie all'apertura del
foglio. Il codice di ripristino resta mostrabile anche se il primo backup
fallisce: il foglio segnala il fallimento e offre «Crea ora».

Salute dati usa conteggi SQL e ricarica con trascinamento verso il basso.
Problemi di sincronizzazione raggruppa in SQLite l'ultima operazione per
entità (upsert/delete insieme, domini separati), in ordine della prima
operazione pendente. Mostra 50 entità alla volta con Precedenti/Successivi;
trasferisce al massimo 51 righe compresa la sentinella, senza payload JSON.
Una coda che cambia aggiorna la pagina corrente; dopo lo svuotamento si può
sempre tornare alla precedente. Nessuna operazione di sincronizzazione viene
modificata o eliminata da questa vista.

Nessuna nuova dipendenza: cifratura con JCA e Android Keystore in Java
(`TodoBackupCipher`, `TodoBackupFiles`, `TodoBackupMediaStore`,
`TodoBackupChannel`), compressione con `java.util.zip`.

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
- `test/auto_backup_service_test.dart`: attivazione, cadenza settimanale,
  contenuto invariato, rotazione, ritentativi, trigger concorrenti, ripristino.
- `android/app/src/test/.../TodoBackupTest.java`: cifratura, manomissione,
  chiave diversa, codice di ripristino, rotazione su cartella.
- `integration_test/auto_backup_smoke.dart`: Keystore e MediaStore reali nel
  package `.dev.validation`, solo byte sintetici, file rimossi al termine.
  Compilarlo in release con `-t` e firma Todo Test, installarlo senza runner
  Flutter e leggere l'esito con `adb logcat -s flutter:V`.

Eseguire `make check`, `make check-generated` e il collaudo isolato documentato in
[Todo UX hardening](TODO_UX_HARDENING.md). Usare JDK 17 per Gradle.
Esiti hardware, browser e distribuzione: [STATUS](../../STATUS.md).
