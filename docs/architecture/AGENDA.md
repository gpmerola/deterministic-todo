# Agenda unificata (Android)

Dalla build 191. Problema: KCL, SLaM e gli altri account Microsoft 365, insieme
alle riunioni Teams, si integrano male in Google Calendar (link ICS lenti o
disattivati, abbonamenti incompleti). Un collegamento diretto a Microsoft Graph
richiederebbe il consenso dell'amministratore di ogni tenant, di solito negato
dall'NHS e dalle università.

## Fonte dei dati

L'agenda legge il **calendario di sistema Android** (`CalendarContract`). Il
plugin `device_calendar_plus`, già usato per l'esportazione, gestisce permesso,
elenco calendari e apertura degli eventi. Dalla build 196 gli eventi arrivano da
`AgendaChannel`, nativo: una sola query `Instances` per intervallo, con solo le
colonne necessarie. Il plugin eseguiva due query extra per ogni evento
(partecipanti e promemoria) e trasferiva le descrizioni HTML complete degli
inviti. Le descrizioni sono ridotte in Java ai soli URL Teams, Zoom e Meet. Vi compaiono
tutti gli account che il telefono sincronizza: Google e qualsiasi account
Exchange o Outlook per cui l'app Outlook ha attivo **Sincronizza calendari**.
Todo non autentica nessun account e non contatta Microsoft o Google.

Se un'organizzazione vieta via Intune la copia del calendario sul telefono,
quell'account non compare; non esiste un aggiramento lato app.

## Contratto

- **Scrittura solo esplicita.** Toccare un evento apre un dettaglio (build 201)
  con orario, fuso, luogo, calendario, «Partecipa» e le azioni **Modifica**,
  **Elimina** e **Apri nel calendario** (`showEventModal`). Modifica ed
  eliminazione compaiono solo se il calendario è scrivibile e sei tu
  l'organizzatore (`IS_ORGANIZER`). Gli inviti di altri si cambiano dal
  calendario di chi li organizza, altrimenti la loro sincronizzazione
  sovrascriverebbe la modifica. Per un evento ricorrente si sceglie **Solo
  questa** occorrenza (`updateEvent`/`deleteEvent` con l'id d'istanza) o
  **Tutta la serie** (`updateRecurring`/`deleteRecurring` con
  `EventSpan.allEvents`: la serie si sposta dello stesso scarto
  dell'occorrenza). L'eliminazione singola chiede conferma. Il modulo di
  modifica rilegge l'evento completo con `getEvent`, note comprese, e non
  permette di cambiare calendario. Dalla build 199 si possono **creare** eventi: con il pulsante
  **+** dell'Agenda o della vista giorno, oppure toccando uno spazio libero
  nella vista giorno, che preimposta la mezz'ora toccata. Il modulo chiede
  titolo, calendario, giornata intera o orari (un'ora di default), luogo e note
  facoltativi. L'evento è scritto nel calendario scelto con il plugin
  (`createEvent`) e con il fuso IANA del sistema; lo carica online la
  sincronizzazione dell'account (Google o Outlook). Sono proposti solo i
  calendari modificabili. Quello preselezionato è l'ultimo usato
  (`app_settings.agenda_last_event_calendar`, locale). In mancanza, un
  primario Google mostrato nell'Agenda: il telefono ha più account Google,
  ognuno con il proprio primario, e dalla build 200 quelli nascosti
  nell'Agenda vengono saltati. Poi qualsiasi calendario mostrato, poi un
  primario Google, poi il primo modificabile. Gli eventi creati non entrano in SQLite Todo né in Supabase.
- **Solo locale.** Eventi, titoli, luoghi e descrizioni non vengono salvati in
  SQLite, nei log, nei backup o su Supabase: possono contenere dati clinici. È
  salvata soltanto la scelta dei calendari in
  `app_settings.agenda_calendar_choices`, una mappa `{id: mostrato}`. La build
  191 usava `agenda_hidden_calendars`, letta una volta come "nascosti". Gli ID
  sono locali al dispositivo e non vengono sincronizzati.
- **Fuso orario (build 201).** Il fuso riconosciuto è sempre visibile come
  identificatore IANA con lo scarto da UTC, per esempio «Europe/London ·
  UTC+1». Compare sotto l'intestazione dell'Agenda, sotto la data della vista
  giorno, nel dettaglio e nel modulo dell'evento. Lo fornisce
  `AgendaChannel.deviceZone` (`ZoneId.systemDefault()`), mai abbreviazioni, e
  viene riletto a ogni caricamento e al rientro in primo piano: in viaggio
  segue il telefono. Tutti gli orari sono mostrati in quel fuso. Se il fuso
  proprio dell'evento (`EVENT_TIMEZONE`) ha in quel momento uno scarto
  diverso, il dettaglio aggiunge «Orario originale 13:00–14:00 Europe/Rome»,
  calcolato in Java. I nuovi eventi usano il fuso del sistema. Se Android non
  lo riconosce, l'interfaccia lo dice invece di indovinare.
- **Settimana (build 203).** Sette colonne con le ore in scala (48 dp per
  ora), come la vista giorno: i buchi liberi della settimana si vedono a
  colpo d'occhio. Gli eventi di giornata intera e le attività stanno in una
  fascia in alto (al massimo due righe, poi «+N»). Scorrendo in orizzontale si
  cambia settimana, da un anno indietro a tre avanti. Toccando un evento si apre
  il dettaglio, toccando l'intestazione di un giorno la vista giorno, toccando
  uno spazio libero un nuovo evento alla mezz'ora toccata.
- **Mese a schermo intero (build 205, predefinito).** Ogni mese occupa tutta
  l'altezza: le righe (5 o 6 settimane, dal lunedì) si dividono lo spazio e
  ogni giorno mostra tutte le voci che ci stanno, poi «+N». I giorni dei mesi
  vicini completano le settimane, attenuati. Dalla build 206 si cambia mese
  scorrendo di lato, come in Settimana e Giorno; lo stesso vale per la vista
  2 settimane. L'intervallo va da un anno indietro a tre avanti. La preferenza della vista ha una
  nuova chiave (`agenda_view_mode_v2`), così una scelta «2 settimane» salvata
  in precedenza non sostituisce il nuovo predefinito. Nell'Agenda la barra di
  navigazione in basso è più bassa (56 dp, etichetta solo sulla voce
  attiva), il **+** è piccolo e la riga in alto misura 36 dp.
- **Spazio ai giorni (build 204).** Nell'Agenda la barra superiore dell'app
  (anello passi, sincronizzazione, ricerca, impostazioni) è nascosta. Sopra i
  giorni resta una sola riga di 40 dp con il menu della vista (Settimana,
  2 settimane, Mese, Elenco), **Oggi**, il fuso riconosciuto, i calendari
  (icona e conteggio) e **⋮** con Cerca e Impostazioni. Intervalli di date e
  giorni della settimana usano caratteri e margini più piccoli. Dalla build
  219 il fuso delle griglie sta a destra del titolo del periodo, perché
  nella riga veniva tagliato («Londo…»); l'Elenco lo tiene nella riga. La
  barra in basso è la stessa di tutte le sezioni.
- **Celle (build 203; orario dalla 204; due righe dalla 219).** Nelle viste
  2 settimane e Mese gli eventi di giornata intera hanno lo sfondo del
  colore del calendario. Quelli con orario mostrano l'ora d'inizio compatta
  («9», «16:30»: `compactTime`) in grassetto nel colore del calendario e,
  sotto, il titolo su tutta la larghezza. Prima stavano sulla stessa riga e
  il titolo restava di 4–5 lettere. Le attività hanno una casella di
  spunta. Nel tema scuro i colori dei calendari sono smorzati
  (`agenda_colors.dart`); nella settimana i titoli vanno a capo solo tra le
  parole (`agenda_word_wrap.dart`).
- **2 settimane (build 201, predefinita).** Due settimane dal lunedì riempiono
  lo schermo, così ogni giorno ha spazio per più eventi, con l'ora d'inizio
  davanti al titolo. Scorrendo in verticale si passa alla quindicina
  successiva o precedente, fino a 6 mesi indietro e 3 anni avanti. Ogni giorno
  mostra tutti gli eventi che ci stanno, oppure «+N». **Mese** ed **Elenco**
  restano selezionabili; la scelta è salvata.
- **Viste.** Dalla build 194 alla 200 la vista predefinita era **Mese**: griglie mensili
  con lunedì come primo giorno, da 12 mesi indietro a 36 avanti, che scorrono in
  verticale come in Google Calendar. Ogni cella mostra fino a tre eventi colorati
  dal calendario, o due più «+N»; i giorni passati sono attenuati. Toccare un
  giorno apre il dettaglio con orari, luoghi e pulsante riunione. **Oggi**
  riporta al mese corrente. **Elenco** è la vista per giorni delle build
  191–193. La scelta è salvata in `app_settings.agenda_view_mode`.
- **Cache in memoria.** Calendari, scelte, vista e intervalli letti restano in
  memoria per la sessione dell'app (al massimo 64 intervalli, mai su disco).
  Riaprendo l'Agenda la vista li mostra subito e li rilegge in background; un
  mese già visibile non si svuota durante la rilettura.
- **Lettura su richiesta.** Nessun polling né worker. Nella vista Mese ogni mese
  interroga il provider solo quando viene costruito sullo schermo, e il
  risultato resta in memoria finché la vista non si ricarica. Si ricarica
  all'apertura, al ritorno in primo piano mentre è visibile, al
  pull-to-refresh e al cambio di calendari. L'Elenco parte da 14 giorni e cresce
  di 14 alla volta.
- **Calendari.** Sono elencati tutti, ordinati per account e nome. Una scelta
  esplicita in **Calendari** prevale; altrimenti vale la visibilità impostata
  nell'app calendario del telefono, quindi i calendari che il telefono nasconde
  (festività, account secondari) partono spenti ma si possono accendere.
- **Duplicati.** Lo stesso evento presente in più calendari (titolo uguale senza
  distinzione di maiuscole e spazi finali, stesso inizio, fine e flag giornata
  intera) appare una volta. Il colore viene dal primo calendario nell'ordine
  sopra, e sotto il titolo sono elencati tutti i calendari di provenienza.
- **Annullati.** Le occorrenze con stato `canceled` non sono mostrate.
- **Filtri (build 197).** Si impostano in **Calendari** e sono salvati in
  `app_settings.agenda_filter`, solo sul dispositivo. **Nascondi inviti senza
  risposta** esclude le occorrenze con `SELF_ATTENDEE_STATUS = INVITED`, cioè
  gli eventi tratteggiati di Outlook (broadcast e simili). Gli inviti accettati,
  provvisori o creati da te restano. **Nascondi eventi che contengono…**
  esclude i titoli che contengono una delle parole, senza distinguere le
  maiuscole. Con il libero/occupato SLaM pubblicato su Google i blocchi senza
  risposta hanno titolo «Tentative»: la parola «Tentative» li nasconde. I filtri
  si applicano prima dell'unione dei duplicati; con un filtro attivo l'icona di
  **Calendari** diventa un imbuto.
- **Vista giorno (build 197).** Toccare un giorno nella vista Mese apre una
  pagina con le 24 ore in scala (64 dp per ora), così i vuoti tra gli impegni
  sono proporzionali. Gli eventi sovrapposti vanno in colonne affiancate, con
  durata minima visibile di 20 minuti; gli eventi a cavallo della mezzanotte
  sono tagliati al giorno; quelli di giornata intera stanno in alto. La pagina
  si apre poco prima del primo impegno, oppure intorno all'ora attuale se il
  giorno è vuoto. Oggi ha una linea dell'ora corrente. Scorrendo in orizzontale
  si passa al giorno precedente o successivo. Un blocco di almeno un'ora mostra
  «Partecipa · Teams/Zoom/Meet». Il calcolo è `layoutDayTimeline`, puro e
  testato.
- **Riunioni online.** Il primo link Teams (`teams.microsoft.com/l/meetup-join`,
  `teams.microsoft.com/meet`, `teams.live.com/meet`), Zoom (`*.zoom.us/j/`) o
  Google Meet trovato in URL, luogo o descrizione diventa un pulsante che apre
  l'app esterna.
- **Giorni.** Un evento compare in ogni giorno civile che interseca (fine
  esclusa); un evento di durata zero compare nel giorno di inizio. Prima gli
  eventi di giornata intera, poi per inizio, fine, titolo e ID occorrenza. Gli
  eventi a cavallo della mezzanotte mostrano «dalle 22:00» o «fino 02:00».
- **Piattaforme.** Solo Android. Sul Web la sezione non è mostrata.

## Agenda sul Web (build 212)

Il browser non vede i calendari del telefono. Il telefono quindi carica su
Supabase una **copia** di ciò che mostra la sua Agenda, e il Web la legge.
Dalla build 213 il Web può anche creare, modificare ed eliminare eventi
tramite una coda applicata dal telefono (sezione successiva). L'utente ha accettato la presenza dei titoli degli eventi su
Supabase, dichiarando che non contengono dati di pazienti.

**Cosa entra nella copia** (`buildAgendaMirror`):

- calendari mostrati (con colore e nome), filtri applicati e duplicati uniti;
- finestra da 30 giorni indietro a 90 avanti;
- per ogni evento: titolo, luogo, inizio e fine in UTC (gli eventi di
  giornata intera anche come date civili), link della riunione, fuso
  dell'evento e orario originale;
- per ogni calendario anche se è scrivibile (`writable`, dalla 213), così il
  Web offre la modifica solo dove il telefono può scrivere. Dalla 215
  la copia segna anche `main` («Nuovi eventi in») e `ai` (calendario ✨):
  sul Web sono i predefiniti, salvo una scelta fatta nel browser;
- le chiavi «Mostra in agenda» delle attività. Le attività stesse arrivano al
  Web dalla normale sincronizzazione.

Note e descrizioni non vengono inviate.

**Scrittura.** Una sola RPC, `replace_agenda_snapshot_v1(jsonb)`
(migrazione `202610040001_agenda_mirror.sql`), sostituisce l'intera copia
dell'utente in un'unica transazione: elimina gli eventi precedenti, inserisce i
nuovi e aggiorna `agenda_snapshots`. È `security definer` con `auth.uid()`
come proprietario. Le tabelle hanno RLS «select own»; INSERT, UPDATE, DELETE e
TRUNCATE sono revocati a `anon` e `authenticated`; `anon` non legge. Limite:
5.000 eventi. Verificata con PGlite (`tools/sql-tests/agenda_mirror.mjs`).

**Quando il telefono carica** (`AgendaMirror`):

- all'avvio e al ritorno in primo piano, al massimo ogni 10 minuti;
- subito dopo una modifica nell'Agenda, una creazione ✨, un'attività
  collegata o un cambio di calendari o filtri.

Dalla build 213 anche in background, quando cambia il calendario del
telefono (vedi «Aggiornamento in background»). Se fallisce, nessun errore
visibile: riprova al passaggio successivo.

**Web** (`WebAgendaService`):

- tutte le viste, il dettaglio, la vista giorno e la ricerca leggono
  `agenda_events`;
- gli orari sono nel fuso del browser, letto come IANA da
  `Intl.DateTimeFormat`; gli eventi di giornata intera mantengono le loro
  date;
- l'intestazione mostra «Copia dal telefono · <ora del caricamento>» e,
  se ci sono, quante modifiche sono «in attesa»;
- sul Web non c'è «Apri nel calendario»; ci sono +, Modifica ed Elimina
  (vedi sotto), «Partecipa» e «Preparare/Follow-up»;
- senza una copia, un messaggio spiega di aprire Todo sul telefono;
- anche **Oggi** sul Web mostra la riga degli impegni.

## Modifiche dal Web (build 213)

Solo il telefono può scrivere nei suoi calendari. Il Web quindi mette la
richiesta in coda in `agenda_requests` e il telefono la applica come una
modifica fatta nell'Agenda.

**Coda** (migrazione `202610050001_agenda_requests.sql`):

- una riga per richiesta: `create`, `update` o `delete`, occorrenza
  (`instance_key`), «tutta la serie» e `payload`;
- orari in UTC, giornate intere come date civili: fusi diversi tra browser
  e telefono non spostano nulla;
- RLS «own»; il browser può inserire solo tipo, occorrenza, serie e
  payload. Stato, proprietario e orari li impostano i default e le RPC;
- una richiesta si può cambiare o ritirare finché il telefono non la prende;
- al massimo 100 richieste aperte e payload fino a 8 KB.

**Telefono** (`AgendaRequestProcessor`):

- `claim_agenda_requests_v1` consegna ogni richiesta **una sola volta**
  (stato `processing`), in ordine di creazione;
- il telefono la applica e poi chiama `complete_agenda_request_v1`, con
  `done` oppure `failed` e un motivo breve in italiano;
- se il telefono si interrompe a metà, dopo 30 minuti la richiesta diventa
  «Esito sconosciuto: controlla il calendario sul telefono». Non viene mai
  ripetuta, così un evento non nasce mai due volte;
- le richieste chiuse si cancellano dopo 14 giorni.

**Regole di applicazione:**

- il calendario deve esistere ed essere scrivibile sul telefono;
- una modifica mantiene calendario, note e regola di ripetizione del
  telefono. Le note non sono nella copia, quindi dal Web non si modificano;
- modificare un evento sparito è un errore; eliminarlo è già fatto;
- note e ripetizione viaggiano solo con una creazione.

**Quando il telefono applica:**

- all'apertura e al ritorno in primo piano, al massimo una volta al minuto;
- dal lavoro in background orario.

Subito dopo, il telefono carica una nuova copia.

**Web:**

- finché la copia non riflette la richiesta, il Web mostra l'effetto
  previsto marcato «In attesa ·» (`applyAgendaRequests`, in ordine di
  creazione qualunque sia l'ordine delle righe; fino alla 214 era ⏳):
  nuovi eventi aggiunti, modifiche
  già applicate, eliminazioni nascoste;
- un evento «In attesa» ancora in coda si può modificare o eliminare, cioè ritirare;
- le richieste rifiutate compaiono con l'icona rossa nell'intestazione, con
  il motivo. «Ignora» toglie solo l'avviso.

## Aggiornamento in background (build 213)

Per tenere aggiornato il Web senza aprire Todo, senza polling e senza timer
nell'app, ci sono due job Android (`AgendaBackground`,
`AgendaBackgroundJob`). L'app li programma solo dopo l'accesso alla
sincronizzazione.

1. **Calendario cambiato.** Usa un `JobInfo.TriggerContentUri` su
   `CalendarContract.CONTENT_URI`:
   - raggruppa le notifiche per 1 minuto, al massimo 15, e richiede la rete;
   - prima di avviare Dart calcola un'impronta SHA-256 delle occorrenze
     nella finestra della copia, con una query sola;
   - se l'impronta non è cambiata (contabilità di sync di Google o Outlook),
     finisce lì.
2. **Ogni ora circa** (persistente, flex 20 minuti, con rete). Applica le
   modifiche in coda dal Web e, dalla 216, carica la copia se l'impronta è
   cambiata. Ripristina anche il job 1 dopo un riavvio, quando Android
   dimentica i trigger sul contenuto.
3. **Nuovo tentativo** (dalla 216). Dopo un caricamento fallito con il
   calendario cambiato, un job singolo con rete riprova dopo 2, 4, 8…
   minuti, al massimo un'ora; il contatore si azzera al primo successo.
   Nella prova reale della 215 un'eliminazione non era arrivata al Web
   perché la rete del telefono cambiava durante il caricamento.

**Dove gira Dart.** Se il motore dell'app è vivo, il lavoro passa da lì:
una sola sessione Supabase e nessun doppio rinnovo del token. Altrimenti
parte un motore headless (`agendaBackgroundMain`), che:

- apre lo stesso database e la sessione salvata, senza deep link;
- attende il recupero della sessione, perché `Supabase.initialize` non lo
  attende;
- se la sessione è scaduta la rinnova e, prima di chiudersi, salva la
  sessione corrente;
- fa un solo giro e viene distrutto, al più tardi dopo 90 secondi.

**Sessione: regola di sicurezza (dalla 217).** Il motore headless usa
`BackgroundSessionStorage`, che non cancella mai la sessione salvata.

Il difetto nelle build 213–216: il motore partiva con
`autoRefreshToken: false`. Con una sessione scaduta (app non aperta da più
di un'ora), gotrue faceva il logout locale e supabase_flutter cancellava la
sessione dal telefono, quindi l'utente doveva rifare il login. Segnalato
dall'utente il 4 ottobre 2026; regressione in
`test/background_session_test.dart`.

Ora, se il rinnovo non riesce, il giro risponde `retry` e lascia la
sessione all'app, l'unica che può uscire davvero dall'account. Dopo un
nuovo login i job si riattivano a ogni apertura.

**Esiti.** Dart risponde `done` (si memorizza l'impronta), `retry` oppure
`stop` (nessun accesso o nessun permesso calendario): con `stop` i job
vengono cancellati finché l'app non li riprogramma. Nessun contenuto entra
nei log.

## Sovrapposizioni (build 213)

`agendaOverlaps` segnala gli eventi con orario che si sovrappongono a un
altro evento con orario, di qualunque calendario. Non contano:

- eventi di giornata intera e attività;
- eventi consecutivi (uno finisce quando l'altro inizia);
- lo stesso evento presente in due calendari, già unito.

Nella vista giorno e nella vista settimana i blocchi in conflitto hanno il
bordo rosso; la vista giorno aggiunge ⚠ all'orario. Il dettaglio
dell'evento elenca «Si sovrappone a:» con orari e titoli.

## Calendario e lista più vicini (build 211)

- **Oggi** ha in cima una riga con gli impegni che restano della giornata:
  fino a tre con orario, «+N» e quanti sono di giornata intera.
  - Le attività segnate sono escluse, perché sono già nella lista.
  - La riga si rilegge all'apertura, al ritorno in primo piano e a mezzanotte,
    senza timer.
  - Toccandola si apre la vista giorno, con dettaglio, creazione e modifica
    come nell'Agenda (`AgendaService.agendaDays`).
- Il dettaglio di un evento ha **Preparare (giorno prima)** e **Follow-up
  (giorno dopo)**: un'attività «Preparare: <titolo>» o «Follow-up: <titolo>»,
  con note «Collegata a: <titolo · giorno ora>».
  - La data è il giorno lavorativo prima dell'inizio, o dopo la fine (per
    gli eventi di giornata intera, l'ultimo giorno).
  - L'attività è segnata «Mostra in agenda». Calcolo deterministico
    (`linkedTaskFor`), senza AI.
- **Calendario principale.** «Nuovi eventi in» cambia solo per scelta
  esplicita. Fino alla 210 ogni creazione lo spostava sull'ultimo calendario
  usato, quindi un evento ✨ portava anche il **+** su «✨ Assistente».
  «Aggiungi a Google Calendar» dall'editor di un'attività usa lo stesso
  calendario (`mainCalendarKey`) invece del primo primario Google in ordine
  alfabetico. Nessun indirizzo è scritto nel codice: la scelta resta sul
  telefono.
- **Leggibilità.**
  - Nell'intestazione il fuso è abbreviato («London · UTC+1», il nome IANA
    completo resta nel dettaglio e nella vista giorno).
  - Il menu della vista mostra icona, nome breve e freccia («Mese ▾»).
  - Sabato e domenica hanno una tinta leggera nelle griglie.

## Attività Todo nell'agenda (build 203)

Nel menu ⋮ dell'editor di un'attività (solo Android) si attiva **Mostra in
Agenda**. L'attività compare nel giorno della sua data come voce di giornata
intera, dopo gli eventi, con una casella di spunta (barrata se completata).
Toccandola si apre l'editor. Per un'attività di una serie ricorrente il flag
vale per l'intera serie (`series:<id>`), così ogni occorrenza compare. Senza
data l'attività non compare finché non ne riceve una.

Il flag è **solo locale**: `app_settings.agenda_task_links`, un elenco di
`task:<id>` e `series:<id>`. L'Agenda esiste solo su Android, mentre una
colonna sincronizzata avrebbe richiesto una migrazione Supabase e modifiche
al codice di sincronizzazione. Viaggia con i backup; non passa da Supabase.

## Ricorrenza nella creazione (build 203)

Il modulo **Nuovo evento** ha **Ripeti**: non si ripete, ogni giorno, giorni
feriali (lun–ven), ogni settimana nello stesso giorno, ogni mese nello stesso
giorno, ogni anno nella stessa data. Si può aggiungere **Fino al**, con
l'ultimo giorno incluso (UNTIL alla fine di quel giorno, in UTC). La regola
passa al plugin come `RecurrenceRule` (`AgendaService.recurrenceRuleFor`).
Modificando una serie esistente la regola resta quella attuale.

## Ricerca unificata (build 203)

Il comando universale (lente) mostra, dopo le attività, una sezione
**Eventi**: titoli che contengono il testo, almeno 2 caratteri, nei calendari
mostrati nell'Agenda, con i filtri applicati. L'intervallo va da un anno
indietro a due avanti. È una sola query nativa (`instances` con
`titleQuery`), al massimo 200 righe. Dalla build 213 ignora maiuscole e
accenti («attivita» trova «attività»): un `LIKE` largo, con `_` al posto
delle lettere che possono essere accentate, restringe in SQLite; poi il
titolo, normalizzato in NFD e senza segni diacritici, conferma in Java. poi
si mostrano i 30 risultati più vicini, prima i prossimi e poi i passati più
recenti. Toccando un risultato si apre lo stesso dettaglio dell'Agenda. Nulla
viene salvato. I filtri della ricerca (Oggi, Senza data, …) riguardano solo
le attività e nascondono la sezione Eventi.

## Codice e test

- `lib/domain/agenda.dart`: unione, duplicati, link e giorni, puro.
- `lib/services/agenda_service.dart`: permessi, provider, calendari nascosti.
- `lib/ui/views/agenda_view.dart`: vista, Elenco, selettore calendari, etichette.
- `lib/ui/views/agenda_month_view.dart`: griglie mensili e celle.
- `lib/ui/views/agenda_day_view.dart`: vista giorno in scala.
- `lib/ui/views/agenda_weeks_view.dart`: vista a 2 settimane.
- `lib/ui/views/agenda_week_view.dart`: vista settimana a colonne.
- `lib/ui/views/agenda_event_flows.dart`: dettaglio, creazione, modifica ed
  eliminazione condivisi da viste e ricerca.
- `lib/services/agenda_tasks.dart`: flag locali «Mostra in agenda».
- `lib/ui/views/agenda_event_sheet.dart` e `agenda_event_editor.dart`:
  dettaglio, creazione, modifica ed eliminazione.
- `android/app/.../AgendaChannel.java`: query nativa e riduzione ai link.
- `lib/domain/agenda_request.dart`, `lib/services/agenda_requests.dart`,
  `agenda_phone_sync.dart` e `lib/background/agenda_background.dart`: coda
  dal Web, telefono e job in background.
- `android/app/.../AgendaBackground.java` e `AgendaBackgroundJob.java`: job,
  impronta e motore headless.
- `lib/domain/text_fold.dart`: ricerca senza accenti (attività, Agenda, Web).
- `test/agenda_test.dart`, `agenda_requests_test.dart`,
  `agenda_overlap_test.dart`, `search_fold_test.dart`,
  `AgendaChannelTest.java`, `AgendaBackgroundTest.java` e
  `tools/sql-tests/agenda_requests.mjs`: regressioni.
