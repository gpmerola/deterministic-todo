# Stato corrente

Aggiornato l’11 settembre 2026.

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
[MOVEMENT_AUTONOMY](docs/architecture/MOVEMENT_AUTONOMY.md).
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
[MOVEMENT_AUTONOMY](docs/architecture/MOVEMENT_AUTONOMY.md).

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

Implementazione e riscontri: [MOVEMENT_AUTONOMY](docs/architecture/MOVEMENT_AUTONOMY.md).
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
