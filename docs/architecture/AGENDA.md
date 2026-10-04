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
  giorni della settimana usano caratteri e margini più piccoli.
- **Celle (build 203; orario dalla 204).** Nelle viste 2 settimane e Mese gli eventi di giornata
  intera hanno lo sfondo del colore del calendario; quelli con orario hanno un
  pallino colorato, l'ora d'inizio compatta, più piccola e attenuata («9»,
  «16:30»: `compactTime`), e il titolo. Le attività hanno una casella di
  spunta.
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
`titleQuery`, `LIKE` con caratteri jolly protetti), al massimo 200 righe; poi
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
- `test/agenda_test.dart` e `AgendaChannelTest.java`: regressioni.
