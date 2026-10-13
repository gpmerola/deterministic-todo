# Sessioni amministrative (sperimentale) — build 264

Funzione opzionale per il protocollo personale «Sessioni amministrative»: un
compito burocratico non urgente non si risolve quando compare, si cattura e si
rimanda alla prossima sessione amministrativa settimanale.

## Interruttore

**Impostazioni → Sessioni amministrative (sperimentale)**, in fondo alla lista,
spento di default. Spento, l'app è identica alla build 263: nessuna sezione,
nessun blocco nel Calendario, nessuna voce nei menu delle attività, nessuna
scrittura (la sola lettura all'avvio è una riga di `app_settings`).
Spegnerlo nasconde la funzione e lascia ogni attività, progetto e sezione
dov'è.

## Struttura dei dati

Nessuna migrazione SQLite o Supabase.

| Elemento | Dove vive | Sincronizzato |
| --- | --- | --- |
| Progetto «Amministrazione» e cinque sezioni | `projects`, `project_sections` con ID UUID v5 fissi (`adminProjectId`, `adminSectionId`) e `external_source = 'admin'` | sì, come ogni progetto |
| Attività in coda | righe normali di quel progetto | sì |
| Slot assegnato | `show_date` dell'attività (solo la data, come sempre) | sì |
| In attesa con data di controllo | `status = 'waiting'` + `show_date` + sezione «In attesa» | sì |
| Origine | `external_source = 'admin:<codice>'` (`gmail_opuk`, `semble`, `kcl`, `personale`, `altro`) | sì |
| ID esterno | `external_id`, unico per origine (indice locale e Supabase già esistenti) | sì |
| Serie degli slot, occorrenze spostate o saltate, sessioni chiuse, stima minuti | `app_settings` chiave `admin_sessions_v1` | **no**, solo dispositivo |

Gli ID fissi rendono idempotente l'attivazione: accendere la funzione sul
telefono e sul Web crea lo stesso progetto, che la sync unisce. Le sezioni
rinominate dall'utente conservano il nome. Le attività importate da Todoist
mantengono `external_source = 'todoist'`: l'origine non è modificabile per non
rompere la deduplicazione del reimport.

Sottosezioni: Inbox amministrativa (da classificare), Clinica privata (Semble,
Online Psychiatry UK), Finanza e burocrazia (tasse, ENPAM, bollette, rimborsi,
commercialista), Carriera e compliance (GMC, SLaM, KCL, training, contratti),
In attesa (bloccate da una risposta esterna). Privacy: titoli generici, nessun
nome di paziente o dettaglio clinico.

## Slot

Tre serie predefinite, modificabili: A lunedì 16:00 per 40 minuti, B mercoledì
16:00 per 40 minuti, C domenica 17:30 per 55 minuti. Una serie è giorno della
settimana + minuti locali + durata, nel fuso del dispositivo: il cambio di ora
legale non sposta l'orario a parete. Un'occorrenza si identifica con
`serie@data originale` e può essere spostata (giorno, ora, durata) o saltata
senza toccare la serie. Cambiare una serie azzera le sue occorrenze future
spostate o saltate, che si riferivano al vecchio orario; quelle passate restano.

Le regole pure sono in `lib/domain/admin_sessions.dart`:

- `adminSlotsBetween`: slot dei giorni richiesti, comprese le occorrenze
  spostate dentro l'intervallo da fuori, escluse quelle saltate o spostate
  fuori.
- `nextAdminSlot`: primo slot che inizia **dopo** l'istante corrente (una
  sessione già iniziata non è «la prossima»), oppure il primo dopo una data
  occorrenza; orizzonte di 10 settimane.
- `adminDeferTarget`: un'attività con data successiva a oggi ma precedente al
  prossimo slot conserva la sua data (regola del protocollo); senza data, con
  data odierna, arretrata o successiva allo slot prende la data dello slot.
- `adminSessionResidue`: residuo di una sessione = attività aperte, non in
  attesa, con data uguale o precedente al giorno della sessione. Restano
  escluse quelle senza data (da classificare) e quelle con data successiva.

Nessuna attività viene mai spostata implicitamente: solo azioni esplicite, con
Annulla. La burocrazia non viene mai collocata fuori dagli slot configurati.

## Interfaccia

- **Admin** nella barra di navigazione: intestazione con prossimo slot,
  conteggio della coda con tempo stimato (attività × minuti stimati, solo
  informativo, nessun obiettivo), «Chiudi sessione» e «Modifica slot»; poi le
  cinque sottosezioni con il loro contenuto e un + ciascuna. Il + flottante
  crea nell'Inbox amministrativa.
- **Rimanda al prossimo slot**: scorrimento verso destra su qualunque attività
  aperta, oppure voce del menu (pressione prolungata, ⋮, clic destro). Porta
  l'attività nella coda (Inbox amministrativa se proveniva da altrove o da In
  attesa) e le assegna la data dello slot; snackbar con Annulla.
- **In attesa fino a…** e **Origine e ID…** nello stesso menu.
- **Chiudi sessione** (intestazione o blocco nel Calendario): il residuo passa
  allo slot successivo, che tiene conto di spostamenti e salti; le attività in
  attesa conservano la data di controllo. Annulla ripristina le date.
- **Calendario**: gli slot sono blocchi orari color ocra (calendario interno
  `todo-admin`), non eventi Android o Google. Toccandoli: sposta solo questa
  volta, salta questa volta, ripristina come da serie, cambia tutte le
  settimane, chiudi sessione. Spostando o saltando uno slot con attività
  previste l'app chiede se spostarle insieme.
- I blocchi entrano solo nelle viste del Calendario (`AgendaView`): mirror Web,
  backup Agenda, promemoria, visite urgenti, stima lavoro privato e ricerca non
  li vedono.

## Web

Funziona anche sul Web: stessa sezione, stessi menu, configurazione degli slot
salvata nel database locale del browser. Gli slot appaiono nel Calendario Web
quando questo è disponibile (sync configurata). Limite: la configurazione degli
slot non è sincronizzata, va impostata su ogni dispositivo.

## Fuori da questo incremento

Integrazione automatica Gmail OPUK e Semble (richiede OAuth e decisioni
privacy), sincronizzazione della configurazione slot. Vedi `TODO_NEXT.md`.

## Verifica

- `test/admin_sessions_test.dart`: slot, prossimo slot con occorrenze spostate
  e saltate, ora legale (25 ottobre 2026 e 28 marzo 2027), scadenze prima dello
  slot, residuo, codifica della configurazione. Eseguito anche con
  `TZ=Europe/London` e `TZ=America/New_York`.
- `test/admin_sessions_service_test.dart`: attivazione idempotente, rimanda con
  annulla, chiudi sessione, sposta e salta con attività, attesa, origine unica,
  attività Todoist protette.
- `test/admin_sessions_ui_test.dart`: app invariata da spenta, attivazione da
  Impostazioni, rimanda da menu e con scorrimento, vista Admin, blocco del
  Calendario che apre lo slot.
- Web: build release `tools/build_web.py` riuscita. Avvio e persistenza dopo
  refresh non verificati: nell'ambiente di sviluppo il server locale non offre
  storage persistente a nessuna build (anche la 263 mostra «Impossibile aprire
  i dati locali»); la verifica sul sito pubblico richiede una release stabile.
