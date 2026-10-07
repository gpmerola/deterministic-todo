# Promemoria del Calendario Android

Dalla build 245: **Calendario → ⋮ → Promemoria → Avvisa 30 minuti prima**.
Attivo al primo avvio; scelta locale salvata in SQLite
`app_settings.agenda_reminders_enabled` (assente = true). Disattivare svuota
la coda, annulla l'allarme e rimuove soltanto le notifiche del Calendario Todo.
La preferenza non viene sincronizzata né inclusa nel backup degli account.

## Ambito e permessi

- Tutti gli eventi con orario visibili, compresi quelli preesistenti e le
  occorrenze ricorrenti. Stessi filtri, calendari nascosti e unione dei
  duplicati della vista Calendario, prima del raggruppamento grafico visite.
- Esclusi eventi tutto il giorno e attività Todo senza orario. Nessun avviso
  retroattivo se un evento entra nel Calendario meno di 30 minuti prima.
- Notifiche locali Todo: nessuna scrittura in Google, Outlook o nel provider;
  gli avvisi eventualmente configurati nelle altre app restano indipendenti.
- Android 13+: richiesta notifiche una sola volta, dopo accesso al Calendario.
  Il pannello segnala blocchi dell'app o del canale «Promemoria Calendario».
- `SCHEDULE_EXACT_ALARM`: se autorizzato si usa `setExactAndAllowWhileIdle`;
  altrimenti `setAndAllowWhileIdle`, con possibile ritardo esplicitato nel
  pannello. **Consenti in Android** apre il permesso pertinente. Non si cambia
  di nascosto alcuna preferenza Android. Risparmio batteria/Doze e arresto
  forzato possono comunque limitare il funzionamento: riaprire Todo dopo un
  arresto forzato.
- Toccare la notifica apre il Calendario del package corrente. Titolo nascosto
  sul blocco schermo tramite `VISIBILITY_PRIVATE`; nessun dato evento nei log.

Riferimenti: [allarmi Android](https://developer.android.com/develop/background-work/services/alarms),
[permesso notifiche](https://developer.android.com/develop/ui/compose/notifications/notification-permission).

## Flusso e limiti

`CalendarContract + scelte SQLite → piano Dart → cache privata Android → AlarmManager`.
SQLite e provider restano canonici. SharedPreferences `agenda_reminders` contiene
solo la cache sostituibile necessaria alle notifiche (ID opaco, ID provider,
titolo, inizio, istante avviso), stato derivato e ricevute già inviate. Non è
una copia da sincronizzare o promuovere a fonte dati.

`AgendaReminders.refresh` rilegge calendari e filtri senza cache UI. Orizzonte
limitato a oggi più i sette giorni successivi. Ogni occorrenza ha una chiave
stabile SHA-256; attraversare la mezzanotte o il cambio d'ora non moltiplica gli
avvisi. Sottrazione di 30 minuti sull'istante, non sull'ora civile.

Un solo allarme Android punta al primo gruppo in scadenza, poi arma il
successivo: nessun timer/polling, rete, foreground service o nuova dipendenza.
Una generazione monotona nativa impedisce a un piano iniziato prima di una
modifica o disattivazione di sovrascrivere il più recente, anche se proviene
da un engine headless distinto.
Prima di notificare controlla ancora in `Instances` che la stessa occorrenza
non sia stata eliminata, spostata, annullata o rifiutata; legge il titolo
attuale. Le ricevute evitano ripetizioni dopo un refresh; il piano conserva
un avviso già dovuto ma non ancora emesso finché l'evento non è iniziato.

Aggiornamento all'avvio/ripresa e dopo modifiche/filtri. `AgendaReminderJob`
usa un trigger sui cambiamenti del provider (batch 1–5 secondi) e un job
giornaliero persistente per estendere l'orizzonte, entrambi senza vincoli di
rete. Il trigger confronta prima un'impronta dei soli prossimi otto giorni:
nessun engine Dart per notifiche del provider senza modifiche effettive.

Il lavoro locale usa il ramo `reminders` del runner esistente prima di qualsiasi
lettura sessione/Supabase, anche da processo terminato. Boot, aggiornamento APK,
cambio ora/fuso e concessione del permesso allarmi riarmano la cache e chiedono
un refresh. Permesso calendario revocato: coda vuota, nessuna notifica; riaprire
l'app dopo averlo ripristinato. Errori transitori non vengono registrati con
contenuti personali; i job ritentano con il backoff Android.

## Verifica riproducibile

- `flutter test test/agenda_reminders_test.dart`: default/persistenza, filtri,
  duplicati, ricorrenze, mezzanotte/DST, revoca permessi e interruttore UI.
- Da `android/`, `./gradlew :app:testDevDebugUnitTest`: politica eventi entrati
  tardi, avvisi già dovuti e scadenza.
- `python3 tools/agenda_provider_smoke.py --reminders --serial emulator-5554`:
  richiede emulatore arm64 e firma Todo Test locale; usa `.dev.validation`, DB
  in memoria ed eventi sintetici rimossi al termine. Verifica notifica reale,
  nessun duplicato al refresh, eventi cancellati/spostati, disattivazione e rifiuto di piani obsoleti. Risultato
  atteso `Agenda native provider smoke: PASS`. Non accetta telefoni reali;
  conserva gli APK normali prima di compilare l'harness.
- `make check` e `make check-generated` prima della consegna; `make todo-test`
  installa l'APK funzionale sul Galaxy. Esiti correnti in [STATUS](../../STATUS.md).

Il test sintetico non equivale a una misura di puntualità dopo molte ore di
Doze o a un collaudo di reboot fisico del Galaxy.
