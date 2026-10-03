# Agenda unificata (Android)

Dalla build 191. Problema: KCL, SLaM e gli altri account Microsoft 365, insieme
alle riunioni Teams, si integrano male in Google Calendar (link ICS lenti o
disattivati, abbonamenti incompleti). Un collegamento diretto a Microsoft Graph
richiederebbe il consenso dell'amministratore di ogni tenant, di solito negato
dall'NHS e dalle università.

## Fonte dei dati

L'agenda legge il **calendario di sistema Android** (`CalendarContract`) tramite
il plugin `device_calendar_plus`, già usato per l'esportazione. Vi compaiono
tutti gli account che il telefono sincronizza: Google e qualsiasi account
Exchange o Outlook per cui l'app Outlook ha attivo **Sincronizza calendari**.
Todo non autentica nessun account e non contatta Microsoft o Google.

Se un'organizzazione vieta via Intune la copia del calendario sul telefono,
quell'account non compare; non esiste un aggiramento lato app.

## Contratto

- **Sola lettura.** Todo non crea, modifica né cancella eventi di terzi. Toccare
  un evento lo apre nell'app calendario del sistema (`showEventModal`), dove le
  modifiche restano responsabilità di quell'app.
- **Solo locale.** Eventi, titoli, luoghi e descrizioni non vengono salvati in
  SQLite, nei log, nei backup o su Supabase: possono contenere dati clinici. È
  salvato soltanto, in `app_settings.agenda_hidden_calendars`, l'elenco degli ID
  dei calendari nascosti. Gli ID sono locali al dispositivo e non vengono
  sincronizzati.
- **Lettura su richiesta.** Nessun polling né worker: l'agenda interroga il
  provider all'apertura, al ritorno in primo piano mentre è visibile, al
  pull-to-refresh e quando si estende la finestra. La finestra iniziale è di 14
  giorni da oggi e cresce di 14 alla volta.
- **Calendari.** Sono elencati quelli che il sistema marca visibili, ordinati per
  account e nome; ognuno si può nascondere da **Calendari**.
- **Duplicati.** Lo stesso evento presente in più calendari (titolo uguale senza
  distinzione di maiuscole e spazi finali, stesso inizio, fine e flag giornata
  intera) appare una volta. Il colore viene dal primo calendario nell'ordine
  sopra, e sotto il titolo sono elencati tutti i calendari di provenienza.
- **Annullati.** Le occorrenze con stato `canceled` non sono mostrate.
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
- `lib/ui/views/agenda_view.dart`: vista, selettore calendari, etichette orarie.
- `test/agenda_test.dart`: regressioni della logica e della vista.
