# Backup e recovery

## Dati utente

Il backup completo è l'export JSON dall'app. CSV non conserva tutti i metadati.
Prima di reset, reimport Todoist o manutenzione Supabase esportare JSON e
verificare che il file sia leggibile. Non inserirlo nel repository.

Dalla build 330 ogni telefono Android collegato a Supabase salva anche una copia
giornaliera nel cloud (ultime 14, solo se cambiata): per ripristinarla su un
telefono nuovo collegare lo stesso account, aprire Impostazioni → Dati e
manutenzione → Backup nel cloud e scegliere la copia; segue anteprima e
conferma. Contratto e limiti:
[backup nel cloud](../architecture/TODO_BACKUP_AND_LIFECYCLE.md#backup-nel-cloud-android-con-account-build-330).

## Dispositivo

- Android: SQLite resta nei dati applicativi durante gli aggiornamenti firmati.
- Browser: non usare incognito e non cancellare dati del sito; SQLite e
  diagnostica persistono nello storage del sito.
- Dopo recovery collegare lo stesso account Supabase e attendere la convergenza
  prima di modificare in parallelo da un altro dispositivo.

## Chiavi e release

Il keystore Android vive fuori da Git ed esige un backup cifrato esterno. La sua
perdita impedisce aggiornamenti delle installazioni esistenti. Token e password
non devono entrare in backup applicativi, log o documentazione.

## Reset

Il reset locale è consentito soltanto dopo la disconnessione Supabase. Un reset
atomico cloud+dispositivo richiede ancora una RPC transazionale server-side e
non va simulato con cancellazioni parziali.
