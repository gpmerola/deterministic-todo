# Stato corrente

Aggiornato il 25 ottobre 2026. Solo esiti validi oggi; la cronologia delle
versioni è in [CHANGELOG](CHANGELOG.md), gli esiti più vecchi negli archivi in
fondo.

- Stabile: 2.121.2 / 311 (Web, APK diretti, Play interno). Todo Test: 2313
  (branch `agent/semble-fallback`): Semble senza chiave.
- 30 ottobre 2026: Semble rifiuta la chiave API in uso (verificato da
  Impostazioni → Semble su Todo Test). In attesa di una chiave nuova; dalla
  build 313 senza API le visite vengono dal calendario Google «Semble»
  (script Apps Script, ogni 30 minuti) o dal link iCal, le disponibilità
  dall'ultima lettura.
- Galaxy S21: Todo Test (`.dev`) è il solo client operativo; la build Play
  121 resta installata ma `disabled-user`.
- Voci aperte e collaudi con l'utente: [TODO_NEXT](TODO_NEXT.md).

## Release stabile 2.121.2 / 311 — 25 ottobre 2026

Pubblicazione autorizzata con `PUBBLICA` (messaggio dell'utente delle 17:08
UTC). `main` avanzato in fast-forward, senza riscritture, al commit
`29c580c33ff3f789b6d61a845d63b304badd060b` di
`agent/storage-calendar-hardening` (build 309–311). Run coordinato
[40215087202](https://github.com/gpmerola/deterministic-todo/actions/runs/40215087202)
verde in tutti gli otto job.

- [Web](https://gpmerola.github.io/deterministic-todo/): `release-info.json`
  2.121.2 / 311 con lo stesso commit. Profilo Chrome usa e getta, rete
  limitata al sito e a CanvasKit: completa → Annulla → completa di nuovo
  lascia una sola occorrenza il giorno dopo.
- [APK diretti](https://github.com/gpmerola/deterministic-todo-releases/releases/tag/v2.121.2):
  `v2.121.2` `latest`, non prerelease; manifest con quattro APK e SHA-256
  identici ai digest degli asset.
- Google Play: `publish-google-play` riuscito (track `internal`);
  propagazione non verificata.
- Galaxy: Todo Test 2311 già installata; nessun APK dell'updater presente,
  nessun nuovo tentativo del Calendario, spazio libero 142.795.240 KB.

## Build 311 — nessun doppione dal Cestino dopo Annulla (25 ottobre 2026)

`watchTrash` esclude un'occorrenza aperta cancellata quando la serie ha
un'altra occorrenza aperta (la copia lasciata dall'Annulla); `restore`
rifiuta lo stesso caso con un messaggio. Test in `test/database_test.dart`,
che fallisce senza la correzione. `make check-generated` e `make check`
verdi (618 test, 3 saltati). `make todo-test`: Todo Test 2.121.2 / 2311 via
ADB USB, dati conservati, sync con build 2311, Realtime `subscribed`, coda
vuota, nessun nuovo tentativo del Calendario. Suite
`integration_test/todo_validation_test.dart` sul Galaxy: 40 passati, 1
saltato, nessun overflow (un primo avvio si era interrotto per una
connessione del tool di test persa, senza crash dell'app). Indietro
predittivo verificato in sola lettura su Todo Test: dettaglio evento e foglio
Backup del Calendario si chiudono restando nel Calendario. Nessuna release
stabile.

## Build 309–310 — spazio, Calendario in background, manifest (25 ottobre 2026)

Analisi ADB in sola lettura: Todo Test occupava 1,46 GB di dati con un APK da
24 MB. Causa confermata sul Galaxy: l'updater conservava ogni APK scaricato.
La pulizia (`DownloadedApkCleanup`) ha cancellato 1.416.241.004 byte al primo
avvio della 309 e altri 68.149.090 byte di APK con il nome di agosto nella
310: totale 1.484.390.094 byte, nessun APK rimasto. Spazio libero del
telefono da 141.111.176 KB a 142.828.440 KB (`dumpsys diskstats`; il valore
per app è in cache e si aggiorna una volta al giorno).

Calendario in background: il 25 ottobre il contatore dei fallimenti era a 2
con nuovo tentativo a 8 minuti e tre job avviati nello stesso istante.
Ipotesi corretta nella 309: `AgendaMirror.upload()` rispondeva `false` se un
altro invio era in corso. Ora aspetta e ripete; i job con la stessa impronta
del calendario si uniscono (`agenda_bg_joined_runs` già a 1 dopo
l'installazione) e i motivi dei nuovi tentativi sono registrati senza
contenuti. Primo controllo dopo la 310: nessun nuovo tentativo, contatore a 0.
Voce di osservazione in [TODO_NEXT](TODO_NEXT.md).

Manifest: tolti `INSTALL_PACKAGES`, `WRITE_EXTERNAL_STORAGE`,
`ACCESS_WIFI_STATE`. Indietro predittivo attivo: sequenza a freddo (composer,
editor, Esc, schede, Impostazioni, uscita dalla radice) identica con e senza,
due giri ciascuna, sul pacchetto di validazione. Non provati con questo
confronto: editor eventi e foglio backup del Calendario (assenti nel
pacchetto di validazione).

`make check-generated` e `make check` verdi (617 test, 3 saltati); test JVM
`DownloadedApkCleanupTest` e `AgendaBackgroundTest` verdi. `make todo-test`:
Todo Test 2.121.1 / 2310 installata via ADB USB, dati conservati, sync con
build 2310, Realtime `subscribed`, coda vuota, logcat senza errori. Nessuna
release stabile.

## Release stabile 2.120.1 / 308 — 25 ottobre 2026

Pubblicazione autorizzata con `PUBBLICA` (messaggio dell'utente delle 15:36
UTC). `main` avanzato in fast-forward, senza riscritture, al commit
`2d495ad8c4f075f60317809496d6c8d908bf4af7` di `agent/lighter-docs-device-test`
(contiene tutta `agent/semble-availability`, PR #6). Run coordinato
[40207768802](https://github.com/gpmerola/deterministic-todo/actions/runs/40207768802)
verde in tutti gli otto job.

- [Web](https://gpmerola.github.io/deterministic-todo/): `release-info.json`
  2.120.1 / 308 con lo stesso commit. Profilo Chrome usa e getta, rete
  limitata al sito e a CanvasKit, attività sintetica: completa → Annulla →
  completa di nuovo lascia una sola occorrenza il giorno dopo in Prossime.
- [APK diretti](https://github.com/gpmerola/deterministic-todo-releases/releases/tag/v2.120.1):
  `v2.120.1` `latest`, non prerelease; manifest con quattro APK e SHA-256
  identici ai digest degli asset.
- Google Play: `publish-google-play` riuscito (track `internal`);
  propagazione non verificata.
- Galaxy: Todo Test 2308 già installata via ADB USB.

## Build 308 — ricorrenti dopo Annulla e collaudo del 25 ottobre

Difetto trovato nel collaudo sul Galaxy (pacchetto `.dev.validation`, dati
sintetici): completa → Annulla → completa di nuovo lasciava la prossima
occorrenza come tombstone, perché `_insertOccurrence` usa `insertOrIgnore`
sull'ID deterministico. Ora un tombstone con quella chiave viene ripristinato
con patch Lamport; test in `test/database_test.dart`.
Verificata anche sul Galaxy nel pacchetto di validazione ricompilato.
`make check-generated` e `make check` verdi (614 test, 3 saltati). `make
todo-test`: Todo Test 2.120.1 / 2308 installata via ADB USB, dati
conservati, primo ciclo sync riuscito con build 2308, Realtime `subscribed`,
coda vuota. Nessuna release stabile.

Collaudo dello stesso giorno: suite `integration_test/todo_validation_test.dart`
sul Galaxy 40 passati, 1 saltato (prima della correzione del test falliva per
la tastiera reale su vista finta 400×800). Todo Test 2307 in sola lettura:
avvio a freddo 199–408 ms e a caldo 69–73 ms (`am start -W`), Oggi, Prossime,
Progetti, Calendario 3 giorni/Settimana/2 e 4 settimane, ricerca,
Impostazioni e ritorno da background senza eccezioni né overflow in logcat;
sync `healthy`, Realtime `subscribed`, coda vuota. Non provati per non
modificare impostazioni di sistema: rotazione, testo grande, modalità aereo.

## Build 307 — inviti senza risposta e bordo ambra per singolo evento (in collaudo)

Il 4 novembre un invito Teams non accettato in una disponibilità
straordinaria 10:00–16:45 non aveva bordo: `sembleOverlaps` usava
`agendaBusyMinutes`, che esclude `unanswered`. Ora
`agendaBusyMinutes(unanswered: true)` per bordo e notifica; le fasce libere
restano come prima. Eccezioni a mano: `sembleOverlapKey` (instanceId|inizio)
→ fine, in `SembleSettings.ignoredOverlaps` (Keystore, scadono a fine
evento), lette da `SembleLayer` e da `SembleConflicts`. Voci nel menu ⋯
della scheda. ADB dal Mac ancora irraggiungibile (porta 5555 rifiutata).

## Build 306 — notifica verso il blocco, intestazione e Impostazioni (in collaudo)

La notifica dei conflitti mette nell'intent solo l'inizio del primo evento e
se è unico (`CalendarLaunchRequest`, extra `semble_event_start`/`_single`);
`consumeLaunch` restituisce false, true o `{start, single}` e
`AgendaView.launch` apre la scheda dell'evento (dopo `SembleLayer.refresh`,
così «Blocca in Semble» c'è) o il giorno. Intestazione senza Oggi né
contatore; Impostazioni in sezioni. Refactoring: viste Mese/Elenco/3
settimane e `agenda_list_widgets.dart` eliminati, `AgendaViewMode.parse`,
loader senza giorni, `semble_service.dart` diviso (barrel), `semble_time.dart`,
`AgendaEntry.copyWith`, `NotificationLedger.java`. Da provare sul Galaxy.

## Build 305 — controllo Semble anche all'uscita dall'app (collaudata: la notifica arriva)

L'utente ha creato «Test» e non ha avuto notifica: probabilmente creato in
Todo in primo piano, dove il controllo salta, e nessun altro trigger era
seguito. Ora `didChangeAppLifecycleState` lancia `SembleConflicts.check()`
alla prima transizione in background (insieme allo snapshot). ADB non
raggiungibile al momento: diagnosi sul telefono non fatta.

## Build 304 — notifica per eventi in orario Semble

`SembleConflicts.check` gira con il refresh dei promemoria (trigger del
provider calendario e job giornaliero di `AgendaReminderJob`), headless o
nell'engine dell'app se non è in primo piano. Regole dalla cache
`SembleSettings.saveRules` (Keystore, scritta a ogni lettura riuscita),
`sembleConflicts` sui prossimi 14 giorni, `notifySembleConflicts` →
`AgendaSembleConflicts.java` (canale `calendar_semble_conflicts`, registro
di hash con scadenza). Limite: richiede i promemoria del Calendario attivi.
Da provare sul Galaxy creando un evento in una fascia da un'altra app.

## Build 303 — proposta di blocco alla creazione, visite annullate

Dopo `create()` un evento con `_canSembleBlock` mostra lo snackbar
`agenda-offer-semble-block` con l'azione che chiama
`perform(sembleBlock)`. `sembleAdjustEntries(now:)` aggiunge le prenotazioni
cancellate non ancora finite come `sembleCancelledPrefix` («Annullata ·
tipo»), escluse da occupato, gruppi e conflitti. Prossimo passo richiesto:
notifica per gli eventi arrivati in background in orario prenotabile.

## Build 302 — bordo ambra solo sugli eventi non finiti

`sembleOverlaps(now:)`: `SembleLayer.overlapsFor` esclude gli eventi già
finiti. Da provare sul Galaxy.

## Build 301 — blocco dagli eventi ambra, niente barretta

Pulsante «Blocca in Semble» nella scheda degli eventi ambra (intero
orario dell'evento) e rimozione di `AgendaSembleStrip` dalle griglie. Da
provare sul Galaxy.

## Build 300 — ritocchi Semble (pubblicata su Todo Test)

Richieste dell'utente del 23 ottobre: tocco sui gruppi nelle griglie apre
il giorno (`CalendarVisitGroup.onTap`); blocco sempre `other` senza
`comment`; snackbar con `persist: false`; `SembleLayer.overlapsFor` /
`sembleOverlaps` per il bordo ambra sugli eventi non visite in orario
prenotabile; `SemblePalette` verde per visite (colore del calendario
Semble), disponibilità e indisponibilità. Da provare sul Galaxy; il primo
blocco reale conferma che Semble accetta l'assenza di commento.

## Build 299 — Calendario più semplice (pubblicata su Todo Test)

Su richiesta dell'utente: viste ridotte a 4 settimane, 2 settimane,
Settimana, 3 giorni (migrazione una tantum alla chiave v4), Assistente nel
menu Altro, azioni secondarie della scheda evento sotto «⋯», campi
secondari del nuovo evento sotto «Altre opzioni». Dettagli in
`docs/architecture/AGENDA.md`. Da provare sul Galaxy.

## Build 298 — blocco Semble più semplice (pubblicata su Todo Test)

L'utente non trovava l'icona della build 297. Il nuovo evento ha un
`SegmentedButton` «Evento | Blocco Semble»; in modalità blocco il modulo
mostra solo giorno, orari e tipi (4 rapidi più «Altri tipi») e «Blocca»
chiama `createSembleBlock` direttamente (la scheda di conferma è stata
tolta: il tocco su «Blocca» è la conferma esplicita). Errori Semble
mostrati nel modulo. Da provare sul Galaxy.

## Build 297 — blocchi Semble dal Calendario

Richiesta dell'utente del 23 ottobre 2026 («un metodo veloce e comodo per
aggiungere indisponibilità su Semble»). `SembleClient.createUnavailability`
e `deleteUnavailability` (solo l'id appena creato, per «Annulla»); scheda
`showSembleBlockSheet` aperta dall'icona del nuovo evento quando
`SembleLayer.canBlock`; ID stanza in Impostazioni. Test con fusi UTC, Londra
e Roma; da provare sul Galaxy.
## Prova di scrittura Semble — 23 ottobre 2026

Su richiesta esplicita dell'utente, dal Mac: una sola indisponibilità di
prova (23/10/2026, 23:00–23:15 ora di Londra, tipo `other`, commento di test,
stanza `6a5116a7c2ac13bafdfe9cf1`) creata con `createAvailability`, riletta
con `availabilityRule` e cancellata con `deleteAvailability`; la rilettura
finale risponde «not found». Prima verificato che nessuna regola né
prenotazione occupasse la fascia. La chiave **può scrivere** disponibilità.
Per un solo giorno senza ricorrenza `endDate` va omesso (altrimenti l'API
rifiuta). `createdAt` è un vero UTC, mentre `start`/`end` delle prenotazioni
sono ora di Londra con `Z`. L'app non scrive verso Semble.
## Build 296 — Semble in ora legale, solare e in Italia

Cifre dell'API lette come Europe/London (`londonWallClock`, regole BST) e
convertite nel fuso del telefono; disponibilità spostate con
`sembleZoneShift`. Test superati con `TZ` UTC, Europe/London ed Europe/Rome,
compresi i giorni del cambio d'ora del 25 ottobre 2026 e del 28 marzo 2027.

## Build 295 — orari API come ora di Londra

Lo screenshot di Semble dell'utente del 23 ottobre 2026 (visite alle 10:00,
10:30, 11:00, linea dell'ora alle 11:3x BST) e l'API (`10:00:00.000Z`, …)
mostrano che la `Z` dell'API è l'ora di Londra: le build 291–294 erano
sbagliate e il calendario iCal era giusto. Tolto lo spostamento, cifre lette
come ora locale; durata delle visite dal titolo (pausa di 15 minuti esclusa).
Test superati su Linux anche con `TZ=Europe/London`; da provare sul Galaxy.

## Build 294 — spostamento per giornata

Il 23 ottobre 2026 l'utente ha segnalato visite non coincidenti con Semble:
con prenotazioni alle 11:00, 11:30 e 12:00 le copie iCal (10:00, 10:30, 11:00)
cadevano su un'altra prenotazione e il controllo per singola visita le
lasciava ferme. Ora si decide per giornata (test con la giornata reale, solo
orari). Da provare sul Galaxy.

## Build 293 — stima dalle prenotazioni Semble

La Stima lavoro privato usa le prenotazioni del mese come fonte delle visite
Semble (`estimateWithSembleBookings`). Classificatore verificato sui tipi
reali in inglese («Follow-up Consultation (15 min)», «Initial Consultation
(Adult) (60 min)», «… - 30 min (PLE)», «… - Insurance»). Test superati su
Linux anche con `TZ=Europe/London`; da confrontare sul Galaxy con Semble.

## Build 292 — visite iCal Semble riportate all'ora giusta

Lettura dal Mac del 22 ottobre 2026 (solo orari e tipo di visita): le
prenotazioni API sono corrette in UTC con `Z`, mentre le copie iCal nel
calendario del telefono sono un'ora prima in BST. Nelle build 289–291 le copie
dirette (titoli in inglese) erano all'ora giusta e quelle iCal (titoli in
italiano) no. Ora l'Agenda sposta solo in visualizzazione le visite del
calendario Semble che coincidono con una prenotazione spostata dello scarto
UTC. Test superati su Linux anche con `TZ=Europe/London`; da provare sul
Galaxy.

## Build 291 — orari Semble in UTC

Lo screenshot dell'utente del 22 ottobre 2026 mostrava le copie dirette
un'ora prima delle visite iCal: Semble manda `start`/`end` in UTC senza `Z`.
Ora un orario senza fuso è letto come UTC. Test superati su Linux; da
provare sul Galaxy.

## Build 290 — niente doppioni Semble

Nella 289 le prenotazioni dirette comparivano accanto alla copia iCal
(segnalato dall'utente il 22 ottobre 2026). Ora le nasconde qualsiasi
evento con orario nello stesso minuto. Test superati su Linux; da provare
sul Galaxy.

## Build 289 — prenotazioni Semble dirette nel Calendario

Le prenotazioni con il proprio cognome da ieri a 4 settimane compaiono nel
Calendario dall'API e spariscono quando la copia iCal inizia nello stesso
minuto. `flutter analyze` e `flutter test` superati su Linux; da provare sul
Galaxy dopo aver scritto il cognome in Impostazioni → Semble.

## Build 288 — DNA e cancellazioni da Semble nella stima

Esplorazione dell'API Semble dal Mac il 22 ottobre 2026, con chiave in
`~/.semble_api_key` e risultati solo in `temp/semble_api/` (ignorata da git):
query `bookings` per intervallo di date senza filtro per medico; `doctor`
vietato (`settingsSeeUsers`), `doctorName` leggibile; nessuno stato di
presenza, ma `bookingJourney` con `arrived`, `consultation`, `departed`,
`dna` (date ISO in UTC); la chiave può leggere anche i pazienti collegati,
che l'app non seleziona mai. Prova di scrittura innocua:
`deleteAvailability` con ID tutto zeri ha risposto «not found», non
FORBIDDEN, quindi la chiave va considerata capace di scrivere disponibilità.
`flutter analyze` e `flutter test` superati su Linux; da provare sul Galaxy.

## Build 287 — verde Semble solo sugli spazi liberi

Le fasce e la barretta Semble escludono il tempo già occupato da eventi con
orario. `flutter analyze` e `flutter test` superati su Linux; da provare sul
Galaxy.

## Build 286 — barretta Semble in 4 settimane e Mese

Barretta di disponibilità sotto la data nelle griglie 4 settimane e Mese.
`flutter analyze` e `flutter test` superati su Linux; da provare sul Galaxy.

## Build 285 — disponibilità Semble nel Calendario

Livello di sola lettura con le regole di disponibilità Semble nelle viste
Giorno, 3 giorni e Settimana; chiave in Impostazioni → Semble
([contratto](docs/architecture/AGENDA.md)).

- `flutter analyze` e `flutter test` superati in un ambiente Linux con
  Flutter 3.47.7 (test golden saltati come in CI).
- Non ancora verificato con la chiave reale: forma effettiva di `startDate`,
  `exclusions` e `daysOfTheWeek` nel tenant; il parser accetta date ISO e
  ripete la lettura senza `exclusions` se lo schema la rifiuta.
- Galaxy, 22 ottobre 2026: chiave e User ID salvati, 34 regole lette (15
  ottobre – 22 gennaio); in vista Settimana giovedì 22 verde 10–18 con la
  fascia bloccata delle 14, come in Semble.

## Build 284 — istruzioni diagnostiche agnostiche

Il dialogo prestazioni propone «un assistente AI a tua scelta». Prompt copiato,
esportazione manuale e provider dell'assistente integrato restano invariati.

- `make check`: analisi statica, strumenti, SQL e 571 test Flutter superati
  (3 test saltati).
- `make check-generated`: superato, nessuna differenza nel database generato.
- `make build-web`: build release locale riuscita; nessuna pubblicazione Web.
- `make todo-test`: APK firmato verificato, installato in-place e avviato sul
  Galaxy S21. Verifica successiva del package: `2.103.1-dev`, `versionCode 2284`;
  dati conservati. Il dialogo diagnostico non è stato ispezionato sul telefono.
- Nessuna nuova pubblicazione stabile Web/Play autorizzata da questa modifica.

## Release stabile 2.109.0 / 296 — 23 ottobre 2026

Pubblicazione autorizzata con `PUBBLICA` e scelta "B" (merge in `main`) dei
messaggi dell'utente delle 11:12 e 12:49 UTC. `main` avanzato in fast-forward,
senza riscritture, al commit `2a22ff74a2435763feccea54fafe71446457667b`
(`agent/semble-availability`). Un primo run dal branch
([39949008302](https://github.com/gpmerola/deterministic-todo/actions/runs/39949008302))
è stato annullato in `verify`, senza pubblicare nulla: `github-pages` non
ammette quel branch. Run coordinato da `main`
[39956436806](https://github.com/gpmerola/deterministic-todo/actions/runs/39956436806)
verde in tutti gli otto job.

- [Web](https://gpmerola.github.io/deterministic-todo/): `release-info.json`
  2.109.0 / 296 con lo stesso commit.
- [APK diretti](https://github.com/gpmerola/deterministic-todo-releases/releases/tag/v2.109.0):
  `v2.109.0` `latest`, non prerelease; manifest con quattro APK e SHA-256
  identici ai digest degli asset.
- Google Play: `publish-google-play` riuscito (track `internal`);
  propagazione non verificata.
- Galaxy: ADB non raggiungibile (porta 5555 rifiutata dopo il riavvio); nessuna
  verifica sul dispositivo per questa release.

## Esiti precedenti

Archivio per mese, superato dalle sezioni sopra:
[ottobre 2026, build 190–283](docs/archive/status/2026-10.md),
[settembre 2026, build 168–189](docs/archive/status/2026-09.md),
[agosto 2026 e sintesi iniziali](docs/archive/status/2026-08.md).
