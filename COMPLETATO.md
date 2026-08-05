# Funzioni completate e verificate

Aggiornato il 5 agosto 2026.

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
- Frasi intelligenti per feriali, weekend, ultimo giorno/weekday mensile, intervalli dal completamento e date relative; piano Todoist tipizzato con progetti, sezioni, task, descrizioni, priorità, date, fusi, ricorrenze e UUID v5 deterministici.
- Import Todoist attivo-only completo: anteprima obbligatoria, transazione SQLite atomica, reimportazione senza duplicati, outbox per tutti i task e sincronizzazione Supabase di progetti, sezioni, priorità e identificativi esterni.
- Il vero export personale è stato simulato soltanto in memoria: 5 progetti, 13 sezioni, 110 task attivi, 46 pianificati e 25 ricorrenti; seconda esecuzione con zero duplicati. Il file personale non è stato copiato nel repository.
- Vista Progetti Android con sezioni e attività attive, Completate spostata nelle Impostazioni e rendering cliccabile dei link Markdown Todoist senza URL estesi in elenco.
- Progetti personalizzabili in stile Todoist: selettore con colori/conteggi, layout elenco o bacheca persistente per progetto, creazione di progetti/sezioni/task e spostamento task da editor.
- Diagnostica locale strutturata e rotante su Android/macOS, esportabile su richiesta e priva di contenuti utente o credenziali.
- Release 2.3.0: animazione breve al completamento, indicatore visibile delle ricorrenze, bandierine P1–P4 coerenti con le priorità importate da Todoist e navigazione gerarchica con il tasto Indietro Android.
- Release 2.3.1: descrizioni naturali delle ricorrenze in elenco, editor attività compatto come bottom sheet e completamento in due fasi con conferma verde prima della dissolvenza.
- Release 2.4.0: densità visiva ridotta sulla base del confronto con Todoist, editor sotto i 460 px, date non duplicate, priorità integrate nel checkbox, contatori rimossi da Prossime e Inbox Todoist nascosta dai progetti.
- Release 2.5.0: Progetti con intestazione unica, Impostazioni raccolte, guide testuali rimosse, priorità con tinta leggera e ordinamento automatico, chiusura tastiera/composer Android con una sola pressione e animazione inversa da 90 ms.
- Release 2.6.0: descrizioni Todoist visibili sotto il titolo con link compatti, eliminazione via swipe sempre annullabile, filtro “Tutte” rimosso da Prossime e sincronizzazione condensata in una sola riga.
- Release 2.7.0: Progetti ridisegnato come navigazione gerarchica minimale compatibile con Todoist, composer aperto/chiuso in 80/45 ms con descrizione opzionale immediata e ora rimossa dalla UI e dalla creazione naturale.
- Release 2.8.0: supporto orario rimosso da parser, import, sync, calendario e runtime; eliminati plugin di notifiche/fusi e receiver Android. Priorità P1–P4 impostabile direttamente dal composer rapido.
- Release 2.9.0: swipe verso il cestino limitato a destra→sinistra con soglia 62% e Undo; composer rapido riusato dentro Progetti; descrizioni ridotte a una riga; editor senza Stato e Scadenza, con stato derivato dalla sola data; Google Calendar spostato nel menu `⋮`. Link Todoist e highlighting naturale estratti da `main.dart` in componenti UI dedicati.
- Release 2.10.0: menu minimale `⋮` su progetti e sezioni con rinomina, spostamento su/giù ed eliminazione reversibile con Undo; riordino e archiviazione incrementano la versione logica e convergono tramite la sincronizzazione esistente senza cancellare task o mapping Todoist.
- Release 2.11.0: composer/editor e completamento accelerati; padding tastiera immediato; Prossime trasformata in timeline lazy con giorni vuoti, senza chip e senza doppio Indietro; editor link senza URL Markdown visibili; Completate limitata a 200 record con retention di 365 giorni; reset locale transazionale protetto; controllo update ogni sei ore soltanto in foreground.
- Release 2.11.1: controllo aggiornamenti con query cache-buster e header `no-cache`, per evitare che la cache CDN GitHub ritardi il prompt dopo una nuova pubblicazione.
- Release 2.12.0: apertura e chiusura del composer `+` senza animazione; link delle descrizioni presentati come chip apribili e rimovibili senza URL grezzi; Cestino in Impostazioni con ripristino di attività, progetti e sezioni.

## Verificate in questa macchina

- `flutter analyze`: nessun problema.
- `flutter test`: suite completa superata, inclusi dominio, database, UI Android, parser italiano, calendario idempotente e import Todoist ripetibile.
- Build macOS tentata: non eseguibile perché `xcodebuild` non è installato/selezionato in questa macchina.
- Build Android tentata: non eseguibile perché Android SDK/`ANDROID_HOME` non è presente.
- Build Windows non eseguibile da macOS; va verificata su Windows come descritto nel README.

## Non dichiarate complete

Vedi “Limiti noti” nel README e [TODO_NEXT.md](TODO_NEXT.md): pairing/sync live, recupero cestino, selezione multipla/undo, scheduler automatico dell'orizzonte calendario e backup cifrato. Notifiche, calendario e aggiornamento OTA superano build/test, ma i flussi completi non sono ancora stati provati fisicamente sul Galaxy S21; Supabase non è stato provato contro un progetto reale.
# Versione 2.1.0

- Reimport Todoist incrementale tramite checkpoint `updated_at`: nuovi record aggiunti, record cambiati aggiornati, nessun duplicato.
- Opzione “Sostituisci da zero” con doppia conferma, limitata ai dati Todoist e compatibile con la sincronizzazione Android/macOS.
- Import del layout elenco/bacheca indicato dal progetto Todoist.
- Log diagnostico con conteggi separati per aggiunte, aggiornamenti e rimozioni.

# Versione 2.1.1

- Polling di sincronizzazione ridotto da 5 a 15 minuti, sospeso quando l’app non è in primo piano e riattivato immediatamente al ritorno.
- Upload di progetti e sezioni invariati eliminato tramite fingerprint Lamport locale; nessuna modifica allo schema Supabase.
- Outbox compattata per attività e confronto del pull remoto eseguito in batch, eliminando RPC e query SQLite duplicate.
- Simboli Dart separati dagli APK release e conservati privatamente per 30 giorni, riducendo lo storage sul dispositivo senza perdere la possibilità di diagnosticare crash.
- APK ARM64 2.1.2 misurato a 22.364.249 byte: circa 1,25 MB (5,3%) in meno rispetto alla 2.1.1.

# Versione 2.2.0

- Profilazione locale event-driven di avvio, RAM RSS, dimensione SQLite, code di sync e frame build/raster.
- Metriche del sync per durata, volume remoto, upload compattati e progetti/sezioni invariati saltati.
- Nessun analytics, nuovo polling o contenuto utente nei log; esportazione manuale dalle Impostazioni.
- Promemoria interno massimo una volta al giorno con esportazione diretta e prompt di analisi pronto da copiare.
- Oggi esclude il backlog senza data appartenente ai progetti, mantenendo visibili le attività libere senza progetto.
- Conteggio frame lenti sia sul budget 60 Hz sia sul budget 120 Hz del Galaxy S21.
# 2.12.1

- Ripristino automatico delle migrazioni SQLite interrotte: macOS e Android possono completare lo schema locale senza perdere attività quando alcune colonne erano già state create.
- Aggiunto un test di regressione che parte intenzionalmente da una migrazione versione 2 rimasta a metà.
