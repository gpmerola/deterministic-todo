# Copia privata del Second Brain

## Contratto

`Supabase -> RPC di sola lettura -> Google Apps Script -> Google Doc privato`.
Il Mac non deve restare acceso. Lo script associato al documento esegue un
aggiornamento orario sotto l'account Google che lo autorizza; gli orari non sono
garantiti al minuto. Nessun nuovo lavoro, polling o dipendenza nell'app Android.
La versione applicativa resta invariata: questo collegamento ha schema 1 e
una migrazione server separata, da attivare esplicitamente.

La fonte operativa resta SQLite/Todo, sincronizzata in Supabase. Drive è una
copia derivata: modifiche nel documento non tornano nell'app. Le chat devono
avere Google Drive collegato e accesso al documento; non basta citarne il nome.
La sincronizzazione/indexazione del connettore della chat può introdurre ritardo.

Sono esportati titoli, ID, stato e pianificazione delle attività aperte,
titoli e orari degli eventi visibili nella copia del calendario, timestamp e
finestra coperta. Esclusi note, account, link delle riunioni, attività completate,
cestino e storico. Eventi fuori finestra, nascosti o non ancora sincronizzati
dal telefono non possono essere dedotti da questa copia. Date all-day civili,
fine esclusa; istanti con offset per gli altri eventi. Le date delle attività
sono civili, non scadenze inventate; `show_date` è la data di pianificazione.

## Sicurezza

La migrazione `202610060001_second_brain_export.sql` aggiunge una tabella di
autorizzazioni inaccessibile ad `anon` e `authenticated` e una sola RPC.
La RPC non accetta SQL, ID utente o filtri dal chiamante: una chiave casuale
revocabile individua esattamente il proprietario. Il server conserva soltanto
SHA-256; la chiave viaggia nell'header HTTPS `x-second-brain-token`, mai nell'URL.
Un unico statement produce uno snapshot coerente anche durante gli upload.
Non usare chiavi `service_role`, password, sessioni dell'app o token di refresh.

Il token è un segreto di lettura: chi lo possiede può leggere i campi esportati
fino a scadenza/revoca. Conservarlo solo nelle Script Properties del progetto
privato. Non condividere documento o script con editor non autorizzati: gli
editor del contenitore possono modificare lo script e accedere alle proprietà.
I permessi Google sono documento corrente, richieste HTTPS e trigger; nessun
accesso generale a Drive. La condivisione resta privata. L'attivazione di nuovi
accessi attraverso browser richiede conferma al momento dell'azione.

## Installazione e verifica

1. Eseguire `make check`. Applicare la migrazione verificata tramite il canale
   amministrativo autorizzato, senza modificare tabelle o policy esistenti.
2. Creare un Google Doc privato dedicato in `SECOND BRAIN/30_RISORSE` e aprire
   **Estensioni → Apps Script**. Copiare il sorgente canonico
   [Code.js](../../tools/second-brain/Code.js) in `Codice.gs` e il manifest
   [appsscript.json](../../tools/second-brain/appsscript.json). Nessun deployment
   come web app, nessun URL pubblico.
3. L'utente esegue `prepareSecondBrain` e autorizza i tre scope Google.
   Lo script crea e conserva il token nelle proprie proprietà; mostra solo
   SHA-256. Due UUID casuali indipendenti forniscono 244 bit casuali. Rieseguire
   non ruota la chiave. Non registrare il token in cronologie SQL, output
   dell'agente o log. L'amministratore registra solo l'hash per l'UUID
   dell'account Todo scelto. Usare
   parametri del client SQL: `insert into public.second_brain_export_grants
   (user_id, token_hash, expires_at) values ($1, $2, now()+interval '1 year')`
   con `$2` pari ai 32 byte SHA-256 del token UTF-8. Non sovrascrivere un grant
   esistente senza autorizzazione alla rotazione. Questa fase richiede un
   canale amministrativo autenticato: il repository non contiene credenziali.
4. Inserire nelle **Proprietà script** `SUPABASE_URL`, `SUPABASE_ANON_KEY`
   (configurazione pubblica client). `EXPORT_TOKEN` è già generato dallo script;
   non mostrarlo né copiarlo in chat.
5. Eseguire `installSecondBrain`: prima copia verificata, poi un solo trigger
   orario. Ripeterlo non duplica i trigger. Controllare contenuto e metadati del
   documento: distinguere «prima copia riuscita e timer configurato» da
   «esecuzione automatica verificata». Aggiornare START QUI con l'esatto stato
   osservato. Verificare successivamente l'esecuzione oraria naturale senza
   aumentare la frequenza autorizzata per accelerare il collaudo.
6. Da una nuova chat con Google Drive collegato, chiedere «Vai sul Second Brain
   e guarda il mio calendario». Verificare che legga il documento giusto,
   dichiari freschezza/copertura e non scambi un intervallo ignoto per libero.

Stato dell'attivazione e collegamenti privati restano nel Second Brain;
il riepilogo tecnico verificato è in [STATUS](../../STATUS.md).

## Errori, revoca e recovery

Errore HTTP, schema invalido o risposta troppo grande: lo script non sostituisce
l'ultima copia valida e non ne rinnova il timestamp. Nessun troncamento silenzioso.
Gli errori espongono solo codici, non risposta, token o titoli. I fallimenti di
scrittura Google restano fallimenti: verificare il documento e la sua cronologia
prima di dichiarare una copia riuscita. Il limite di 900.000 caratteri precede la
scrittura. Scadenza del token: provisioning di un nuovo hash e aggiornamento
privato della proprietà, poi `syncSecondBrain`.

`stopSecondBrain` rimuove solo i trigger di questo esportatore. Per revocare
anche la lettura, l'amministratore elimina il grant del solo utente interessato.
La copia precedente resta su Drive e va eventualmente cestinata esplicitamente;
la revoca non cancella dati già letti da una chat. Non rimuovere il calendario,
le attività o il backup di Todo. Il rollback del collegamento non richiede
rollback dell'app né delle sue tabelle.

Riferimenti: [trigger Google](https://developers.google.com/apps-script/guides/triggers/installable),
[proprietà](https://developers.google.com/apps-script/reference/properties/properties-service).
