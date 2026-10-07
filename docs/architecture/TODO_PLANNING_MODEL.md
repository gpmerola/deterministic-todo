# Todo: pianificazione, viste e struttura della shell — build 189

Fonte canonica per stato, appartenenza alle viste, Inbox, ricerca e cambio di
giorno. Sincronizzazione e storico restano in
[sincronizzazione e storico](TODO_SYNC_AND_HISTORY.md).

## Regola di pianificazione

La pianificazione di un'attività aperta dipende soltanto da `show_date`.
`status` distingue esclusivamente `completed` e `waiting`: `inbox`,
`available` e `scheduled` sono valori aperti equivalenti.

I tre valori continuano a essere scritti perché i client precedenti alla 189
(schede Web non ricaricate, build Play di riserva) filtrano ancora su di essi.
`legacyOpenStatus` in `lib/domain/task_planning.dart` li proietta dalla data al
momento della scrittura: senza data `inbox`, fino a oggi `available`, nel futuro
`scheduled`. È l'unico punto che li calcola; lo usano creazione, editor,
riapertura dopo il completamento, occorrenze ricorrenti e import Todoist.

- `updateDetails` riproietta lo stato solo se la data cambia davvero: salvare
  altri campi non genera un intento sul campo `status`.
- Un elemento `completed` o `waiting` conserva lo stato quando si modifica la data.
- Riaprire un'attività completata con data futura la riporta in Prossime
  (`scheduled`); prima diventava `available` e restava in Oggi.
- Il cambio di giorno non scrive nulla: cambia solo la visibilità.

## Appartenenza alle viste

È definita una sola volta, in SQL, da `TaskRepository.watchView`. La UI ordina
e raggruppa le righe ricevute ma non le filtra di nuovo
(`lib/ui/views/task_order.dart`). Escluse sempre completate e tombstone.

| Vista | Righe |
| --- | --- |
| Oggi | aperte con data ≤ oggi; aperte senza data e senza progetto (Inbox); `waiting` solo nel giorno esatto |
| Prossime | aperte con data > oggi, nella finestra visibile |
| Progetto | tutte le non completate del progetto, qualunque data o stato |
| Completate | stream separato con limite |

Differenze rispetto alla 188, entrambe correzioni: un'attività `available` con
data futura compare in Prossime invece che in Oggi; un'attività senza data ma
in un progetto compare solo nel progetto. Le sezioni `Inbox` e `In attesa` della
shell non erano raggiungibili e sono state rimosse; lo stato `waiting` resta
nei dati e nel protocollo.

## Inbox

L'Inbox è l'insieme delle attività aperte senza data e senza progetto, mostrate
in Oggi. Nessun comportamento dipende più dal nome di un progetto.

- **Import Todoist**: il progetto con il flag Todoist `inbox_project` (o
  `is_inbox_project`) non viene creato; le sue attività restano senza progetto e
  le sue sezioni non vengono importate. Un progetto chiamato "Inbox" senza il
  flag è un progetto normale.
- **Dati esistenti**: il vecchio progetto "Inbox" importato prima della 189
  appare ora tra i progetti. **Azioni progetto → Sposta in Inbox**, dopo
  conferma, toglie progetto e sezione a tutte le sue attività non eliminate e
  archivia il progetto, in un'unica transazione con outbox. L'annullamento
  ripristina il progetto e le attività ancora senza progetto: una scelta fatta
  nel frattempo su un'altra attività prevale. Ogni modifica resta nello storico.
- La conversione è esplicita e funziona per qualunque progetto; nessuna
  migrazione automatica tocca i dati sincronizzati.

## `due_date`

La colonna locale è rimossa con lo schema SQLite 11. Poiché i trigger dello
storico e l'indice `tasks_dates_idx` la citavano, la migrazione li ricrea dallo
schema Dart corrente; se il motore non supportasse `DROP COLUMN` la colonna
resterebbe inutilizzata senza bloccare l'avvio. L'export CSV non ha più la
colonna `due_date`.

La colonna Supabase resta: rimuoverla richiede una migrazione server con
approvazione esplicita. Il client non la invia più, quindi il server conserva
il valore esistente (normalmente nullo); i backup JSON vecchi che la contengono
si importano ignorandola.

## Ricerca

`TaskRepository.watchSearch` filtra in SQLite titolo, descrizione e nome del
progetto (`#` limita ai progetti), applica i filtri rapidi e restituisce al
massimo `searchLimit` (100) righe: prima le attive, poi le completate, poi per
data. Ogni input distinto apre una sola query; la ricerca non carica più
l'intero archivio in memoria. `%` e `_` digitati sono caratteri letterali.

Limite: `LIKE` di SQLite ignora maiuscole e minuscole solo per ASCII, quindi
"È" non trova "è". Prima il confronto avveniva in Dart su tutte le righe.

## Cambio di giorno

`CivilDayClock` (`lib/ui/shell/civil_day_clock.dart`) arma un solo timer per la
mezzanotte locale e lo riarma dopo lo scatto; non esiste polling. Alla ripresa
dall'uso in background la shell chiama `refresh()`, perché un timer può
scattare in ritardo mentre il processo è sospeso. Una scheda Web aperta
durante la notte mostra così la Oggi corretta senza interazioni. Il cambio di
giorno non produce scritture né outbox (`test/task_views_test.dart`).

## Struttura della shell

`lib/main.dart` contiene avvio, tema, navigazione e layout della shell. Il
resto vive in librerie separate, testabili senza avviare l'app:

| File | Responsabilità |
| --- | --- |
| `ui/app_section.dart` | destinazioni principali |
| `ui/views/today_view.dart` | Oggi con gruppo Arretrate |
| `ui/views/upcoming_view.dart` | timeline Prossime e "Vai a data" |
| `ui/views/projects_view.dart` | progetti, sezioni, azioni e Sposta in Inbox |
| `ui/views/task_order.dart` | ordinamento di presentazione |
| `ui/search.dart` | comando universale e ricerca |
| `ui/quick_add_sheet.dart` | composer rapido e bozza locale |
| `ui/shell/app_update_flow.dart` | controllo e installazione aggiornamenti |
| `ui/shell/civil_day_clock.dart` | giorno civile corrente |
| `ui/shell/daily_steps_controller.dart` | passi del giorno, obiettivo e celebrazione |

Le viste ricevono le righe già filtrate e un `tileBuilder`: non dipendono dalla
shell né dall'editor. Dalla build 239 i passi sono un `ChangeNotifier`
ascoltato solo da anello e Impostazioni: il controllo al minuto non ridisegna
più l'intera shell e notifica solo se passi o obiettivo cambiano.

## Verifica

- `test/task_planning_view_test.dart`: viste, proiezione dello stato,
  riapertura, Sposta in Inbox con annullamento, flag Todoist.
- `test/task_views_test.dart`: ordinamento, Oggi, Prossime, mezzanotte.
- `test/civil_day_clock_test.dart`: un solo timer, recupero dopo sospensione.
- `test/sync_foreground_test.dart`: ricerca in SQLite, ordine, limite, `%`.
- `test/database_migration_test.dart`: migrazione 10 → 11 con trigger e indice.
