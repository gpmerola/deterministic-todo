# Registro delle eliminazioni definitive

## Sorgenti e autorizzazione

Applicare nell'ordine le migrazioni `202609110001_safe_purge.sql` e
`202609110002_ledger_privileges.sql`, soltanto dopo autorizzazione esplicita
per il progetto Supabase condiviso. Il push GitHub non applica SQL remoto.
La seconda migrazione revoca anche TRUNCATE e privilegi ereditati sulle funzioni;
Supabase assegna per default tutti i privilegi ai ruoli client. RLS da sola non
sostituisce questa revoca. I client possono leggere il proprio registro e
invocare le due RPC di purge, ma non modificare il registro direttamente.

## Preflight e conservazione

1. Confermare che il progetto selezionato coincida con l'host in
   `supabase/config.json`; non usare né esporre chiavi amministrative nel client.
2. Verificare `tasks`, `projects`, `project_sections` e l'assenza del nuovo registro.
3. Leggere `pg_get_functiondef(to_regprocedure('public.purge_trash()'))` e
   conservarne la definizione prima di sostituirla. Nel deploy iniziale dell'11
   settembre corrispondeva alla migrazione immutabile `202608310001_purge_trash.sql`.
4. Controllare `pg_default_acl` e i privilegi reali. Non consultare righe Todo o
   account per questa operazione di schema.

L'applicazione iniziale non cancella né trasforma dati esistenti: crea un registro
vuoto e installa funzioni/trigger. Non chiamare `purge_trash` come smoke test sul
profilo reale. Le definizioni precedenti sono conservate nelle migrazioni Git;
questa conservazione dello schema non equivale a un backup dei dati personali.

## Applicazione e verifica

Eseguire i due file canonici nella stessa transazione, preceduti da:

```sql
begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';
```

Terminare con `commit;`. Un timeout, un oggetto già esistente o qualsiasi errore
richiede rollback e ispezione dello schema; non ritentare alla cieca o cancellare
oggetti per far passare il comando. I file non sono uno script di reset.

Dopo il commit verificare in sola lettura:

- `pg_class.relrowsecurity` sul registro: true;
- sei trigger non interni (`*_purge_guard`, `*_purge_ledger`): presenti;
- `has_table_privilege`: authenticated ha SELECT, non ha INSERT/UPDATE/DELETE/
  TRUNCATE/REFERENCES/TRIGGER; anon non ha SELECT né scritture;
- `has_function_privilege`: authenticated ha EXECUTE sulle RPC purge; anon no;
  i ruoli client non hanno EXECUTE diretto sulle due funzioni trigger;
- stato tecnico del prossimo sync Todo e nessun errore nuovo attribuibile alla
  migrazione. Non confondere un successo storico con un ciclo successivo al deploy.

`make check-sql` riproduce anche i grant predefiniti Supabase e verifica RLS,
rollback, ricreazione di UUID, privilegi ereditati e cancellazione account, con
fixture sintetiche su PostgreSQL WASM. Non prova la concorrenza su connessioni
multiple del server reale.

## Recovery

Prima del commit, PostgreSQL annulla tutta la transazione in caso di errore.
Dopo il commit, preferire una migrazione correttiva. Non rimuovere il registro o
le protezioni sugli UUID già eliminati: un client offline potrebbe ricrearli.
Conservare il contratto `purge_trash_v2` e le ACL esplicite; non tornare a un purge
locale indiscriminato. Un ripristino di dati personali richiede un backup
separato, un ambito esplicito e verifica degli UUID rispetto al registro.

Stato applicato, hash e pubblicazione client: [STATUS](../../STATUS.md).
