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

Le attività Todo non compaiono ancora nell'agenda. Il passo successivo previsto
è un'opzione esplicita per singola attività ("Mostra in agenda"), che richiede
una colonna sincronizzata e una migrazione Supabase.

## Codice e test

- `lib/domain/agenda.dart`: unione, duplicati, link e giorni, puro.
- `lib/services/agenda_service.dart`: permessi, provider, calendari nascosti.
- `lib/ui/views/agenda_view.dart`: vista, Elenco, selettore calendari, etichette.
- `lib/ui/views/agenda_month_view.dart`: griglie mensili e celle.
- `lib/ui/views/agenda_day_view.dart`: vista giorno in scala.
- `lib/ui/views/agenda_weeks_view.dart`: vista a 2 settimane.
- `lib/ui/views/agenda_event_sheet.dart` e `agenda_event_editor.dart`:
  dettaglio, creazione, modifica ed eliminazione.
- `android/app/.../AgendaChannel.java`: query nativa e riduzione ai link.
- `test/agenda_test.dart` e `AgendaChannelTest.java`: regressioni.
