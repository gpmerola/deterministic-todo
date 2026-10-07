# Stato corrente

Aggiornato il 7 ottobre 2026.

## Build 240 — Cassaforte cifrata 10 e import UTF-8

`flutter_secure_storage` 9 → 10 (non 11: la 11 rifiuta i dati v9 non migrati).
Sul Galaxy, installando 2240 sopra 2239, il log riporta «Non-biometric migration
completed successfully! Migrated 4 items»; dopo la migrazione e dopo un
riavvio a freddo l'app resta sincronizzata senza login e la chiave DeepSeek
è ancora presente. Il formato web della 2.x coincide con la 1.x (stessa chiave
`FlutterSecureStorage`, AES-GCM, nessun wrap key): nessuna migrazione nel
browser, da confermare alla prossima Web pubblicata.

Trovato durante l'aggiornamento di `file_picker`: i lettori nativo e web
decodificavano i file scelti con `String.fromCharCodes`, cioè Latin-1, mentre
l'export scrive UTF-8. Un backup reimportato o un export Todoist con accenti
sarebbe stato alterato. Ora `decodePickedText` decodifica UTF-8 con test.
Eventuali import passati con accenti non sono stati controllati (nessuna
ispezione del database personale). `make check` verde, 422 test.

## Build 239 — Manutenzione, passi e Calendario più leggeri

Revisione di struttura richiesta dall'utente il 7 ottobre 2026. Il test
«Data nell editor riprogramma» falliva solo quando il giorno di domani cadeva
al centro dello schermo: il tocco arrivava durante l'animazione del dialogo.
Ora attende la fine della transizione. Passi estratti in
`DailyStepsController`: nessuna ricostruzione della shell a passi invariati;
obiettivo e preferenza della celebrazione riletti solo alla riapertura. Letture
iniziali del Calendario in parallelo. `make check` (419 test Flutter, strumenti,
link, SQL) e `make check-generated` verdi.

Dipendenze: solo aggiornamenti compatibili. `flutter_secure_storage` 11 (che
sblocca `package_info_plus` 10, `share_plus` 13, `file_picker` 13) e `drift`
2.35 non sono stati applicati: richiedono rispettivamente prova della
migrazione della sessione sul Galaxy e rigenerazione di `web/drift_worker.js`
con collaudo Web (TODO_NEXT).

Galaxy: `make todo-test` ha installato in place Todo Test 2.68.3-dev
(`versionCode` 2239) via ADB, dati conservati. Anello passi visibile e
aggiornato in Oggi; Calendario aperto con fuso, vista «3 sett.» memorizzata e
filtri ripristinati; nessun crash nel buffer `crash`. Non osservato un intero
tick con cambio passi né una celebrazione reale.

## Second Brain — attivato il 6 ottobre 2026

Su richiesta dell'utente è stata scelta una copia privata su Google Drive,
aggiornata ogni ora. RPC con grant di sola lettura per un singolo proprietario,
hash SHA-256 del token, scadenza/revoca, proiezioni ridotte e snapshot coerente.
Apps Script associato al documento dedicato: scope limitato al documento,
nessun deployment pubblico; copia precedente conservata se il fetch fallisce.
Contratto e attivazione in [SECOND_BRAIN](docs/operations/SECOND_BRAIN.md).

Documento privato creato in `SECOND BRAIN/30_RISORSE`, riferimento nativo
aggiunto a START QUI e changelog del sistema aggiornato. Contenuti di stato e
permessi privati riletti. Dopo «fatto, attiva», verificata la preparazione della
chiave eseguita dall'utente; applicata in transazione la migrazione server e
registrato un solo grant, con scadenza 6 ottobre 2027. RLS attiva e tabella grant
non leggibile da `anon` né `authenticated`; richiesta REST senza chiave respinta
con HTTP 401 / codice 42501. Il segreto è rimasto nelle proprietà dello script.

`installSecondBrain` riuscito alle 17:26 UTC: prima copia letta tramite il
connettore Drive, con timestamp del telefono e copertura distinti da quello
dell'esportazione. Documento ancora privato (solo proprietario). Unico trigger
`syncSecondBrain` configurato ogni ora, anche a Mac spento. START QUI e changelog
aggiornati e riletti. Prima esecuzione automatica non ancora osservata; non
equivale alla prova manuale riuscita. Il tentativo di timer temporaneo al minuto
per il collaudo è stato respinto dall'auto-review: modifica annullata, cadenza
oraria conservata. Nessun ulteriore accesso o trigger di prova creato.
`make check`: analisi statica pulita, 414 test Flutter, controlli strumenti,
documenti e SQL superati. Nuovi test sintetici: isolamento tra proprietari,
proiezione dei campi, scadenza/revoca, mancata sovrascrittura su errore,
trigger idempotenti e preparazione della chiave senza esposizione del segreto.
CI Verify del commit `6df80c2` superata. Questa attivazione non modifica il
codice dell'app né la release Android 238.

## Release stabile 238 — pubblicata

Dopo `PUBBLICA`, workflow coordinato
[37491519220](https://github.com/gpmerola/deterministic-todo/actions/runs/37491519220)
riuscito: Web, APK diretti e upload Play nel track interno. Versione 2.68.2,
build 238, sorgente `05dfc17bba0b9252733bc3b2ec51deedbb6205d8`.
Identità Web e manifest coerenti; i quattro APK pubblici riscaricati e SHA-256
verificati. Chrome aggiornato dalla 229: Impostazioni mostra 2.68.2 (238),
sessione e contenuti conservati dopo refresh HTTPS, sincronizzazione riuscita.
La disponibilità Play sul singolo dispositivo non è stata verificata; Galaxy
resta sul canale Todo Test 2238 già installato, senza riattivare il package Play.

## Build 238 — Avviso temporaneo e testi più leggibili

La SnackBar «Nascosto in Todo» restava visibile perché l’azione «Annulla»
implicava `persist: true` nella versione Flutter installata. Ora `persist`
è esplicitamente falso, durata 6 secondi, X disponibile e coda delle conferme
precedenti svuotata. Testano timeout dopo ripetizione, X e annullamento,
verificando che solo «Annulla» ripristini l’evento e che il filtro resti salvato.

Rimosso lo sbiadimento globale di eventi passati e fuori mese, anche in elenco;
fuori mese si distingue il numero giorno. Testo principale e secondario più
netto, nero/bianco sui riempimenti scelto per contrasto e orari colorati adattati
alla superficie. Test di contrasto includono colori chiari, scuri e intermedi;
test UI proteggono dall’opacità ridotta sulle celle passate/fuori mese e lista.
Rendering sintetico 360×800 della vista tre settimane, chiaro/scuro, ispezionato
con gruppo e appuntamento in giorni passati. Nessun collaudo visivo reale sul
telefono eseguito.
`make check` superato: analisi statica pulita, 414 test Flutter e controlli
strumenti, SQL e documentazione. Build Android e Web release riuscite.
Todo Test 2.68.2-dev / versionCode 2238 installata e avviata in-place sul
Galaxy con `make todo-test`; versione/processo verificati e dati conservati.
Pubblicazione e collaudo browser HTTPS: vedere la sezione release stabile sopra.

## Build 237 — Palette dedicata al Calendario

Superfici neutre chiare/ardesia, fasce delle date grigio-azzurre e accenti blu
per «Oggi» e comandi. Eventi con fondi meno saturi e bordi nelle viste orarie;
colori e preferenze dei calendari conservati. Il tema è applicato solo alla
sezione Calendario e alla pagina giorno, mantenendo tipografia e impostazioni.

Rendering sintetici 360×800 di tre settimane e settimana, chiaro/scuro,
ispezionati con gruppi e singoli eventi blu/verde chiaro. Nessun overflow
nei flussi di espansione. `make check` superato: analisi pulita, 408 test
Flutter e controlli strumenti, SQL e documentazione. Nessun nuovo test
per valori cosmetici; verifiche visive eseguite su fixture sintetiche.
Build Android e Web release riuscite. Nessun collaudo browser HTTPS della 237;
Web/stabile pubblicati restano alla 229.
Todo Test 2.68.1-dev / versionCode 2237 installata e avviata in-place sul Galaxy
con `make todo-test`; versione e processo verificati, dati conservati. Primo
streamed install ADB fallito senza motivo dettagliato; ripetizione del comando
canonico riuscita dopo `s21-adb`. Controllo visivo sintetico, non sul telefono.

## Build 236 — Tre settimane e ultima vista ricordata

Nuova modalità «3 settimane», con la settimana corrente e le due successive:
21 giorni dal lunedì, paginazione di 21 giorni e «Oggi» che ripristina il
periodo corrente. Riusa la griglia esistente e il raggruppamento visite.
La preferenza era già persistente in SQLite; anche `threeWeeks` viene salvata
con il nome nella stessa chiave, senza migrazione né reset delle altre scelte.
Test aggiunti per confini a cavallo d’anno, 21 celle, paging, «Oggi» e ripristino
di ogni modalità scelta dal menu dopo la creazione di una nuova istanza del
Calendario e del servizio. Il test comune dei gruppi include la nuova modalità.
`make check` superato: analisi statica pulita e 408 test Flutter, oltre ai
controlli strumenti, SQL e documentazione. Build Android e Web release riuscite.
Todo Test 2.68.0-dev / versionCode 2236 installata e avviata in-place sul Galaxy
con `make todo-test`; versione/processo verificati, dati conservati. Nessun
nuovo collaudo visivo sul telefono né browser HTTPS. Web/stabile restano 229.

## Build 235 — Raggruppamento in tutte le viste

Gruppi di visite disponibili in giorno, tre giorni, settimana, due/quattro
settimane, mese ed elenco, con le stesse regole di eleggibilità e pausa massima
di 15 minuti. Le viste orarie conservano la scala del tempo: il blocco va dalla
prima all’ultima visita, mentre il pannello espanso mostra gli orari originali.
I proxy usati per la geometria non vengono passati all’editor o salvati.
Il riepilogo si adatta alla larghezza: tre righe nelle celle strette, una riga
con indicatore di espansione negli spazi larghi.

Test di flusso per tutte le modalità: espansione e apertura del singolo evento;
nel giorno verificata anche l’identità dell’oggetto originale e la sua durata.
Rendering sintetico 360×800 delle sei modalità della schermata principale
eseguito; settimana, tre giorni, due settimane, mese ed elenco ispezionati.
`make check` superato: analisi pulita, 405 test Flutter e controlli strumenti,
SQL e documentazione. Todo Test 2.67.0-dev / versionCode 2235 installata e
avviata in-place sul Galaxy con `make todo-test`; versione/processo verificati
e dati conservati. Il collaudo visivo è sintetico, non sul telefono.
Build Android e Web release riuscite. Nessun nuovo
collaudo browser HTTPS; Web/stabile pubblicati restano alla 229.

## Build 234 — Pause fino a 15 minuti tra visite

Corretta la soglia troppo restrittiva della 233: nella vista quattro settimane
le visite possono avere una pausa da zero a 15 minuti inclusi tra fine e inizio
successivo. Restano il minimo di tre visite, il riconoscimento dei titoli e lo
stesso calendario; sovrapposizioni e pause maggiori interrompono il gruppo.
Gli orari degli eventi originali restano visibili nell’elenco espanso.

`make check` superato: analisi pulita e 398 test Flutter, inclusa regressione
con pause di 0, 5, 14, 15 minuti e separazione a 16 minuti.
Todo Test 2.66.1-dev / versionCode 2234 installata e avviata in-place sul
Galaxy con `make todo-test`; versione e processo verificati, dati conservati.
Build Web release riuscita. Nessun nuovo collaudo visivo sul telefono o HTTPS;
Web/stabile pubblicati restano alla 229.

## Build 233 — Calendario, visite compatte e icona Home

«Agenda» diventa «Calendario» nell’interfaccia; nessuna migrazione dei dati.
Nella vista quattro settimane almeno tre visite riconoscibili dal titolo,
consecutive nello stesso calendario, diventano un blocco con orario e conteggio.
Un tocco mostra l’elenco e permette di aprire il singolo evento originale.
Pause, sovrapposizioni, task e richieste in attesa non vengono raggruppati.

Su Android, «⋮ → Aggiungi alla schermata Home» richiede al launcher un’icona
«Calendario». La conferma spetta all’utente; la richiesta non viene presentata
come aggiunta già completata. Il collegamento apre la sezione corretta e resta
nel package di origine. Editor eventualmente aperti non vengono chiusi forzatamente.

`make check` superato: analisi statica pulita e 397 test Flutter. Test JVM dev
e compilazione Kotlin direct/play superati. Test coprono raggruppamento,
esclusioni, accesso agli originali, menu e consumo singolo delle richieste
native/Dart a freddo e a caldo. Rendering sintetico 360×800 del blocco e della
lista espansa ispezionato. Conferma del launcher e apertura dall’icona reale
sul Galaxy ancora da collaudare: i test non sostituiscono questa verifica.

Todo Test 2.66.0-dev / versionCode 2233 installata e avviata in-place sul
Galaxy con `make todo-test`; versione e processo verificati, dati conservati.
Build Web release riuscita; collaudo browser HTTPS della 233 non eseguito.
Web/stabile pubblicati restano alla 229.

## Build 232 — Creazione nella barra superiore

«+» spostato accanto a «Oggi»: rimosso il pulsante flottante che copriva gli
ultimi giorni. Permessi e salvataggio invariati. Il raggruppamento delle visite, ancora
una proposta in questa build, è stato implementato nella 233.

`make check` superato: analisi pulita, 388 test Flutter. Il test di creazione
verifica ora anche l'allineamento con «Oggi» e l'assenza del pulsante flottante.
Rendering sintetico 360×800 con font reali e azioni normali della shell
(assistente, calendari, menu) ispezionato: nessun overflow, ultima riga libera.
Todo Test 2.65.1-dev / versionCode 2232 installata e avviata in-place sul
Galaxy con `make todo-test`; versione/processo verificati e dati conservati.
Il controllo visivo è sintetico, non uno screenshot del telefono. Web/stabile
pubblicati restano alla 229.
Build Web release 232 riuscita; collaudo browser HTTPS della 232 non eseguito.

## Build 231 — Quattro settimane correnti

Vista predefinita: quattro settimane dal lunedì corrente, 28 giorni anche
a cavallo di mesi e anni; «Oggi» ripristina questo intervallo. Scorrimento a
pagine di 28 giorni. La griglia delle due settimane è parametrizzata e riusata;
«Mese» rimane disponibile. Preferenza `agenda_view_mode_v3`: migrazione una
tantum del vecchio mese a quattro settimane, altre scelte conservate; una
nuova selezione esplicita del mese resta memorizzata.

`make check` superato, analisi pulita e 388 test Flutter: coperti numero e
confini delle celle, paginazione, Oggi, cambio d'anno e migrazione preferenze.
Rendering sintetico 360×800 con font reali ispezionato: quattro righe,
intestazione compatta senza sovrapposizione al fuso. Nessun altro intervento
di riduzione delle barre o dei caratteri.
Todo Test 2.65.0-dev / versionCode 2231 installata e avviata in-place sul
Galaxy con `make todo-test`; dati conservati, versione e processo verificati.
L'ispezione visiva resta quella sintetica, non uno screenshot del telefono.
Web/stabile pubblicati restano alla 229.
Build Web release 231 riuscita; collaudo browser HTTPS della 231 non eseguito.

## Build 230 — Agenda più compatta

Riepilogo dei calendari nascosti e «Azzera filtri» spostati nel pannello
Calendari: nessuna riga aggiuntiva sopra la griglia. L'azzeramento resta locale
al pannello fino ad «Applica». Le righe delle date hanno una lieve tinta
neutra nei temi chiaro e scuro, a parità di altezza.

`make check` superato: analisi pulita e 386 test Flutter, inclusa la verifica
che il riepilogo compaia solo nel pannello e che il reset richieda «Applica».
Rendering sintetico a 360×800 con font reali: mese chiaro/scuro e pannello
Calendari ispezionati, senza overflow. Todo Test 2.64.1-dev / versionCode 2230
installata in-place e avviata sul Galaxy con `make todo-test`; versione e
processo verificati, dati conservati. L'ispezione visiva è sul rendering
sintetico, non uno screenshot del dispositivo. Web/stabile restano alla 229.
Build Web release 230 riuscita; collaudo della 230 nel browser HTTPS non
eseguito e nessun nuovo deploy Web avviato.

## Build 229 — Agenda: protezione delle modifiche e navigazione

Todo Test 2.64.0-dev / versionCode 2229 installata con `make todo-test` sul
Galaxy S21 il 6 ottobre: versione e processo verificati, dati conservati.

Verifiche locali:
- `make check`: analisi pulita, 386 test Flutter, controlli Python, SQL e link.
- `:app:testDevDebugUnitTest`: superato; nuove regressioni su DST (gap,
  ambiguità, durata e fine ricorrenza) e retry dopo insert con risposta persa.
- Provider Android reale su emulatore, con sole fixture sintetiche: copia e
  retry sullo stesso ID, due restore senza duplicati, serie con occorrenza
  spostata e note, conversione Europe/Rome: PASS. Pulizia delle fixture riuscita.
  Il test ha riprodotto e corretto due rifiuti del provider nel ripristino delle
  eccezioni: usare DURATION e lasciare derivare ORIGINAL_ALL_DAY dalla serie.
- Build release Android arm64 e Web riuscite. Editor renderizzato con
  font reali alle dimensioni logiche S21, senza overflow.
- Chrome locale su origine isolata: sentinella SQLite ancora presente dopo
  refresh e chiusura/riapertura della scheda. Il certificato HTTPS locale non
  attendibile non è stato aggirato; collaudo HTTPS pubblico dopo il rilascio sotto.

Limiti: prova d'uso completa dei sei flussi sul Galaxy e ripristino di serie
reali su telefono vuoto ancora da completare. Contratto e comando del collaudo sintetico in
[Agenda](docs/architecture/AGENDA.md).

### Pubblicazione coordinata 229

Dopo `PUBBLICA`, Web, APK diretti stabili e track interno Google Play pubblicati
dal commit `05fdf3a45803a03fc3d3ae680d2b13442c0c56eb`:
[run 37469093626](https://github.com/gpmerola/deterministic-todo/actions/runs/37469093626)
interamente verde, inclusa parità degli endpoint pubblici 2.64.0+229.
Il primo run `37467757345` è stato annullato prima della pubblicazione: il
bundle Play compilava, ma il task `testPlayReleaseUnitTest` non esiste nella
configurazione Android corrente. Corretto in `testPlayDebugUnitTest`; verifica
locale con 19 test app e 8 runtracker, tutti superati. Nessun numero Play è
stato consumato dal tentativo interrotto.

Scaricati e verificati tutti i quattro APK pubblici: SHA-256 corrispondenti al
manifest, package stabile, versione 2.64.0 e firma identica all'APK arm64 della
2.40.1 precedente. VersionCode: universale 229, ARM32 1229, ARM64 2229, x86_64
4229; ARM64 precedente 2179, quindi aggiornamento compatibile per versione e
firma. Questo controllo non sostituisce un'installazione reale del canale direct.
Play ha accettato il bundle nel track interno; propagazione al tester e
installazione non sono state verificate. Sul Galaxy resta Todo Test 2229 e il
fallback Play resta disabilitato.

Chrome sul sito HTTPS pubblico: Impostazioni mostra 2.64.0 (229). Una task
sintetica creata e modificata sulla 225 è rimasta visibile, inclusa la modifica,
dopo il deploy, refresh e chiusura/riapertura della scheda. Sentinella poi
spostata nel cestino. Il test è stato svolto online, senza isolare il recupero
dalla sincronizzazione; la persistenza locale isolata è coperta dalla prova
loopback sopra. Nessun contenuto personale esportato nel repository.

## Build 225 — Web pubblicata

Web 2.61.0+225 pubblicata dopo conferma `PUBBLICA` dal commit `c1965db`:
run `37324593122` riuscito, `release-info.json` verificato. Todo Test 2225
pubblicata dalla CI rapida. Contiene «Nascondi festività» attivo per
default.

## Build 224 — Web pubblicata

Web 2.60.0+224 pubblicata dopo conferma `PUBBLICA` del 5 ottobre dal commit
`600d13e`: run `37321321449`, build e deploy riusciti, `release-info.json`
verificato. Comprende le build 219–224 (interfaccia, 3 giorni, cascata,
colori personali, ore compattate, elenco con data fissa). Todo Test 2224
pubblicata dalla CI rapida.

## Verifica 2217: sessione scaduta rinnovata in background — 4 ottobre 2026

- Nuovo login sul Galaxy alle 19:26 UTC, poi Todo Test lasciato chiuso.
- Evento sintetico su Google alle 20:21 UTC. La sincronizzazione è
  arrivata tardi per rete debole e calore; nel frattempo il job 7303 di
  nuovo tentativo risultava programmato.
- Alle 21:10 UTC Android avvia il processo solo come servizio, senza
  attività. Il token del login (19:26) viene ruotato alle 21:10:08, con
  sessione scaduta da oltre un'ora: il nuovo token resta attivo e non
  revocato. La copia caricata alle 21:10:10 contiene l'evento.
- Evento di prova eliminato da Google.

Resta da confermare con l'utente che l'app non chieda il login alla
prossima apertura.

## Incidente: logout dal telefono — build 213–216, corretto nella 217

L'utente ha dovuto rifare il login a Supabase sul Galaxy. Causa: il motore
headless dell'Agenda partiva con `autoRefreshToken: false`. Il giro delle
19:09 UTC è partito più di un'ora dopo l'ultima apertura; con la sessione
scaduta, `GoTrueClient.recoverSession` ha fatto il logout locale e
`SupabaseAuth` ha cancellato la sessione da `SecureSupabaseStorage`.

`auth.refresh_tokens` non mostra rinnovi nelle ultime 10 ore: niente
rotazione di token, solo cancellazione locale.

Correzione nella 217:
- `BackgroundSessionStorage` non cancella mai la sessione;
- refresh consentito e attesa del recupero della sessione;
- salvataggio della sessione prima di chiudere il motore;
- riprogrammazione dei job a ogni apertura.

Regressione in `test/background_session_test.dart`.

## Prova reale del job in background — 4 ottobre 2026

Telefono raffreddato (stato termico 1), app chiusa (in primo piano
YouTube), evento sintetico creato e poi eliminato su Google Calendar via
connettore. Nessuna apertura di Todo.

**Creazione (18:39 UTC):** Android avvia il processo solo per
`AgendaBackgroundJob`, cioè il motore headless. Due esecuzioni:

- 6,1 s senza caricamento;
- 3,6 s con copia caricata alle 18:49:33 UTC, contenente l'evento.

Un'esecuzione successiva si ferma in 261 ms: impronta invariata, Dart non
parte.

**Eliminazione (18:59 UTC):** l'evento sparisce dal provider. Il job parte
alle 19:09:55 UTC e lavora 12,7 s, con molti `onNetworkChanged`: rete
mobile instabile. La copia non si aggiorna, e la 215 non riprovava fino
alla modifica successiva del calendario.

La 216 aggiunge il nuovo tentativo con attese crescenti e il caricamento
dal job orario quando l'impronta è cambiata.

## Verifica finale build 215 — 4 ottobre 2026

**Galaxy:**
- 2215 installata;
- copia caricata alle 16:44 UTC con 271 eventi, `main` =
  `sennar.pierp@gmail.com`, `ai` = «✨ Assistente»;
- nessuna richiesta aperta o fallita.

**Web 215:** il + propone `sennar.pierp@gmail.com`, come il telefono. Il
modulo è stato chiuso senza salvare.

In quel momento job e motore headless non erano verificabili: stato
termico 3, poi verificati nella sezione precedente.

## Build 215 — Web e Todo Test pubblicati

- `make check` superato: 343 test Flutter, SQL e documentazione.
- Todo Test 2215 pubblicata dalla CI rapida sul commit `74d560c`.
- Web 2.56.2+215 pubblicata dopo conferma `PUBBLICA`: run `37216741025`,
  build e deploy riusciti, `release-info.json` pubblico verificato.

## Prova reale Web → telefono — 4 ottobre 2026

Eseguita su richiesta dell'utente, con evento sintetico «Prova Web (da
eliminare)» nel calendario «✨ Assistente».

**Creazione:**
- dal Web l'evento compare subito come ⏳ con «1 in attesa»;
- il job orario forzato è rinviato da Android per temperatura, quindi
  l'app è stata aperta via ADB;
- richiesta presa e applicata in 0,2 s; evento nel provider (calendar_id 39,
  18:00 `Europe/London`); nuova copia caricata;
- sul Web l'evento appare senza ⏳.

**Eliminazione:** dal Web l'evento sparisce subito. Al ritorno dell'app la
richiesta è `done` in 0,8 s e l'evento non è più nel provider.

**Difetti osservati:**
1. PostgREST ordina in modo decrescente per default: la coda arrivava dalla
   più recente. Corretto nella 214 con test.
2. Sul Web ⏳ è apparso come quadratino al primo disegno, perché il font
   emoji non era ancora caricato. Nella 215 il segno è il testo «In attesa ·».
3. Lentezza del Web non confermata. La scheda di Chrome automatizzata era
   `visibilityState: hidden`: con la finestra non visibile Chrome sospende
   il disegno e rallenta i timer, e nessun long task è stato misurato. Va
   verificata in una finestra visibile. Reale invece «Fuso non
   riconosciuto» durante il caricamento: nella 215 mostra «Fuso…».
4. Sul Web «Nuovi eventi in» non seguiva il telefono: nella 215 la copia
   segnala `main` e `ai`.

## Agenda dal Web, background, sovrapposizioni, ricerca — build 213

`make check` superato:

- 341 test Flutter;
- PGlite per la coda (`agenda_requests.mjs`) e catena completa delle
  migrazioni (`safe_purge.mjs`);
- 8 test JVM per `AgendaChannel` e `AgendaBackground`.

2213 pubblicata con `make todo-test-remote` (commit `38e1c53`), senza ADB per
non disturbare il telefono in uso.

Non ancora fatto:

- migrazione `202610050001_agenda_requests.sql` (SHA-256
  `cdb7281609342be3d2fb7b7e2cc6aed3d5fe447da0e0992a7b9b12e9d7937d4f`)
  applicata dall'utente nel SQL Editor il 4 ottobre 2026. Verifica:
  - RLS attiva con 4 policy e trigger del limite presente;
  - `anon` non legge e non esegue le RPC;
  - `authenticated` legge e inserisce il payload, ma non può impostare né
    modificare lo stato;
  - claim e complete sono eseguibili solo da `authenticated`;
- sul dispositivo vanno verificati il job a trigger e il motore headless.

Web 2.56.0+213 pubblicata dopo conferma `PUBBLICA` dal commit `0743df3`: run
`37213680721` riuscito, `release-info.json` pubblico verificato.

Galaxy 2213: job 7301 (trigger `content://com.android.calendar`) e 7302
(orario, persistente) programmati dall'app. Le esecuzioni forzate con
`cmd jobscheduler run -f` sono rinviate da Android: «Restricted due to:
thermal» (telefono caldo, hotspot attivo). È un comportamento corretto, non
un errore dell'app; l'esecuzione reale resta da verificare.

## Agenda sul Web in sola lettura — build 212

`make check` e `make check-sql` superati (314 test Flutter, PGlite per la
nuova RPC). 2212 pubblicata con `make todo-test-remote`.

Migrazione `202610040001_agenda_mirror.sql` (SHA-256
`3e3f5390377376e1e8031ba473ca69ca45c8696d78f8917fd6c257ad23fc1e74`) applicata
il 4 ottobre 2026 dal SQL Editor, dopo approvazione dell'utente. Verifica
post-applicazione: RLS attiva su entrambe le tabelle, 2 policy, `authenticated`
legge ma non scrive, `anon` non legge, RPC `security definer` eseguibile solo
da `authenticated`.

Web: `publish-web.yml` non ha più le guardie fisse 2.42.0/189; legge la
versione da `pubspec.yaml`, richiede una build maggiore di quella online e
verifica l'identità pubblica con gli stessi valori. Web 2.55.0+212 pubblicata
dopo conferma `PUBBLICA` dal commit `c4c3d70`: run `37207528222`, build e
deploy riusciti; `release-info.json` pubblico verificato (2.55.0, 212,
`c4c3d70`). Galaxy con 2212 installata; nessuna copia ancora in
`agenda_snapshots` al momento della verifica (app non riaperta dopo la
migrazione).

## Oggi + agenda, attività collegate, annulla ✨ — build 211

`make check` superato (310 test): striscia di Oggi, «Preparare» dal
dettaglio, giorni lavorativi, nomi brevi, esportazione nel calendario
principale. L'annulla di ✨ non ha un test automatico (usa repository e
plugin calendario dalla shell). 2211 pubblicata con `make todo-test-remote`,
senza ADB. Non ancora vista sul dispositivo.

## Calendario dell'assistente verificato — builds 209–210

Sul Galaxy (2209): il calendario Google «✨ Assistente» creato dall'utente è
presente nel provider (id 39, visibile, sincronizzato, scrivibile) e attivo
nell'Agenda. Nel pannello Calendari: «Nuovi eventi in» =
`sennar.pierp@gmail.com`, «Eventi creati da ✨ in» = «✨ Assistente»;
heydoc spento e Semble acceso. La 210 corregge solo l'etichetta del primo
menu, che citava ancora l'assistente. `make check` superato.

## Prova reale dell'assistente con DeepSeek — builds 207–208

L'utente ha inserito una chiave DeepSeek sul Galaxy. Prove via ADB, solo
Interpreta: nessun «Crea», quindi nessun elemento scritto.

Con la 2206:
- 3 note su 4 interpretate correttamente;
- la nota con due richieste falliva sempre con «risposta non comprensibile».
  Il ragionamento di `deepseek-flash`, attivo di default, troncava il json.

La 2207 (`thinking: disabled`, `max_tokens` 4096, messaggio per risposta
troncata) l'ha risolta:
- due attività ven 9 e lun 12 ott;
- PRADA collegata all'evento reale e al progetto giusto;
- supervisione 09:00–09:30.

Unico errore residuo: data inventata per «comprare latte». La 2208 lo corregge
nelle istruzioni, verificato: «Senza data». Nella 2208 anche riunione più
attività del giorno prima, con nota sull'ambiguità di «giovedì prossimo».
`make check` 304 test. Il calendario predefinito resta da scegliere
all'utente (Agenda › Calendari › Nuovi eventi in).

## ✨ Scrivi o detta e scorrimento laterale — build 206

`make check` superato (302 test). `test/ai_capture_test.dart` copre:
- validazione della risposta, con 4 elementi scartati su 8;
- formato delle richieste a DeepSeek (json mode, `deepseek-flash`) e a Claude;
- assenza di richieste senza chiave;
- flusso revisione → creazione solo degli elementi selezionati.

Nessuna chiamata reale al fornitore eseguita: serve la chiave dell'utente.
2206 pubblicata con `make todo-test-remote`, senza ADB. Da provare con
l'utente: inserimento chiave DeepSeek, una nota reale, creazione con ✨ e
comparsa in Agenda e in Google.

## Mese a schermo intero e chiave AI — build 205

`make check` superato (296 test, tra cui `test/ai_settings_test.dart` e il mese
a tutta altezza con i giorni dei mesi vicini). La 2205 è pubblicata sul
manifest rolling con `make todo-test-remote`, senza ADB, per non interrompere
l'utente. Nessuna chiamata a un LLM nel codice: solo salvataggio della chiave
e verifica con GET dell'elenco modelli, senza contenuti. Non ancora vista sul
dispositivo.

## Spazio ai giorni e orario compatto — build 204

`make check` superato (293 test, 34 in `test/agenda_test.dart`, compresi
l'intestazione in un'unica riga con il menu Cerca/Impostazioni e
`compactTime`). Per non disturbare l'utente, che stava usando il telefono, la
2204 è stata pubblicata sul manifest rolling con `make todo-test-remote`,
senza installazione ADB: l'utente aggiorna dall'app. Non ancora vista sul
dispositivo.

## Attività in agenda, settimana, ripeti, ricerca — build 203

`make check` superato (291 test, 32 in `test/agenda_test.dart`):
- flag locali per attività e serie;
- regole RRULE con fine inclusiva;
- vista settimana in scala e creazione da spazio libero;
- ordinamento e sezione Eventi della ricerca.

`AgendaChannelTest` 5/5 (escape di `LIKE`). Installata via ADB la 2203, dati
conservati. Sul Galaxy la vista 2 settimane mostra le celle nuove (pallino e
titolo). Gli altri controlli a video sono stati interrotti perché l'utente
stava usando il telefono: due tocchi ADB sono finiti su WhatsApp, senza
effetti (nessuna chiamata attiva in `dumpsys telecom`, campo messaggio
vuoto). Da qui in poi non si tocca lo schermo senza conferma.
Vista settimana, attività in agenda, Ripeti e ricerca eventi non sono ancora
stati provati sul dispositivo.

## Modifica, vista 2 settimane e fuso — builds 201–202

`make check` superato (285 test, 26 in `test/agenda_test.dart`);
`AgendaChannelTest` 4/4 (fuso del dispositivo, orario originale nel fuso
dell'evento). Le varianti dev, play e direct compilano. Installate via ADB la
2201 e la 2202, logcat senza crash. Sul Galaxy: vista 2 settimane predefinita
con «Europe/London · UTC+1» visibile; vista giorno con data intera e fuso;
dettaglio dell'evento ricorrente Google «PDP CPD» con Modifica ed Elimina.
Dettaglio della riunione KCL «Case based discussions» anch'esso modificabile:
il provider la registra con l'utente come organizzatore (`organizer` =
account, `isOrganizer=1`), mentre «TNG Meeting» (`isOrganizer=0`) non lo è.
Nessuna modifica né eliminazione reale eseguita sul dispositivo; flussi
coperti dai test. La 202 riduce il pulsante calendari a icona e conteggio.

## Creazione eventi e confronto con Google — builds 199–200

`make check` superato (280 test, 21 in `test/agenda_test.dart`). Installate via
ADB la 2199 e la 2200. Sul Galaxy il modulo **Nuovo evento** si apre dal **+**
e si chiude senza salvare; nessun evento di prova scritto nei calendari reali.
Con la 2199 il calendario proposto era `dr.merolagp@gmail.com`, nascosto
nell'Agenda; dalla 2200 si propone un primario mostrato (verificato).
Confronto di 3 mesi (3/10/2026–3/1/2027) tra API Google dell'account
`sennar.pierp@gmail.com` e provider del telefono: coincidono il primario (28
eventi più 1 di giornata intera del 2/10, incluso dall'allargamento UTC),
Semble (19), heydoc (20) e SLAM (3). Todoist: 1.398 occorrenze sul telefono;
la sola prima pagina API (250) copre fino al 22/10, confronto completo non
fatto. Differenze attese dell'Agenda: duplicati con stesso titolo e orario
uniti (PDP 6/12, festività ripetute tra account); heydoc e Semble sono le
stesse visite con titoli e durate diversi, quindi non vengono uniti.

## Filtri e vista giorno — builds 197–198

`make check` superato (277 test, 18 in `test/agenda_test.dart`): impaginazione
della giornata, filtri, persistenza e vista giorno in scala. `AgendaChannelTest`
verde. `make todo-test` ha installato via ADB la 2197 e la 2198 (logcat senza
crash). Sul Galaxy con la 2197: vista giorno del 6 ottobre con vuoti
proporzionali, due riunioni delle 11:00 affiancate e «Partecipa · Teams». La
198 accorcia il titolo, prima tagliato, e aggiunge il margine della barra di
navigazione; non verificata a video perché il telefono si è bloccato. I filtri
non sono ancora stati impostati sul dispositivo. L'utente ha attivato il
calendario SLAM: dopo un intervento ADB su `sync_events`, il telefono ha
scaricato 35 eventi (34 «Tentative», 1 «Busy»).

## Agenda veloce — build 196

Causa della lentezza alla riapertura: la vista ripartiva da zero a ogni
navigazione, e il plugin calendario eseguiva due query extra per evento
(partecipanti, promemoria) trasferendo l'HTML completo degli inviti. Ora una
query nativa `Instances` per intervallo (`AgendaChannel`) e cache in memoria
con rilettura in background. `make check` superato (272 test) e
`AgendaChannelTest` 2/2. Tutte le varianti Android compilano. `make todo-test`
ha installato via ADB la 2196 con dati conservati. Sul Galaxy, uno screenshot
250 ms dopo il tocco su Agenda, tornando da Oggi, mostra la griglia di ottobre
già popolata; logcat senza errori. Condivisione SLaM verso KCL rifiutata da
Outlook Web («couldn't be sent»); la pubblicazione consente solo libero/occupato.

## Agenda vista Mese — builds 194–195

`make check` superato (270 test, 11 in `test/agenda_test.dart`, incluso un test
della griglia a 1080×2400). `make todo-test` ha installato via ADB la 2194 e la
2195 con dati conservati. Verificato con screenshot sul Galaxy: vista Mese
predefinita con griglia dal lunedì, oggi evidenziato, eventi colorati per
calendario e «+N»; scorrimento fino a dicembre; il dettaglio di un giorno di
novembre mostra orari e il pulsante Teams riconosciuto su riunioni KCL. La 195
corregge l'intestazione, che con la 194 andava a capo («12/29 calendari»).
Pulsante Teams e apertura evento non ancora toccati.
L'account SLaM non si può aggiungere a Outlook: l'app è gestita da Intune con
l'account KCL e accetta un solo account gestito (schermata dell'utente).

## ADB ripristinato e Agenda collaudata — builds 192–193

ADB era chiuso sulla 5555 dopo un riavvio Android. Ripristinato via Tailscale:
Debug wireless su Wi-Fi, nuovo pairing con codice, `adb tcpip 5555`, poi
`s21-adb` connesso su IPv6 (procedura in
[ADB_WIFI](docs/operations/ADB_WIFI.md)). Sul Galaxy la 2191 risultava già
installata dall'utente; `dumpsys jobscheduler` mostra un solo job WorkManager
del package `.dev`, coerente con la pulizia di Movimento. Il provider calendario
espone 29 calendari: due account Outlook KCL sono sincronizzati, nessun
account SLaM/NHS.
La 192 elenca anche i calendari nascosti dal sistema, spenti di default; la 193
non ripete i nomi uguali dei calendari di provenienza. `make check` superato
(269 test). `make todo-test` ha installato via ADB la 2192 e la 2193 con dati
conservati. Verificato con screenshot: Agenda in navigazione, 12 di 29
calendari, eventi di oggi e domani, festività su due calendari unita in una
riga con nome singolo, selettore con calendari KCL attivi e Google secondari
spenti. Non ancora provati il pulsante Teams e l'apertura di un evento.

## Agenda unificata — build 191

Nuova sezione Agenda Android in sola lettura sul calendario di sistema
([contratto](docs/architecture/AGENDA.md)). `make check` superato con 266 test
Flutter (7 nuovi in `test/agenda_test.dart`) e analisi pulita. ADB ancora
rifiutato sulla porta 5555 (Tailscale raggiungibile, `adb tcpip` da riattivare
dopo un probabile riavvio): `make todo-test` ha pubblicato la 2.44.0 /
versionCode 2191 dal commit `81d0e9a`; Verify `37119595728` e Publish Todo Test
Fast `37119592016` riusciti. Manifest finale: canale dev, SHA-256 coincidente
con l'APK CI (22.921.303 byte), versionCode 2191. Non provata sul Galaxy:
restano da verificare permesso, calendari Outlook visibili, duplicati e
pulsante Teams. Comprende anche la 190, mai installata.

## Movimento archiviato, solo passi — build 190

Su decisione dell'utente il modulo Movimento è ridotto al contapassi; il resto è
nel tag e branch `archive/movimento-completo-b189` (pubblicati su GitHub).
Inventario e ripristino: [Movimento archiviato](docs/archive/MOVIMENTO.md).
`make check` superato con 259 test Flutter e analisi pulita;
`:runtracker:testDebugUnitTest` 8/8 (incluso `MovementArchiveCleanupTest`),
test strumentati compilati ma non eseguiti (nessun dispositivo). ADB non
raggiungibile (timeout IPv6 e IPv4 Tailscale): `make todo-test` ha pubblicato
la 2.43.0 / versionCode 2190 dal commit `4d254da`; Verify `37117257311` e
Publish Todo Test Fast `37117254810` riusciti. Manifest finale: canale dev,
SHA-256 coincidente con l'APK, `apkanalyzer` conferma package `.dev`, versionCode
2190 e assenza dei permessi posizione, Bluetooth, notifiche e Health Connect.
APK arm64 CI 22.855.691 byte contro 23.141.568 della 189 (−286 KB; dex
−600 KB non compresso). L'APK locale di `make todo-test` è più grande
(24,1 MB) perché non usa `--split-debug-info`, a differenza della CI che lo
sostituisce. Non ancora installata né provata sul Galaxy: da verificare la
pulizia dei lavori archiviati, l'anello e il pannello passi.

## Pianificazione, Inbox e shell — build 189

`make check` superato con 260 test Flutter e analisi pulita; `make check-generated`
superato. Web release 188 e 189 compilate e servite sulla stessa origine
localhost in Chrome headless: attività creata con la 188, poi caricato il
bundle 189 (nessun service worker, trasferimento completo) che ha migrato
SQLite WASM allo schema 11 conservandola; una nuova attività creata dopo la
migrazione e la precedente restano dopo refresh, console senza errori. HTTPS
locale con CA esplicita risponde 200 per pagina, `main.dart.js`, `sqlite3.wasm`,
`drift_worker.js` e `version.json` 2.42.0+189. ADB non raggiungibile
(porta 5555 rifiutata su Tailscale): `make todo-test` ha pubblicato la
2.42.0 / versionCode 2189 sul manifest rolling dal commit `d81bc2d`; Verify
`36285809685` e Publish Todo Test Fast `36285806530` riusciti, e il manifest
finale ha canale dev e SHA-256 coincidente con l'APK pubblicato. L'utente riferisce
di aver installato la 2189 sul telefono; non verificato via ADB (porta 5555
ancora rifiutata). Web 2.42.0+189 pubblicata dopo conferma `PUBBLICA` dal commit
`cf6a331`: run `36286530167`, build e deploy riusciti, `release-info.json`
pubblico verificato. Chrome headless con profilo vuoto sul sito pubblico:
avvio, creazione di un'attività e persistenza dopo refresh, console senza errori. Contratto: [pianificazione e viste](docs/architecture/TODO_PLANNING_MODEL.md).

## Anteprima descrizione — build 188

`make check` superato con 247 test Flutter e analisi pulita; `make check-generated`
superato. ADB non raggiungibile (Tailscale): `make todo-test` ha pubblicato la
2.41.0+188 sul manifest rolling, verificato con canale dev e commit `4518052`.
Verify `36237232202` e Publish Todo Test Fast `36237230165` riusciti. L'utente
riferisce di aver installato la 2188 sul telefono tramite aggiornamento; non
verificato via ADB (non raggiungibile). Web 2.41.0+188 pubblicata dopo conferma
`PUBBLICA` dal commit `da63744`: run `36239804372`, build e deploy riusciti,
`release-info.json` pubblico verificato.

## Pausa indipendente dai frame — build 186

Con la 2185 un avvio a schermo spento ha continuato a sincronizzare in
background (cicli 2–11, sei fallimenti con retry, recupero alle 20:05:12 UTC)
con attività `STOPPED`. Causa e correzione in
[sincronizzazione e storico](docs/architecture/TODO_SYNC_AND_HISTORY.md).
La 2186 installata a schermo spento ha eseguito un solo ciclo iniziale, fallito
alle 20:10:45 UTC, poi si è ripresa alla riapertura (ciclo 3 riuscito alle
20:10:55). La build 187 elimina anche quel ciclo iniziale.
`make check` superato con 245 test Flutter; `make check-generated` superato.
Verify `36184413603` e Publish Todo Test Fast `36184409842` riusciti sul commit
`425cdc2`. `make todo-test` ha installato la 2.40.9 / versionCode 2187 al secondo
tentativo (il primo `adb install` via IPv4 è fallito) con schermo spento: nessun
ciclo all'avvio in background. Il registro eventi mostra una ripresa di circa due
secondi alle 20:17:18 UTC, con ciclo 2 riuscito alle 20:17:20; fino alle
20:23:32, attività `STOPPED`, nessun altro ciclo né fallimento.
Web 2.40.9+187 pubblicata dopo conferma `PUBBLICA` dal commit `7cedb62`: run
`36185727429`, build e deploy riusciti; `release-info.json` pubblico verificato.
Non ripetuto il collaudo in Chrome; le schede aperte vanno ricaricate.

## Ripresa breve allo sblocco — builds 184–185

`make check` superato con 243 test Flutter e analisi pulita; `make check-generated`
superato. `make todo-test` ha installato in-place la 2.40.7 / versionCode 2185;
ciclo completo `healthy` alle 19:49:17 UTC, zero operazioni pendenti e zero
conflitti. Verify `36181862462` e Publish Todo Test Fast `36181857626` riusciti
sul commit `b973dd8`. Resta da osservare uno sblocco reale con la 2185: il
provider non deve più registrare un fallimento pochi secondi dopo la ripresa.
Web resta alla 183 fino a conferma `PUBBLICA`.

## Invii in blocco e divergenza — build 183

Revisione del codice, senza incidente reale associato. Contratto in
[sincronizzazione e storico](docs/architecture/TODO_SYNC_AND_HISTORY.md).
`make check` superato con 240 test Flutter e analisi pulita; `make check-generated`
superato. Misura sintetica: 50 modifiche da 150 a 52 richieste, una ricevuta.
`make todo-test` ha installato in-place la 2.40.5 / versionCode 2183; ciclo
completo `healthy` alle 19:01:31 UTC con una richiesta, zero operazioni pendenti
e zero conflitti. Verify `36176956625` e Publish Todo Test Fast `36176950283`
riusciti sul commit `1f5e5a7`. Web resta alla 181 fino a conferma `PUBBLICA`.

Web 2.40.5+183 pubblicata dopo conferma `PUBBLICA` dal commit `f9adcc7`: run
`36179562000`, build e deploy riusciti, `release-info.json` pubblico verificato.

Osservazione, causa individuata nella build 185 (la 184 correggeva un caso
diverso): con la 2182 il provider registra un controllo completo
fallito per rete alle 18:51:32 UTC (ciclo 3, fase overview, coda zero) mentre
lo schermo era in stand-by, dopo un avvio via ADB con telefono bloccato. Alle
19:0x l'attività risultava `STOPPED`. La causa non è attribuita: il giornale
dettagliato non è leggibile via ADB. Si è ripetuta con la 2183 alle
19:24:59 UTC, con Todo Test in background e schermo acceso su un'altra app.
Si è ripetuta con la 2184 alle 19:37:00 UTC. Il registro eventi Android mostra
una ripresa di circa un secondo allo sblocco prima dei casi 19:24:59 e 19:37:00;
causa e correzione in [sincronizzazione e storico](docs/architecture/TODO_SYNC_AND_HISTORY.md).

## Ciclo di vita e ricerca — build 182

Revisione del codice, senza incidente reale associato. Correzioni e limiti in
[sincronizzazione e storico](docs/architecture/TODO_SYNC_AND_HISTORY.md).
`make check` superato con 235 test Flutter e analisi pulita; `make check-generated`
superato. `make todo-test` ha installato in-place la 2.40.4 / versionCode 2182
sul Galaxy preservando i dati; ciclo completo `healthy` alle 18:46:56 UTC con una
richiesta, zero operazioni pendenti e zero conflitti. Aprendo e chiudendo la
tendina notifiche via ADB `last_success_at` è rimasto invariato: nessun nuovo
controllo completo. Il ritorno da background non è verificato sul telefono,
perché il dispositivo è entrato in stand-by bloccato; è coperto dai test
sintetici. Verify `36175440611` e Publish Todo Test Fast `36175435730` riusciti
sul commit `7514db0`. Web resta alla 181 fino a una nuova conferma `PUBBLICA`.

## Isolamento errori sync — build 181

Revisione del codice, senza incidente reale associato: un rifiuto server per
singola riga fermava invii e pull dell'intero account; Realtime poteva perdere
notifiche in blocco o dopo un fetch fallito fino al timer di 10 minuti; la
sottoscrizione poteva agganciarsi a uno snapshot già letto. Correzioni e limiti
in [sincronizzazione e storico](docs/architecture/TODO_SYNC_AND_HISTORY.md).
`make check` superato: 231 test Flutter, analisi statica pulita, test strumenti
e link documentali; `make check-generated` superato. `make todo-test` ha
installato in-place la 2.40.3 / versionCode 2181 sul Galaxy preservando i dati.
Alle 18:14:10 UTC il provider riporta `healthy`, build 2181, zero operazioni
pendenti e zero conflitti. Verify `36171968918` e Publish Todo Test Fast
`36171960700` completati con successo sul commit `1b2c72d`. Web 2.40.3+181
pubblicata dopo conferma `PUBBLICA` dal commit `6704525`: run `36173491508`,
build e deploy riusciti; `release-info.json` pubblico verificato via HTTPS con
versione, build e commit corretti. Non è stato ripetuto il collaudo in Chrome;
le schede già aperte devono essere ricaricate per usare il nuovo client. Il ramo del rifiuto
server e il fallback Realtime sono verificati solo sinteticamente: nessun rifiuto
reale era presente sul telefono.

## Recupero sincronizzazione — build 180

Diagnostica tecnica Galaxy sulla 2179: 11 operazioni pendenti, un conflitto
nell'ultimo ciclo completato e successivo `ClientException` in `taskUpload`.
La scheda Web aperta non aveva operazioni in attesa. Nessun database personale
è stato estratto. Il test sintetico riproduce un difetto nel recupero attività:
un `replace` scelto nello storico restava preceduto da tentativi incerti che
facevano fallire il writer prima di applicare la scelta. La 180 delimita gli
intenti all'ultimo ripristino, conservando quelli successivi e tutti gli ID
fino alla ricevuta. Contratto: [sincronizzazione e storico](docs/architecture/TODO_SYNC_AND_HISTORY.md).

`make check` superato: 224 test Flutter, analisi statica pulita, 12 test strumenti,
link documentali e controlli PostgreSQL/PGlite. `make check-generated` superato.
Build release Web e Todo Test superate; il tool canonico `make todo-test` ha
installato in-place la 2.40.2 / versionCode 2180 sul Galaxy, preservando i dati.
Alle 11:30:37 UTC il provider riporta `healthy`, zero operazioni pendenti e zero
conflitti: le scelte già in coda hanno quindi recuperato il caso reale senza
ulteriori ripristini o cancellazioni. Restano eventi di trasporto Realtime
separati (`channelError`), non una coda bloccata. Disponibilità Web e Play sotto.
Verify `35090803334` e pubblicazione Todo Test
`35090797222` completate con successo sul commit `96fd14c`. Il manifest pubblico
rolling espone 2.40.2+180, canale dev e lo stesso commit; pubblicazione e verifica
dell'APK sono passate. La consegna ADB locale e la pubblicazione rolling sono
due build della stessa sorgente, non una prova del flusso OTA sul telefono.

### Pubblicazione Web e diagnosi del blocco Pages

Web 2.40.2+180 pubblicata dal commit `60fb9dd`: run `35139596058`, tentativo 2,
riuscito dopo il recupero del solo job deploy. `release-info.json` pubblico
verificato via HTTPS con versione, build e commit corretti. La build aveva già
superato analisi, generazione e 224 test Flutter. Chrome reale, nuova scheda
sullo stesso profilo: apertura riuscita, Impostazioni mostra `2.40.2 (180)` e
stato `Sincronizzato`; dopo refresh la vista Oggi mostra ancora le attività.
Questa è una verifica di riapertura, non un nuovo test di modifica offline.
La scheda dell'utente già aperta non è stata ricaricata
per preservare eventuali modifiche in corso.

La causa dei rifiuti non era un guasto Pages: le annotazioni del check-run
`104941554133` indicavano che `agent/todo-ux-sync-hardening` non era ammesso
dalle regole dell'environment `github-pages`. La lista consentiva soltanto
`main` e `agent/verify-public-release-token`. Aggiunta la sola regola esatta del
branch operativo (policy `60177181`), conservando tutte le altre protezioni.
Per annullare questa modifica basta rimuovere quella singola policy: i futuri
deploy dal branch tornerebbero bloccati, senza cancellare il sito pubblicato.

Le notifiche email riportavano build riuscita e deploy fallito. L'assenza di
step/log nel job era conseguenza del rifiuto preventivo; non provava un guasto
del servizio. Il workflow manuale `.github/workflows/publish-web.yml` separa
Web da Play, ma da solo non poteva correggere la policy dell'environment.
Diagnosi e recovery ripetibile in [RELEASE](docs/operations/RELEASE.md).

Play aveva già accettato la build 180 nel run `35092161105`; nel successivo
`35093331932` l'errore era `Version code 180 has already been used`, non un
problema di credenziali. Nessun ulteriore invio Play eseguito per recuperare Web.
Gli APK diretti stabili restano alla release precedente; la parità della
release coordinata non è dichiarata completata.

## Build 179 — Paginazione e diagnostica

Diagnosi e contratto: [paginazione sync](docs/architecture/TODO_SYNC_PAGINATION.md).
Difetto riprodotto con fixture sintetiche: 73 task recuperate su 1.501, con
vecchio client e server che rispetta l'ordine richiesto. `make check` superato:
221 test Flutter, analisi statica, 12 test strumenti, link e SQL.
`make check-generated` conferma Drift coerente, senza modifiche allo schema.

Build Web release distribuibile e fixture compilate. Chrome su origine localhost
isolata: 601 attività sintetiche recuperate, inclusa la sentinella con UUID minimo;
coda zero. La sentinella sopravvive al refresh con server sync spento. La prova
release ha riprodotto separatamente la mancata classificazione degli errori
minificati, corretta con controlli di tipo. Dopo il ripristino del server,
il client recupera automaticamente senza pulsante Riprova. HTTPS risponde 200
con CA locale esplicita; UI verificata su HTTP localhost, contesto sicuro,
senza aggirare avvisi di certificato.

APK Todo Test finale compilato e verificato localmente tramite il tool canonico:
2.40.1-dev, versionCode 2179, arm64 24,4 MB. `make todo-test` ha pubblicato
direttamente dal Mac in assenza di ADB, verificando il digest dell'asset.
[CI Verify](https://github.com/gpmerola/deterministic-todo/actions/runs/34698838332)
e [pubblicazione Todo Test](https://github.com/gpmerola/deterministic-todo/actions/runs/34698836044)
superate. Manifest rolling ricontrollato dopo la CI: 2.40.1, build 179, dev,
sorgente `edeaa0e40fa944c8e5798fca1f97e20d94141e60`.
SHA-256 arm64 corrispondente al digest GitHub:
`9ed787abd5bae65f22a71274047920941075e09cd764a69e3267d7efb0701bdc`.

Release stabile **2.40.1+179 pubblicata** dopo conferma `PUBBLICA`:
[workflow coordinato](https://github.com/gpmerola/deterministic-todo/actions/runs/34699496909)
interamente verde, inclusa parità finale. Web pubblico e manifest APK riportano
versione, build e sorgente `f2f8eddaa9b6df719e7038402972b1dfc6a60618` identici;
i quattro SHA-256 del manifest corrispondono ai digest degli asset GitHub.
Play ha accettato il bundle nel track interno; propagazione al tester non
verificata. Permesso temporaneo Pages del branch rimosso dopo il deploy;
nessun merge eseguito. Le schede Web precedenti vanno ricaricate.

Todo Test è aggiornabile senza ADB da Impostazioni → Controlla aggiornamenti
→ Aggiorna, poi conferma Installa di Android; versione attesa 2.40.1-dev (2179).
Il telefono aveva perso ADB dopo il confronto visivo. Il controllo serale del
12 settembre via IPv6 Tailscale conferma ora **2.40.1-dev (2179)** installata,
con `lastUpdateTime=2026-09-12 16:31:23`. Il provider registra un successo della
2179 alle **19:00:54 UTC**, 139 ms, una richiesta, zero intenti finali e zero
conflitti. Al controllo successivo è però in errore: **20:01:10 UTC**, fase
`overview`, `auth_transport / AuthRetryableFetchException`, sessione `expired`,
rete `vpn+mobile`. Questo indica un fallimento del rinnovo attraverso il trasporto,
non prova credenziali errate né una nuova divergenza dati. Dopo aver riportato
l’app in primo piano, la lettura successiva conferma **healthy** e un nuovo
successo alle **20:01:32 UTC**: 130 ms, una richiesta, zero intenti finali,
zero conflitti e Realtime `subscribed`. L’errore è quindi superato; i campi
storici `last_auth_state` e `last_failure` non descrivono il nuovo successo.
La convergenza del contenuto dei due client resta da verificare; lo storico
Android della singola attività non è stato ricostruito.

Configurazione locale ADB aggiornata in [ADB_WIFI](docs/operations/ADB_WIFI.md):
`s21-adb` risponde con il modello atteso, porta TCP 5555, VPN sempre attiva ed
esenzione batteria Tailscale confermate. Plist valido, LaunchAgent caricato con
intervallo 30 secondi e ultima uscita 0. Disconnesso solo il trasporto S21 e
verificata la riconnessione automatica con nuova risposta del modello, senza
richiamare manualmente lo script né riavviare il server ADB. Il precedente
collaudo su rete mobile è descritto nel riferimento locale dell’utente; in questa
verifica non sono stati modificati Wi-Fi, VPN o impostazioni batteria. Il tentativo di smoke test nella scheda pubblica dopo deploy
è bloccato dal collegamento browser (`Debugger unattached`); gli endpoint
pubblici sono verificati. Nessun contenuto personale o log grezzo nel repository.

## Build 178 — Controllo unificato e cache

Contratto e recovery: [sincronizzazione compatta](docs/architecture/TODO_SYNC_PERFORMANCE.md).
`make check`: 214 test Flutter, analisi statica, 11 test strumenti, link e SQL
superati. `make check-generated`: Drift coerente. Galaxy Validation: 33 test
passati, un caso desktop escluso; la prova aggiuntiva di 1.001 purge è passata
localmente. Il rerun hardware che la includeva si è interrotto prima dei test
per cambio porta/offline ADB; non è conteggiato come superato.

20.000 task sintetiche, cache già pronta: 154 ms sul Galaxy (comprende il server
mock); non è una stima della latenza di produzione. Verificati migrazione 9→10,
conservazione outbox, rollback/cache dopo riapertura, cambi remoti di progetti e
sezioni, registro purge e separazione degli intenti tra domini.

`make todo-test` ha installato in-place **2.40.0-dev, versionCode 2178**, APK
arm64 24,4 MB. Migrazione 004 applicata in Supabase dopo consenso specifico:
EXECUTE autenticati true, anon false. Nessun task modificato dalla migrazione.

Misure reali via provider sicuro della build 2178:
- prima della 004, successo 15:56:47 UTC: **3.275 ms**, 25 richieste, rete
  3.031 ms, confronto locale 35 ms, applicazione purge 0 ms, coda finale zero;
- dopo la 004, successo **16:01:41 UTC**: **250 ms**, **una richiesta**, rete
  247 ms, confronto locale 1 ms, applicazione purge 0 ms, coda finale zero.
Sono osservazioni di cicli senza lavoro residuo, non una garanzia di 250 ms per
ogni rete o quantità di modifiche. Nessun contenuto personale ispezionato.

Web release distribuibile e fixture compilate. Chrome su localhost isolato:
attività e link sincronizzati e conservati dopo refresh con server sintetico
spento. HTTPS risponde 200 con CA esplicita; UI provata su HTTP localhost,
contesto sicuro, senza aggirare avvisi certificato.
[CI Verify](https://github.com/gpmerola/deterministic-todo/actions/runs/34619903402)
e [pubblicazione Todo Test](https://github.com/gpmerola/deterministic-todo/actions/runs/34619899790)
superate. Manifest rolling pubblico verificato: 2.40.0, build 178, dev, sorgente
`b4fb63c15d7755b8d289593496b6c15fa5cd5b3a`. SHA-256 arm64 corrispondente al digest
GitHub: `2861f521c6ed9943f2127d2c69d06ff2460dc0a573376c55bfcd66a67086e902`.
Web/Play stabili restano alla 2.38.0+174; la 178 è distribuita su Todo Test.

SHA-256 della migrazione 004 applicata:
`447163b1693e39d7238c70a1f58482b8d9a3c18f4b9f3b0ec3c066a84d3beb4a`.

## Build 177 — Lentezza sincronizzazione APK

Contratto: [sincronizzazione compatta](docs/architecture/TODO_SYNC_PERFORMANCE.md).
Diagnostica release sul Galaxy: build 2176, 78.464 ms e 89.253 righe task
scaricate. Build 2177 senza migrazione 003: fallback completo riuscito in
68.420 ms, 89.253 righe e zero intenti finali. Questi dati confermano che il solo
merge locale aggregato non risolve il costo del download integrale.

`make check`: 210 test Flutter, analisi statica, 11 test strumenti, link e SQL
superati. `make check-generated` conferma Drift coerente. Galaxy Validation:
30 test passati, un caso desktop escluso. 20.000 attività sintetiche invariate:
714 ms per controllo compatto, zero download task; inclusi writer offline con
contatore basso, tombstone e recupero di righe locali mancanti. La misura sintetica
non è una misura della latenza del server di produzione.

`make todo-test` ha installato in-place **2.39.2-dev, versionCode 2177**.
Migrazione 003 applicata in produzione dopo consenso specifico dell'utente:
EXECUTE autenticati true, anon false. Il nuovo ciclo reale 2 della build 2177,
concluso alle **14:56:01 UTC**, dura **3.115 ms**, zero task riscaricate, zero
intenti finali e Realtime subscribed. Prima della migrazione lo stesso APK aveva
impiegato 68.420 ms: circa il 95% di tempo in meno in queste due osservazioni.
Non sono stati letti contenuti personali.
[CI Verify](https://github.com/gpmerola/deterministic-todo/actions/runs/34613426398)
e [pubblicazione Todo Test](https://github.com/gpmerola/deterministic-todo/actions/runs/34613422421)
superate. Manifest rolling pubblico verificato: 2.39.2, build 177, dev, sorgente
`b9c8346b4f9a10bc3126eb7a6d4f13a574459a87`. SHA-256 arm64 corrispondente al digest
GitHub: `d31d312a97b9445b5ad982ffa5292a1bc5eafc43eb326782116a9c54d636a4dd`.
Web/Play stabili restano alla 2.38.0+174; questa correzione è distribuita su Todo Test.

Build Web release e fixture compilate; avvio HTTPS con CA esplicita (200).
Chrome su origine localhost isolata: attività e link sincronizzati, conservati
anche dopo refresh con server sintetico spento. UI provata su HTTP localhost,
contesto sicuro; nessun avviso certificato aggirato.

SHA-256 migrazione compatta 003 applicata:
`f273fc3474c226447f40f6eaa8b6a7d0526db3260b0292cad1d2aeaed6f541b0`.

## Build 175 — Backup, richieste e outbox

Contratto: [backup e lifecycle](docs/architecture/TODO_BACKUP_AND_LIFECYCLE.md).
`make check` superato: 206 test Flutter, analisi statica, 10 test strumenti,
link e SQL. `make check-generated` conferma Drift coerente. Galaxy: 26 test
passati nel package `.dev.validation`; un caso desktop intenzionalmente escluso.
Coperti backup v1/v2, rollback, risposta tardiva, cambio account, abort/timeout
HTTP reale e migrazione SQLite 8→9 preservando la coda.

Prova sintetica outbox: 10.000 ID con circa 20 MB di payload non selezionato,
80 ms sul Galaxy in debug; è una misura di query, non frame/RAM/batteria release.
Web release distribuibile e fixture compilate; avvio HTTPS con certificato
verificato tramite CA locale. Chrome, su origine localhost isolata: anteprima
backup v2, import riuscito, progetto/sezione/task con link conservati dopo refresh.
La UI è stata provata su HTTP localhost (contesto sicuro); HTTPS verificato con
curl e CA esplicita, senza aggirare avvisi del browser.

`make todo-test` ha compilato, verificato e installato in-place **2.39.0-dev,
versionCode 2175**, APK arm64 24,4 MB, alle 15:39:28 Europe/Rome. Il provider Todo
ha registrato un nuovo successo alle **13:40:46 UTC**, stato `healthy`. Il campo storico `last_pending=0` non provava la coda
corrente: il limite diagnostico è corretto nella build 177. Il precedente errore di rete delle 13:22:58
è storico; il dispositivo ha quindi recuperato anche con la nuova build.
[CI Verify](https://github.com/gpmerola/deterministic-todo/actions/runs/34606014681)
e [pubblicazione Todo Test](https://github.com/gpmerola/deterministic-todo/actions/runs/34606010268)
verdi. Manifest rolling pubblico: 2.39.0, build 175, canale dev, sorgente
`dde96360f2aa391a6e1cc0c029cda3948de236b5`; hash arm64 corrispondente al digest
dell'asset GitHub. Web/Play stabili restano alla release della sezione successiva;
la build 175 è distribuita sul canale Todo Test.

Diagnostica sicura Todo della 174, letta prima dell'update: `healthy`, nuovo
successo alle 13:18:59 UTC dell'11 settembre. Il conteggio pendente esposto
era storico, non una misura della coda corrente. Il precedente
errore di rete delle 12:55:34 è quindi superato dopo la migrazione server.
`last_realtime_problem` conserva un incidente storico delle 12:41:12; non è una
misura dello stato attuale del canale. Nessun contenuto Todo o Movimento letto.

## Build 174 — Todo UX e sincronizzazione

Contratto: [Todo UX hardening](docs/architecture/TODO_UX_HARDENING.md).
`make check` superato: 193 test Flutter, analisi statica senza segnalazioni,
10 test strumenti, link documentali e migrazioni PostgreSQL PGlite con RLS,
rollback e protezione di task/progetti/sezioni eliminati. `make check-generated`
conferma Drift invariato. I benchmark locali su 100/1.000/10.000 task sintetiche
materializzano dieci righe: circa 11,3 ms a freddo e 1 ms nelle prove successive;
non sono misure di frame, RAM o batteria del Galaxy.

Convergenza browser–Galaxy verificata su trasporto HTTP sintetico locale: creazione
Web, modifica nota e nuova attività Android, ritorno Web. Il test Android riapre
SQLite e conserva i risultati; Chrome conferma nota Android e task creata sul
Galaxy anche dopo refresh. Editor Web: bozza recuperata, pannello chiuso dopo
salvataggio e nuovo URL corretto dopo sostituzione del testo. Build Web release
sintetica servita via HTTPS con CA esplicita (200); UI verificata su localhost
HTTP, contesto sicuro del browser. Non sono stati usati account o contenuti reali.

Suite Galaxy finale: 13 test mobili passati; un caso desktop escluso dal run
hardware e verificato nella suite locale. Il test separato browser–Galaxy con
riapertura SQLite è passato. Build Web distribuibile compilata con configurazione
canonica. `make todo-test` ha verificato e installato in-place **2.38.0-dev,
versionCode 2174**, APK arm64 24,3 MB; processo avviato e versione riletta via ADB.
Il provider tecnico ha registrato nuovi successi cloud dopo l'installazione
(ultimo alle 12:54:06 UTC), poi un errore di rete alle 12:55:34 UTC, con zero
elementi in attesa. Al controllo finale non registra ancora un ciclo successivo
alla migrazione; il recupero Realtime non è dichiarato verificato.
Il package Play non è stato modificato; al controllo finale non è elencato per
l'utente Android 0 (non viene reinstallato o riattivato da questo task).
La simulazione desktop sul telefono produceva overflow per gli inset della
tastiera fisica: il layout desktop è verificato sul computer/browser, il telefono
esegue i casi mobili. Il package `.dev.validation` non registra Movimento.

Migrazioni Supabase `202609110001` e `202609110002` **applicate** l'11 settembre
2026, in una singola transazione autorizzata. Verifica catalogo alle 13:02:57 UTC:
RLS attiva, sei trigger, lettura autenticata e RPC consentite; TRUNCATE client,
lettura anonima, RPC anonime ed esecuzione diretta del guard negati. Nessuna
chiamata di purge né cancellazione di dati durante il deploy. Il test SQL
riproduce i privilegi predefiniti Supabase, incluso TRUNCATE.

Release stabile **2.38.0+174 pubblicata**: Web, APK diretti e track interno Play.
[Pipeline coordinata](https://github.com/gpmerola/deterministic-todo/actions/runs/34600900234)
interamente verde, commit client `750e23e9678f4b2f62c5879bdf1289ce96a8b807`.
Identità pubbliche Web/Android corrispondenti e SHA-256 dei quattro asset del
manifest confrontati con i digest GitHub. Il permesso temporaneo di deploy Pages
per questo branch è stato rimosso dopo il rilascio; nessun merge eseguito.
L'aggiornamento Play sul telefono non è stato collaudato.

SHA-256 delle migrazioni canoniche applicate:

- `202609110001`: `16746f6fb8605e1b166bf51ec6c7372eba4a499a12e3f0c0af93aa0abc46bb71`
- `202609110002`: `77075e62d976e5776c143da4622efff9bf064ee35eb8449d5bda99a269f4570a`

Procedura e recovery: [SAFE_PURGE](docs/operations/SAFE_PURGE.md).
La prova sintetica non dimostra autenticazione/RLS/Realtime né convergenza con
l'account cloud reale. Il registro non ricostruisce UUID eliminati prima della
migrazione; i client vecchi mantengono il vecchio merge finché non aggiornati.

## Build 173 — Diagnostica locale per intervallo

Implementata lettura ADB riservata alla shell su Todo Test, senza raccolte
aggiuntive o upload. Contratto, confini temporali e limiti della ricalcolazione:
[MOVEMENT_AUTONOMY](docs/archive/MOVEMENT_AUTONOMY.md).
Verifiche superate: `make check` (analisi Flutter, 171 test Flutter, 10 test
strumenti e link), 159 test JVM e 5 test strumentali sul Galaxy con database
sintetici. Il lint Android conserva 38 errori/fatali preesistenti, nessuno nei
file modificati; nessuna baseline aggiunta. `make todo-test` ha installato
2.37.2-dev/versionCode 2173 in-place. La query reale ha restituito i minuti
richiesti e rifiuta intervalli mancanti o oltre il limite. Dati personali e
analisi restano privati fuori dal repository. La risoluzione al minuto limita
la valutazione degli stop al secondo: non è dichiarata una calibrazione validata.
Nessuna nuova release stabile promossa; Play resta disabilitata sul Galaxy.

## Build 172 — Sincronizzazione per campo, storico e persistenza Web

Rimosse le scritture automatiche di avvio e il rebase completo delle attività.
Introdotti UPDATE condizionali, outbox con intenti e protezione delle risposte
perse. SQLite 7 conserva revisioni locali per 90 giorni, incluse copie remote
prima dell'invio, conferme e conflitti; consultazione, export e ripristino
esplicito in UI. Contratto e incidente riprodotto:
[sincronizzazione e storico](docs/architecture/TODO_SYNC_AND_HISTORY.md).

`make check` superato: analisi statica, 171 test Flutter, 10 test strumenti e
collegamenti documentali. La prima 171 è stata installata e usata per riprodurre
il difetto aggiuntivo Web: una modifica e relativa revisione sparivano al refresh,
mentre la creazione restava. La 172 aggiunge la barriera di persistenza IndexedDB
documentata nel contratto sopra; nessuna modifica a dipendenze o worker vendorizzati.

`make todo-test` ha compilato, verificato e installato in-place la versione
2.37.1-dev, versionCode 2172 sul Galaxy. Il provider Todo riporta un nuovo
`sync_completed` alle 09:44:30 UTC del 7 settembre, stato `healthy`: avvio,
migrazione e ciclo ordinario verificati. Non sono stati estratti contenuti Todo
o sanitari; Play resta disabilitata. Un precedente timeout Realtime non è stato
scambiato per successo e il controllo è stato ripetuto dopo l'avvio.

Build Web release compilata e servita via HTTPS locale con certificato verificato
tramite CA esplicita. La UI Chrome usa localhost HTTP (contesto sicuro del browser),
con fixture sintetica e Supabase non configurato. La modifica resta dopo refresh
e chiusura/riapertura completa della scheda; lo storico conserva sia la creazione
sia la revisione con il titolo modificato. Il confronto prima/dopo è stato
ispezionato visivamente. Lo schema Drift rigenerato ha hash identico al file
generato incluso.
Pubblicazione coordinata **2.37.1+172** completata il 7 settembre 2026:
[workflow 34130960443](https://github.com/gpmerola/deterministic-todo/actions/runs/34130960443)
interamente verde. Web pubblico e manifest APK `latest` riportano versione,
build e commit `ed3f80a3b507d90a377ff3f5c6b3b446ca58fdef` identici; verificati
i quattro SHA-256 del manifest contro i digest degli asset GitHub (tre ABI e
fallback universale). Google Play ha accettato l'AAB nel track interno; la
propagazione al singolo tester non è verificata. Sul Galaxy resta installata
Todo Test 2172 e Play resta disabilitata. Da completare la convergenza con due
client reali e l'osservazione del prossimo cambio giorno; il collaudo Chrome
sintetico sopra non prova la sincronizzazione con un account cloud.

## Build 170 — Raccolta locale e modello quotidiano

Implementati Recording API locale senza account/app Fit, import periodico
Room 5, classificazione camminata/corsa, integrazione GPS senza somma doppia e
profilo personale peso/passo. Algoritmo, limiti e procedura:
[MOVEMENT_AUTONOMY](docs/archive/MOVEMENT_AUTONOMY.md).

Verifiche: `make check` superato (analisi Flutter, 153 test app, 10 test
strumenti, link documentali), 155 test JVM, quattro test strumentali sul Galaxy
con database sintetici nel package di test. Coperti migrazione 4→5 preservando
sessioni/subtotali, replay idempotente, rollback, riapertura e ancore GPS al
confine del giorno. Lint Android: persistono i 38 errori preesistenti, nessuno
nei file nuovi/modificati; nessuna baseline aggiunta per nasconderli.

`make todo-test` ha verificato e installato in-place la release arm64
2.36.0-dev/versionCode 2170. APK locale 24.190.020 byte. Sul Galaxy la
sottoscrizione è riuscita e `refresh_steps` ha completato un import reale:
`local_recording_api`, `subscribed`, timestamp import aggiornato. Lettura
soltanto di metadati tecnici; nessun passo personale, GPS, peso o battito
estratto. Amazfit resta spento secondo l'utente; Play resta disabilitata e il
confronto diagnostico non è stato avviato.

Un secondo import richiesto via provider ha aggiornato il timestamp anche
con l'interfaccia non aperta. Il tentativo `am kill` non ha terminato il
processo (PID invariato): non è dichiarata superata una prova di ricreazione
del processo. Non è stato eseguito un arresto forzato sul client personale.

Restano da misurare accuratezza, batteria, copertura dopo reboot/revoca permessi
e una prova con Fit disattivato. La raccolta tramite servizio non è una prova
di precisione del sensore. Import al minuto completo e scheduling Android
possono ritardare il totale visibile; nessuna ricostruzione prima dell'attivazione.
Calorie ancora stimate con coefficienti distanza/peso, senza MET per intensità,
pendenza o metabolismo a riposo. La calibrazione per cadenza e la fusione
temporale Amazfit restano successive alla validazione del solo telefono.

## Build 169 — Basi del conteggio Movimento autonomo

Implementazione e riscontri: [MOVEMENT_AUTONOMY](docs/archive/MOVEMENT_AUTONOMY.md).
Correzione conservativa dei subtotali giorno/fuso e della prima lettura dal
boot odierno; stato tecnico ADB esplicito. `make check` superato: analisi
Flutter, 152 test app, 10 test strumenti e collegamenti documentali. Superati
144 test JVM Movimento, inclusi i nuovi casi di regressione.

`make todo-test` ha compilato, verificato e installato in-place la release
arm64 2.35.4-dev, versionCode 2169, aprendo Todo Test con dati preservati.
Il provider sul Galaxy restituisce `one_shot_counter`, `not_established` e
inizialmente `not_observed`: verificata l'esposizione dei campi, non ancora un
nuovo campione sensore o una camminata reale. Il monitor passivo resta spento.
La correzione di cambio fuso/reboot è verificata con fixture automatiche;
non sono stati alterati ora, fuso o stato di Fit sul telefono personale.

Lint Android completo: 38 errori, 61 warning e 2 hint. Gli errori sono in
otto file non modificati rispetto a HEAD, soprattutto permessi BLE/location,
API minime e Fragment; nessun errore nei file modificati. Non introdotta una
baseline che li nasconda. Il lint completo resta un debito da affrontare.

Controllo ADB precedente all'update: Todo Test 168 installata, Play 121 ancora
disabilitata; monitor passivo `enabled=0`, nessun servizio Movimento attivo
nel controllo, ultimo audit `drive_error/drive_audit_failed_IOException`.
L'errore descrive l'ultimo tentativo, non una diagnosi della disponibilità
attuale di Drive. Amazfit spento secondo l'utente. Collegamento riuscito usando
l'endpoint annunciato da mDNS; non sono stati estratti dati sanitari o GPS.

## Build 168 — Scelta esplicita senza data

L’editor conserva la data nulla selezionata con **Senza data** o con la X e
deriva lo stato `inbox`, mantenendo progetto e sezione. La riapertura e una
modifica successiva non reintroducono oggi. La creazione rapida mantiene oggi
come default. Data, stato e outbox sono scritti in una sola transazione.

Analisi statica, 152 test Flutter, 10 test degli strumenti, controllo Drift e
build release Web/Android superati; anche la CI Verify del commit `8b463b5` è
verde. `make todo-test` ha pubblicato l’APK arm64 `.dev` sul manifest rolling:
versionCode 2168, versione/build, commit sorgente e SHA-256 dell’asset coincidono
con la build locale verificata. Sul telefono è disponibile da **Controlla
aggiornamenti**. Il Galaxy non risponde all’endpoint ADB domestico, quindi
installazione e collaudo hardware della 168 restano pendenti.

Il server HTTPS locale risponde correttamente con certificato verificato.
Il collaudo UI Chrome è stato eseguito su localhost HTTP con fixture sintetiche:
il pulsante e la X funzionano durante la sessione, ma dopo refresh sono stati
riletti valori precedenti delle modifiche, anche su un’origine locale nuova.
La persistenza Web dopo refresh resta da isolare sul profilo Chrome locale; la
pipeline release ha comunque superato build Web, deploy Pages, verifica di
`release-info.json` e parità pubblica. La release coordinata **2.35.3+168** è
stata pubblicata su Web, APK diretti e track interno Play il 7 settembre 2026.

## Build 167 — Inbox filtrata e cancellazione definitiva

La versione **2.35.2 build 167** mostra in Impostazioni soltanto le attività
senza data che non appartengono ad alcun progetto e aggiunge **Svuota cestino**.
Con la sincronizzazione configurata, la cancellazione definitiva viene eseguita
prima su Supabase tramite la RPC `purge_trash` e solo dopo in SQLite; un errore
remoto conserva quindi la copia locale. La migrazione Supabase è stata applicata
il 31 agosto 2026 senza cancellare dati durante l'installazione. Il commit release
`0f3562f` è pubblicato sul Web, negli APK diretti e nel test interno Google Play;
le identità pubbliche Web/Android e la pipeline coordinata risultano coerenti.
Todo Test 167 è installata sul Galaxy S21 con dati preservati.

Prima di svuotare definitivamente il cestino occorre sincronizzare eventuali
altri dispositivi rimasti offline, che altrimenti potrebbero riproporre modifiche
obsolete al successivo collegamento.

## Build 166 — Inbox storica

La versione **2.35.1 build 166** espone in Impostazioni le attività attive senza
data, con rimozione singola o collettiva tramite tombstone sincronizzata e
recupero dal Cestino. Il commit release `a0c5e58` è pubblicato sul Web, negli
APK diretti e nel test interno Google Play; la pipeline coordinata e il
controllo pubblico di parità sono verdi. Todo Test 166 è installata sul Galaxy
S21 con dati preservati.

## Build 155 — Movimento autonomo dal riferimento Fit

Il totale visibile usa `TYPE_STEP_COUNTER` e persiste la baseline cumulativa per
boot e giorno civile. I passi Bip U già importati entrano con la regola
conservativa `max(telefono, Amazfit)`, senza sommare sorgenti sovrapposte; i due
valori sono esposti separatamente. Health Connect/Google Fit non alimenta più
l'anello né la card giornaliera e resta esclusivamente gold di confronto. Il
primo avvio dopo l'aggiornamento stabilisce una baseline e non inventa il
pregresso della giornata non ricostruibile localmente.

## Build 159 — importazione Bip U automatica e limitata

Il client BLE di importazione storico è utilizzabile senza Activity: viene
richiamato al massimo ogni 15 minuti mentre l'app è visibile e da un worker
periodico ogni tre ore. Il tentativo è in sola lettura, dura al massimo 90
secondi, richiede batteria non bassa e non usa retry aggressivi. Android può
ritardare il worker; la cadenza è quindi minima e non un allarme esatto.
La build locale intermedia 156 ha verificato sul Galaxy lo scheduling, rilevando
correttamente Bluetooth spento; la 157 distingue questo esito come `skipped`.
Il collaudo reale della 157 ha raggiunto autenticazione e richiesta delle 168
ore ma rilevato una riconsegna di notifica; la 158 accetta soltanto duplicati
byte-identici e continua a rifiutare gap o contenuti discordanti.
La 159 aggiunge esclusivamente il trigger ADB `sync_bip_now`, protetto dal
permesso di sistema `DUMP`, per riprodurre subito lo stesso percorso headless.
Il collaudo reale della 159 è riuscito: autenticazione, richiesta di 168 ore,
4.263 campioni minuto inseriti idempotentemente e 32.912 passi grezzi nella
finestra completa. Il trasferimento è durato circa 18 secondi; GATT è stato
chiuso e il client BLE deregistrato subito dopo.

## Distribuzione

- Canali supportati: Android nativo e browser Chrome/Edge.
- Versione Todo Test preparata: **2.33.2 build 151**. Il flavor Android `dev`
  produce **Todo Test**, installabile e aggiornabile via ADB accanto alla build
  Play. Sul Galaxy S21 Todo Test è l'unico client attivo, con monitor passivo e
  diagnostica intensiva avviati. La build Play 121 è installata ma
  `disabled-user`: dati e baseline esistenti restano conservati. La build 147
  serializza tutte le scritture Drive: il collaudo reale della 146 aveva
  mostrato un diagnostico manuale `.partial` vuoto quando worker manuale,
  periodico e intensivo si sovrapponevano. Il fallback viene cancellato dopo
  un upload diretto verificato. La build 149 sostituisce definitivamente quel
  flusso con un bundle rolling completo di 7 giorni, aggiornato ogni 3 ore o
  manualmente in due slot alternati. Non elimina mai file su Drive.
  La build 131 unifica il recupero manuale dell’ultima sessione: riesporta GPX
  e diagnostica e riprogramma automaticamente il confronto Fit. I retry con
  valori Fit invariati riusano lo stesso sidecar immutabile, mentre un
  aggiornamento reale dei valori crea un nuovo snapshot.
  La build 132 corregge inoltre il confronto OTA del suffisso `-dev`, verifica
  anche la build logica e ricontrolla la versione installata prima di avviare
  il download: il manifest rolling in ritardo non può più proporre downgrade.
  La build 133 evita che il ritorno da un falso riaggancio GPS aggiunga il
  percorso spurio: il primo fix coerente dopo il riaggancio stabilizza soltanto
  il nuovo riferimento ed è registrato come `gps_discontinuity_settling`.
  Inoltre una sessione calibra la falcata soltanto se almeno l'80% dei passi
  osservati in finestre di 30 secondi appartiene alla cadenza attesa; i
  campioni corsa precedenti a questa regola vengono azzerati una sola volta.
  La build 134 aggiunge un report canonico per sessione confrontabile fra Todo
  Test, Google Fit e Bip U, con finestre UTC di un minuto e campioni Bip nativi.
  Si aggiorna dopo Fit, dopo il recupero Bip e ogni ora per le ultime 15
  sessioni. Il recupero Bip usa un'ora di sovrapposizione e fino a sette giorni
  di storico, senza cancellare dati dall'orologio. La diagnostica registra
  anche la distribuzione reale degli intervalli GPS; la richiesta resta a 1 Hz.
  La build 135 aggiunge ai report passivi una timeline Health Connect UTC al
  minuto, rende persistente e remoto lo stato del recupero Bip e registra i
  buchi della diagnostica intensiva anche fra riavvii/segmenti.
  La build 136 aggiunge in Movimento un upload manuale completo e osservabile:
  crea file univoci per snapshot passivo e diagnostica, carica i blocchi
  intensivi pendenti, aggiorna il report unificato e i confronti recenti senza
  avviare GPS o BLE.
  La build 137 aggiunge l'obiettivo passi globale (10.000 predefiniti,
  configurabile), con anello persistente e celebrazione una volta al giorno;
  riduce Movimento a tre schede principali e sposta i controlli rari nei
  dettagli. L'upload completo è richiamabile anche dalla shell ADB protetta.
  La build 138 elimina il passaggio Flutter→Activity dalla navigazione:
  Movimento è una pagina coerente con il resto dell'app e usa un bridge
  sottile per stato live, avvio/stop e upload. Il refresh al secondo è
  confinato alla pagina visibile e non modifica il monitor passivo.
  La build 139 porta il report passivo allo schema 7: timeline Todo/Fit/Bip,
  episodi diagnostici automatici con pause, copertura e ritardo delle sorgenti,
  provenienza/hash del modello e checkpoint risorse. Algoritmo, GPS e cadenza
  degli upload restano invariati, quindi il test in corso continua.
  La build 140 rende crash-safe la scrittura dei report immutabili su Drive,
  recupera i file da 0 byte e registra tentativo corrente/ultimo upload
  concluso. Normalizza CPU e rete, aggiunge il delta PSS e rende esplicita
  l'assenza o obsolescenza dei campioni Bip senza avviare BLE in background.
  La build 141 rende diagnosticabile ogni singola fase del job Drive e tratta
  il refresh dei confronti storici come opzionale, senza ritentare log e
  riepilogo già riusciti. Lo snapshot passivo schema 8 distingue Fit corrente,
  ritardato, obsoleto o mancante e registra avanzamento, delta e arrivi tardivi
  fra osservazioni. Il contatore hardware indipendente continua a essere
  registrato nei segmenti intensivi come `step_counter_delta`; nessun secondo
  monitor permanente è stato aggiunto.
  La build 146 aggiorna il contatore visibile ogni 30 secondi solo in foreground
  e avvia l'export manuale essenziale su un executor dedicato, con fallback
  WorkManager idempotente dopo un minuto. La build 145 confina il drenaggio
  intensivo in un worker dedicato e ritardato
  di due minuti nel percorso manuale: snapshot, log e report non attraversano
  più quella coda e non possono essere bloccati da un chunk o dal provider SAF.
  La build 144 rende idempotente ogni singolo comando manuale anche attraverso
  i retry, espone separatamente la generazione del report unificato e garantisce
  un report schema 6 minimo in caso di errore. Le metriche non finite diventano
  `null` JSON invece di interrompere la serializzazione. La build 143 elimina la
  dipendenza sequenziale del caricamento manuale:
  snapshot passivo e diagnostica generale sono due lavori indipendenti, così
  un retry parziale non blocca log e report unificato. La build 142 gestisce la
  semantica asincrona del provider Drive: se
  `renameDocument` non restituisce un URI o segnala un errore ambiguo, accetta il successo soltanto dopo
  aver verificato nome e dimensione del file finale. Il report unificato schema
  5 conserva le fasi come JSON annidato e registra lo smaltimento della coda
  intensiva. Anche il worker diagnostico orario carica fino a otto chunk per
  ciclo, indipendentemente dalla schermata e dalla scadenza del monitor passivo.
  Drive separa sessioni,
  confronti passivi, diagnostica intensiva, diagnostica app e prove Bip U in
  cinque sottocartelle. Ogni prova Bip U esporta un report privo di MAC e
  chiavi. La connessione usa prima l'orologio già associato ad Android e resta
  in sola lettura. La build 124 è verificata sul Bip U reale: autenticazione,
  7 campioni cardiaci (67–73 bpm, media 70), stop automatico, GATT 0 e report
  Drive schema 2 completati. La build 126 ha inoltre importato dal dispositivo
  reale 1.440 campioni di un minuto con 2.626 passi e 358 valori cardiaci; il
  retry sovrapposto ha inserito soltanto due minuti nuovi. I dati restano
  locali e separati dalla sorgente telefono. La build 127 aggiunge un
  ore un report remoto unificato con stato telefono/Fit, aggregati Bip U a 3 e
  24 ore, freschezza dei campioni, stato intensivo e metadati dei log. Conserva
  gli ultimi 15 report e 15 snapshot JSONL. La diagnostica intensiva
  opzionale osserva per sette giorni GPS e sensori in finestre di cinque
  secondi e carica blocchi JSONL orari su Drive. ID e scadenza sopravvivono
  alle build intermedie, che restano distinguibili per segmento. La build 118
  rende crash-safe la rotazione e garantisce un tentativo finale di upload
  anche quando test intensivo e passivo scadono insieme, senza cambiare
  algoritmo o campionamento. Il test
  passivo Movimento
  crea snapshot cumulativi Todo/Google Fit della giornata corrente all'avvio e
  ogni ora, mantenendo anche il report finale giornaliero. La 2.25.4 build 112
  aggiorna durante il debugging la diagnostica Drive all'apertura; dalla 134 il
  job periodico gira ogni ora invece che ogni tre
  ore con rete disponibile. Dalla 127 usa snapshot immutabili per fascia
  oraria invece di un file giornaliero non aggiornabile. La
  2.25.3 build 111 verifica ogni
  scrittura task sul server prima di riconoscere l'outbox e ribasa
  automaticamente le versioni Lamport remote più alte. La 2.25.2 build 110
  distribuisce ciascun record passi sull'intervallo temporale completo e
  tratta come incerta l'esclusione di trasporto/sosta nei blocchi misti. La
  2.25.1 build 109 estende a sette giorni la finestra del test passivo; la
  2.25.0 build 108 introduce classificazione passiva
  cammino/corsa/trasporto e calibrazione distinta delle falcate. La 2.24.2 build 107 aggiunge export diagnostico Drive
  giornaliero con retention di 15 file. La 2.24.1 build 106 riduce la memoria
  in background e telemetria PSS Android. La 2.24.0 build 105 introduce layout compatto di
  Movimento e confronto Google Fit persistente con timeout/retry → JSON Drive. La base funzionale
  **2.22.3 build 95** ha superato pubblicazione diretta, Google Play interno,
  Web e controllo finale di parità.
- Stato dispositivo distinto dalla release: la versione installata viene
  verificata via ADB dopo ogni consegna Todo Test; la build Play 121 è soltanto
  fallback disabilitato.
- Non usare l'APK GitHub per sostituire la build Play e non disinstallare o
  cancellare i dati di nessuno dei due package. Gli APK `dev` firmati con la
  linea diretta sono invece il canale rapido previsto per Todo Test.
- Il test interno Google Play è attivo. Dalla build 65 la pipeline pubblica automaticamente nel
  test interno; la produzione resta manuale e subordinata al test chiuso.
- Un solo workflow coordina web e Android e rifiuta versioni, build o commit
  discordanti; l'AAB raggiunge il track Play interno appena supera test e build,
  mentre APK diretti e Web continuano in parallelo.
- La stessa pipeline produce APK per gli aggiornamenti diretti e AAB firmato
  per Google Play.

## Dati e sincronizzazione

- Il 17 agosto è stato isolato un difetto delle build fino alla 110: una
  modifica locale incrementava solo la propria versione e `merge_task` poteva
  scartarla se Supabase aveva già un contatore maggiore; il client eliminava
  comunque l'outbox e il pull ripristinava lo stato remoto. La build 111 usa il
  massimo osservato, verifica la riga server e conserva l'outbox in caso di
  mancata conferma. Le modifiche già sovrascritte richiedono recupero separato
  o reinserimento manuale: il fix impedisce nuove perdite ma non inventa stati
  non più presenti in SQLite o Supabase.

- SQLite Drift è la fonte locale immediata; Supabase con RLS è la replica
  personale facoltativa.
- Le scritture locali entrano in una outbox persistente e vengono inviate
  subito. Le ricevute remote sono immutabili e i retry usano inserimenti
  idempotenti senza richiedere permessi di aggiornamento.
- Supabase Realtime notifica Android e browser; dalla 2.16.0 vengono richiesti
  soltanto gli ID cambiati. Il canale si riapre dopo errori o timeout; un
  controllo completo ogni dieci minuti recupera eventi persi, riprese e periodi
  offline mentre l'app è visibile. Quando l'app passa in background il canale
  viene rimosso per liberare socket e memoria; al resume viene ricreato prima
  del pull di recupero.
- Task, progetti, sezioni, priorità, date civili, ricorrenze e tombstone sono
  sincronizzati. Il tipo `reference` della 2.18.0 resta leggibile come normale
  task per non perdere dati. Non si sincronizzano segreti o contenuti dei log.
- Le occorrenze ricorrenti hanno ID deterministici condivisi tra dispositivi;
  il client riconcilia anche le collisioni storiche `23505` scegliendo la
  versione Lamport più recente.

## Esperienza corrente

- Oggi, Prossime, Progetti, ricerca e composer condividono lo stesso modello su
  Android e web, con layout desktop adattivo. Progetti è l'unico sistema di
  organizzazione persistente esposto nell'interfaccia.
- `Ctrl/⌘ K` apre il comando universale: testo libero cerca, `+` crea, `>`
  naviga e `#` limita la ricerca a un progetto. Sul desktop una task selezionata
  si modifica direttamente nel pannello laterale opzionale.
- Il composer riconosce linguaggio naturale, `#Progetto`, `p1`–`p4` e link;
  ricorda il progetto recente, parte sempre senza priorità e resta fermo durante
  gli assestamenti della tastiera Android.
- Nel campo titolo Invio fisico conferma sia la creazione sia la modifica in
  ogni sezione; la descrizione conserva il comportamento multilinea.
- Le scorciatoie globali richiedono Ctrl/⌘: caratteri come `n` e `/` restano
  testo normale quando un editor è attivo.
- La spunta è separata dallo swipe: completamento e avanzamento della ricorrenza
  non possono più avviare per errore il trascinamento verso il cestino. La riga
  resta ferma durante la conferma e viene rimossa solo dopo la dissolvenza.
- L'Undo usa un solo comportamento per task, progetti e sezioni e, sulle
  ricorrenze, inverte atomicamente anche la nuova occorrenza.
- L'import Todoist supporta aggiornamento e sostituzione idempotente di task,
  progetti e sezioni e produce un rapporto prima del backup.
- Impostazioni contiene Cestino, attività completate, diagnostica e Salute dati;
  gli stati sani restano fuori dall'interfaccia principale.
- Su Android, Movimento è una quarta destinazione principale accanto a
  Progetti. Camminata è l'azione primaria; Drive, export manuali e BLE sono
  raccolti negli strumenti avanzati.
- Android contiene il modulo separato `runtracker`: registra corse usando il
  GPS del telefono in foreground, salva campioni e scarti in Room ed esporta
  GPX. La prima prova BLE è limitata a scansione, connessione e batteria.
- Il modulo legge il totale passi aggregato da Health Connect e
  conserva distanza e calorie attive stimate in Room. Activity Recognition
  distingue cammino, corsa e trasporto senza GPS permanente; falcate separate
  vengono calibrate dopo tre sessioni valide per tipo. Peso personale e
  attribuzione precisa attraverso mezzanotte/reboot restano da completare. Le sessioni leggono inoltre il
  contatore hardware Android e possono confrontare l'ultima attività con i
  dati attribuiti a Google Fit in Health Connect. Camminata e corsa sono
  sessioni distinte; la camminata applica un limite anti-salto GPS dedicato di
  6 m/s e non accumula fix privi di nuovi passi quando il sensore è attivo.
  I GPX reali verificati non contengono battito, cadenza o dati del Bip U;
  l'integrazione Amazfit resta una fase successiva in sola lettura. Il quadro è in
  [docs/HANDOFF.md](docs/HANDOFF.md).

## Verifica

- Le pull request eseguono il percorso canonico `make check-generated` e
  `make check` tramite GitHub Actions; gli stessi comandi sono usati in locale.
- I blocchi JSONL della diagnostica intensiva possono essere validati e
  aggregati offline, senza ADB, con
  `tools/analyze_movement_intensive.py`; il report separa integrità, copertura,
  movimento, risorse e batteria e non modifica gli input Drive.
- Analisi statica senza errori.
- 126 test Flutter superati, incluso uno scenario di convergenza con due
  database indipendenti che rappresentano Android e Web.
- I test JVM coprono filtro GPS, gate passi, timeline, reset/duplicati del
  contatore e stime. Build Android, firma, manifest pubblico e parità con Web
  sono verificati dalla pipeline coordinata.
- La build 98 ha confermato il gate durante due soste: 0 m nella prima e circa
  1,5 m nella seconda. Ha inoltre isolato il blocco del confronto automatico:
  Health Connect richiede il consenso separato per le letture in background.
  La build 99 dichiara e richiede tale consenso, ma sul Galaxy S21 non ha
  riprogrammato né riesportato la sessione 14. La build 100 ha aggiunto il
  recupero in primo piano, ma lo stato persistito era `scheduled`, non
  `permission_required`. La build 101 recupera qualunque stato non concluso. Il
  controllo ADB ha poi confermato permessi corretti e due job conclusi senza
  aggiornamento Drive: la build 102 conserva il codice di errore, riesporta
  ogni tentativo e non lascia più il fallback riuscito su `scheduled`. Il test
  reale della 102 non ha avviato il recupero perché il gate leggeva lo stato
  globale di una sessione precedente; la 103 usa lo stato della sessione più recente
  e ha completato il confronto della sessione 14. Il provider Drive ha però
  conservato il vecchio file nonostante l'esito locale positivo; la 104 forza
  troncamento e sincronizzazione e verifica la dimensione scritta. Anche la
  104 non ha aggiornato il file remoto: la 105 usa quindi sidecar immutabili,
  lo stesso modello create-only affidabile degli export iniziali.
- La 105 introduce inoltre un audit passivo, esteso a sette giorni dalla build
  109. Dalla build 113 WorkManager legge la giornata corrente ogni ora e crea
  snapshot intragiornalieri, oltre al report definitivo del giorno precedente,
  senza GPS o servizio permanente.
- Gli audit reali del 13–15 agosto sulla build 109 hanno mostrato totali passi
  coerenti con Health Connect ma il 61% classificato come escluso: distanza
  Todo 9,51 km contro 21,26 km Google Fit (-55,3%). La causa era l'assegnazione
  integrale dei record passi allo stato del loro punto centrale. La build 110
  usa invece sovrapposizione temporale e un gate conservativo dell'80%.
- La build 114 aggiunge un provider diagnostico aggregato, read-only e protetto
  da `android.permission.DUMP`, così l'ultimo snapshot può essere verificato
  via ADB anche con APK release e Drive non visibile al connettore Codex.
- La build 115 fa prevalere i passi reali su uno stato `STILL` obsoleto,
  mantenendoli come incerti; soltanto veicolo e bicicletta dominanti restano
  esclusi. Lo schema 4 separa le tre cause e aggiunge la baseline all-steps.
- Il Galaxy S21 usa attualmente la firma gestita da Google Play: l'APK diretto
  GitHub, firmato con la chiave di upload/release del repository, viene
  correttamente rifiutato come aggiornamento incompatibile. Non disinstallare
  l'app per cambiare canale; su questo dispositivo usare Play interno.
- ADB remoto è stato verificato con Wi-Fi del telefono disattivato tramite una
  rete privata Tailscale e porta TCP 5555. Endpoint e identificatori runtime
  restano configurazione locale e non sono salvati nel repository; dopo un
  riavvio può servire riattivare `adb tcpip 5555`.
- Restano da collaudare sulla build 118 la continuità dell'esperimento avviato
  sulla 117, l'upload orario e quello finale della
  diagnostica intensiva e almeno due giornate
  principalmente di cammino/corsa, lo schema 7 dei report Drive e la
  calibrazione dopo tre sessioni valide per tipo; resta inoltre il BLE reale
  con Bip U. I test brevi hanno già validato passi, Drive e confronto Health
  Connect.
- Restano manuali il collaudo sul Galaxy S21, Google Calendar e il passaggio
  definitivo dall'ultimo export Todoist; vedi [TODO_NEXT.md](TODO_NEXT.md).

Architettura: [docs/ARCHITETTURA.md](docs/ARCHITETTURA.md). Procedure:
[docs/operations/](docs/operations/). Cronologia: [CHANGELOG.md](CHANGELOG.md).
