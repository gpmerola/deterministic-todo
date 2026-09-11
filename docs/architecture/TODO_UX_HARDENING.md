# Todo: editor, viste e sincronizzazione — build 174

## Comportamento

Prossime ritorna in cima quando si rientra da un'altra schermata. Aprire e
chiudere una task mantiene invece il contesto. Carica inizialmente 30 giorni;
**Mostra altri 30 giorni** estende la finestra. Le viste interrogano SQLite
soltanto per gli elementi visibili, senza materializzare tutte le descrizioni.

Sul desktop il salvataggio riuscito chiude il pannello dettagli. Descrizione
sempre visibile, **Aggiungi link** senza selezione preventiva e nome facoltativo;
i link incollati sono riconosciuti. Le etichette identiche mantengono URL distinti.
Le bozze dell'editor e della creazione rapida restano locali in `app_settings`,
sono escluse dall'export e dal cloud, e vengono rimosse al salvataggio riuscito.
L'editor salva dopo 300 ms di inattività e prima della chiusura; un errore di
storage impedisce la chiusura. Un arresto improvviso entro il debounce può
perdere gli ultimissimi caratteri. La baseline della bozza conserva gli intenti:
un campo non toccato non annulla una modifica remota arrivata nel frattempo.

## Protocollo

SQLite 8 aggiunge trigger transazionali per gli intenti di progetti e sezioni,
con payload schema 3. Le revisioni restano separate dall'outbox. Il writer usa
CAS e conferma degli esiti incerti come per le attività; i vecchi fingerprint
vengono convertiti in intenti legacy conservativi. Un conflitto blocca soltanto
la propria entità: le altre vengono inviate e il pull continua. L'ack elimina
soltanto le operazioni catturate e conserva quelle aggiunte durante l'invio.
I batch per entità mantengono l'ordine SQLite anche con timestamp uguali.

Il pull completo pagina per UUID ordinato, 200 elementi per richiesta, fino a
una pagina vuota. Una pagina corta non implica fine: il limite server può essere
inferiore. Ogni pagina è applicata in transazione, rispettando gli intenti locali.
Il pulsante cloud mostra la coda SQLite e apre gli elementi in attesa; l'editor
collega lo stato della task al suo storico. Il ripristino di progetti/sezioni
ripristina soltanto quella riga, senza ricreare automaticamente le relazioni.

## Cestino e migrazione server

`supabase/migrations/202609110001_safe_purge.sql` aggiunge il registro minimo
`purged_entities`: utente, UUID/tipo e istante, senza titolo o descrizione.
La successiva `202609110002_ledger_privileges.sql` revoca esplicitamente tutti
i privilegi client ereditati prima di concedere soltanto lettura e RPC previste.
Trigger server registrano le eliminazioni definitive e rifiutano la ricreazione
dello stesso UUID anche da client vecchi. RLS permette soltanto la lettura del
proprio registro; le scritture sono riservate ai trigger. Un lock transazionale
per utente serializza eliminazioni e scritture sulle tre tabelle.

Il client richiede `purge_trash_v2`: se manca, lo svuotamento definitivo fallisce
chiaramente. Non ripiega sulla cancellazione locale o sulla vecchia RPC. Il pull
del registro elimina soltanto gli UUID dichiarati, preservando lo storico locale.
Un marker locale minimo conserva gli UUID già osservati come eliminati e
impedisce che una risposta remota ritardata li faccia riapparire. Lo storico
resta leggibile, ma un UUID eliminato definitivamente non può essere ripristinato:
il contenuto può essere copiato esplicitamente in un nuovo elemento.
La vecchia RPC è anch'essa protetta dopo la migrazione. Non è possibile ricostruire
le eliminazioni definitive antecedenti alla sua applicazione. Il registro non ha
scadenza automatica, per proteggere i dispositivi rimasti offline a lungo.

La migrazione non è applicata automaticamente dal push del codice. Prima della
pubblicazione stabile occorrono approvazione per il servizio condiviso, backup
server e applicazione tramite il workflow Supabase autorizzato. Il client continua
il normale sync senza il registro quando la tabella non esiste, ma blocca lo
svuotamento definitivo. Non cancellare il registro per un rollback: perderebbe
la protezione degli UUID già eliminati. I client precedenti mantengono i vecchi
algoritmi di merge; aggiornare Web e Android per una protezione uniforme.

## Verifica riproducibile

- `make check`: analisi, suite Flutter, strumenti, link e PostgreSQL PGlite.
- `make check-generated`: verifica schema Drift generato.
- `test/sync_hardening_test.dart`: due client, CAS, risposte perse, ricevute,
  conflitti isolati, pagina server inferiore a 200 e oltre 1.000 elementi.
- `test/todo_ux_hardening_test.dart`: navigazione, editor, bozze, link e invio unico.
- `test/task_view_performance_test.dart`: 100/1.000/10.000 task sintetiche con
  descrizioni, dieci elementi visibili; misura query, non RAM/frame sul telefono.
- `tools/sql-tests/safe_purge.mjs`: migrazioni SQL reali in PostgreSQL WASM,
  rollback, RLS, vecchia RPC, tentativi di ricreazione e cancellazione account.
  Non sostituisce una prova di concorrenza su più connessioni Supabase reali.

PGlite è fissato nel lockfile, Apache-2.0, dipendenza soltanto di test; non entra
nell'APK o nel bundle Web. Installare con `npm ci --prefix tools/sql-tests`.

Per il Galaxy usare esclusivamente il package sintetico separato:

```sh
ORG_GRADLE_PROJECT_todoValidation=true flutter test --no-pub \
  integration_test/todo_validation_test.dart -d DEVICE --flavor dev \
  --dart-define=TODO_VALIDATION=true
```

Il package `.dev.validation` non registra il canale Movimento; i test rifiutano
package operativi. Per il confronto browser/telefono avviare
`python3 tools/synthetic_sync_server.py`, poi `adb -s DEVICE reverse tcp:8877 tcp:8877`.
Compilare `test/validation_app.dart` con `TODO_VALIDATION=true` e
`SYNC_FIXTURE_URL=http://127.0.0.1:8877`, servire su un'origine localhost separata.
Creare **Cross Web** con nota contenente `https://example.com/documento`, premere
il cloud e **Controlla sincronizzazione**. Eseguire poi
`integration_test/cross_device_test.dart` con gli stessi flag Android.
Flutter può rimuovere i reverse ADB all'avvio: quando il test annuncia
**browser to Android**, ripetere `adb -s DEVICE reverse tcp:8877 tcp:8877`
entro dieci secondi. Il test attende il solo trasporto locale e poi scarica
la task, cambia la nota, crea **Cross Android**, invia e riapre SQLite. Dal browser
ricontrollare il sync e verificare i due risultati anche dopo refresh.

Il server è in memoria, accetta soltanto connessioni loopback e usa identità
sintetiche: nessun account Supabase reale. La convergenza su questo trasporto
non dimostra RLS, Realtime o autenticazione in produzione. Esiti hardware,
pubblicazione e limiti ancora aperti sono riportati in [STATUS](../../STATUS.md).

Applicazione e recovery: [runbook del registro](../operations/SAFE_PURGE.md).
