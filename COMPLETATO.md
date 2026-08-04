# Funzioni completate e verificate

Aggiornato il 4 agosto 2026.

## Completate

- Scaffold Flutter nativo Android/macOS/Windows, senza target web.
- Schema SQLite tipizzato Drift con task, impostazioni, outbox persistente, WAL, tombstone e metadati Lamport.
- Creazione rapida dal solo titolo con Invio; Inbox e viste Oggi, Prossime, In attesa, Completate.
- UI adattiva con NavigationRail desktop e NavigationBar Android, tema chiaro/scuro e localizzazione italiana predisposta.
- Ordinamento Oggi deterministico e riordino manuale persistente.
- Modifica titolo, note, stato, “Mostra il”, scadenza, ora e tipo di ricorrenza esplicito.
- Ricorrenze giornaliere, settimanali e mensili, da calendario e dal completamento; chiave serie/occorrenza univoca e inserimento idempotente.
- Ricerca locale su titolo e note con ordine stabile.
- Notifiche locali pianificate, aggiornate e annullate; permessi Android/macOS e receiver Android al riavvio.
- Export JSON versionato e CSV; validazione, anteprima e import JSON con merge per versione.
- Migrazione Supabase PostgreSQL, RLS, indici, outbox remota e funzione deterministica `merge_task`.
- Worker push/pull non bloccante, retry implicito tramite outbox persistente, trigger su connessione e timer.
- Aggiornamento Android diretto nell’app con avanzamento, verifica SHA-256, firma release stabile e scelta automatica dell’APK per ABI.
- APK Android misurati a circa 19–23 MB per ABI, contro 59 MB universali.
- Ottimizzazioni runtime: stream SQLite attivi/completati separati e persistenti, indici schema 2, riordino senza scritture invariate, fusi/permessi notifiche differiti e controllo release ogni sei ore.
- Documentazione operativa Android e regole permanenti per mantenere codice, documentazione e GitHub allineati.
- Fuso IANA nativo Android per notifiche e task con ora, senza dipendenza dalla rete.
- Export esplicito e idempotente al Calendar Provider Android, con preferenza stabile per Google primario e aggiornamento dello stesso evento.
- Launcher Android aggiornato per scaricare l’artefatto ARM64 del Galaxy S21 prodotto dalla CI split-per-ABI.
- Impostazioni raggiungibili dall'AppBar Android, con ritorno esplicito alla navigazione principale.
- Vista Prossime ordinata e raggruppata per giorno, con export calendario opzionale per ogni attività datata.
- Creazione in una riga con riconoscimento locale di date e orari italiani comuni.
- Sessione Supabase persistente nel secure storage, rinnovo automatico e collegamento account una tantum; la verifica live resta subordinata a un progetto remoto configurato.
- Stato sync reale nelle Impostazioni e protezione single-flight contro esecuzioni di rete sovrapposte.
- Anteprima della data naturale durante la digitazione e correzione della ripianificazione/annullamento notifiche dopo modifica o eliminazione.
- Workflow Android di pubblicazione protetto: ricompilazione, test, APK per ABI, manifest/hash, release `latest` e verifica pubblica nello stesso processo.
- Release pubblica `v1.1.0` build 8 con APK ARM64/ARM32/x86_64 e manifest verificato byte per byte dopo il download pubblico.
- Progetto Supabase personale e publishable key pubblica collegati automaticamente a launcher e build Android/macOS.
- Migrazione Supabase applicata e endpoint RLS `tasks`/`sync_operations` verificati; autenticazione Email attiva con conferma una tantum.
- Release pubblica `v1.1.1` build 9 con Supabase configurato, manifest pubblico confrontato byte per byte e hash ARM64 verificato.
- Composer mobile dal basso e calendario futuro orizzontale con filtro per giorno e conteggi, senza nuovi servizi o dipendenze runtime.
- Android impostato come primo canale di collaudo: pubblicazione automatica per ogni push funzionale versionato e controllo aggiornamenti a ogni apertura.
- Navigazione Android ridotta a Oggi/Prossime/Completate, timeline fino a dieci anni con salto data ed evidenziazione live della sintassi intelligente.
- Schema SQLite 3 predisposto per import Todoist idempotente: progetti, sezioni, priorità e identificativi esterni univoci, senza incorporare metadati nel titolo.
- Repository sorgente pubblico con cronologia pulita e licenza MIT; release 1.4.1 dedicata alla verifica end-to-end di firma, token fine-grained e pubblicazione Android dalla nuova infrastruttura.
- Ricorrenze rapide Todoist-like per giorni, giorni della settimana, settimane, mesi e anni; completamento con creazione idempotente dell'occorrenza successiva.
- Ricorrenze avanzate per giorno del mese, giorno/mese annuale e giorno ordinale mensile; parser Todoist avviato con anteprima read-only e blocco esplicito delle espressioni ambigue.

## Verificate in questa macchina

- `flutter analyze`: nessun problema.
- `flutter test`: 27 test superati, inclusi dominio, database, UI Android, parser italiano, notifiche, calendario idempotente e regressioni performance.
- Build macOS tentata: non eseguibile perché `xcodebuild` non è installato/selezionato in questa macchina.
- Build Android tentata: non eseguibile perché Android SDK/`ANDROID_HOME` non è presente.
- Build Windows non eseguibile da macOS; va verificata su Windows come descritto nel README.

## Non dichiarate complete

Vedi “Limiti noti” nel README e [TODO_NEXT.md](TODO_NEXT.md): pairing/sync live, recupero cestino, selezione multipla/undo, scheduler automatico dell'orizzonte calendario e backup cifrato. Notifiche, calendario e aggiornamento OTA superano build/test, ma i flussi completi non sono ancora stati provati fisicamente sul Galaxy S21; Supabase non è stato provato contro un progetto reale.
