# Assistente AI: chiave API e regole sui dati

Dalla build 205 le Impostazioni Android hanno **Assistente AI**, dove salvare
la chiave API di un fornitore LLM: DeepSeek, scelto dall'utente, oppure
Anthropic (Claude). Dalla build 206 la usa una sola funzione, **✨ Scrivi o
detta**. L'utente ha dichiarato che i suoi calendari non contengono dati di
pazienti e ha accettato l'invio a DeepSeek.

## ✨ Scrivi o detta (build 206)

Pulsante ✨ nella barra in alto (Oggi, Prossime, Progetti) e nella riga
dell'Agenda. Si scrive o si detta, con il microfono della tastiera, una nota
come «preparare slide per la riunione TNG di giovedì; visita Maudsley martedì
15–16». **Interpreta** invia una sola richiesta:

- DeepSeek: `POST https://api.deepseek.com/chat/completions`, modello
  `deepseek-flash`, `response_format: json_object`. Dalla build 207 anche
  `thinking: disabled` e `max_tokens: 4096`. Il ragionamento è attivo di
  default e nella prova reale della 206 esauriva i token sulle note con due
  richieste, troncando il json. `finish_reason: length` (`stop_reason:
  max_tokens` per Claude) mostra un messaggio dedicato: «dividi la nota»;
- Claude: `POST https://api.anthropic.com/v1/messages`, modello
  `claude-haiku-4-5`.

Timeout 45 secondi, nessun registro di prompt e risposte.

Contenuto inviato (`aiCaptureUserPrompt`):

- data e ora correnti e fuso IANA;
- nomi dei progetti non archiviati;
- nomi dei calendari scrivibili mostrati nell'Agenda;
- titoli e orari degli eventi dei prossimi 14 giorni nei calendari mostrati,
  con i filtri applicati, al massimo 80;
- la nota.

Gli elementi sono numerati (`P1`, `C1`, `E1`), così la risposta li cita senza
copiare nomi o identificativi.

La risposta json viene validata (`parseAiCapture`). Si scartano, contandoli,
gli elementi:

- senza titolo;
- con date illeggibili, la fine prima dell'inizio, o più di un giorno nel
  passato o più di tre anni nel futuro;
- di tipo sconosciuto.

Un progetto sconosciuto diventa «nessun progetto», un calendario sconosciuto
diventa quello predefinito. Il predefinito si sceglie in Agenda › Calendari ›
«Nuovi eventi in» (build 207); vale anche per il **+**. Al massimo 10 elementi. Le attività hanno solo
la data; gli eventi durano 60 minuti se manca la fine.

Nella revisione ogni proposta si può deselezionare o modificare: titolo e
data per le attività, il modulo evento precompilato per gli eventi. **Crea**
scrive solo quelle selezionate:

- le **attività** con `TaskRepository.create`. Quelle con data sono segnate
  «Mostra in agenda» (flag locale), così compaiono subito nel calendario;
- gli **eventi** nel calendario scelto, con il fuso del sistema.

**Marcatore.** Ogni elemento creato ha il titolo che inizia con «✨ »
(`aiMarker`) e note che finiscono con «Creato con l'assistente AI di Todo.».
Se c'è un evento collegato, le note riportano anche «Collegata a: <evento>».
Il marcatore si vede in Todo, sul Web e in Google o Outlook. Per eliminare
gli elementi o abbandonare la funzione basta cercare «✨».

## Conservazione della chiave

- La chiave e il fornitore scelto stanno in `flutter_secure_storage`, cioè
  nell'Android Keystore (`ai_api_key`, `ai_provider`).
- Non vanno mai in SQLite, nei backup JSON/CSV, nei log diagnostici, in
  Supabase o nel repository.
- Dopo il salvataggio l'interfaccia mostra solo le ultime quattro cifre
  (`AiSettings.mask`).
- **Elimina chiave** chiede conferma e la cancella dal telefono. Per revocarla
  del tutto va eliminata anche dalla console del fornitore.
- Non è disponibile sul Web: nel browser non esiste un archivio
  equivalente al Keystore.

## Verifica

**Verifica e salva** fa una sola `GET` dell'elenco modelli del fornitore:
`https://api.deepseek.com/models` con `Authorization: Bearer`, oppure
`https://api.anthropic.com/v1/models` con `x-api-key` e
`anthropic-version: 2023-06-01`. Timeout di 10 secondi. Non viene inviato
nessun contenuto (attività, eventi, testo). Esiti:

- 200: valida e salvata;
- 401/403: rifiutata e **non** salvata;
- altro o errore di rete: salvata con l'avviso che la verifica non è riuscita.

Gli errori non vengono registrati, perché la chiave è negli header.

## Regole per le funzioni

- Nessuna richiesta automatica o in background: ogni invio parte da
  un'azione esplicita, e la pagina dice cosa verrà inviato.
- Nulla si crea senza la conferma della revisione.
- Prompt e risposte non si registrano nei log e non si sincronizzano.
- La scelta del fornitore conta per la privacy. DeepSeek elabora i dati in
  Cina secondo la propria informativa; Anthropic non usa per
  l'addestramento i dati inviati via API (impostazione predefinita). Da
  verificare sulle condizioni correnti prima di usare dati sensibili.
