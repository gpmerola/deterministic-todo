# Assistente AI: chiave API e regole sui dati

Dalla build 205 le Impostazioni Android hanno **Assistente AI**, dove salvare
la chiave API di un fornitore LLM: DeepSeek oppure Anthropic (Claude). Per ora
**nessuna funzione usa la chiave**. Questo documento fissa le regole che le
funzioni future dovranno rispettare.

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

## Regole per le funzioni future

- Nessuna richiesta automatica o in background: ogni invio parte da
  un'azione esplicita e mostra prima cosa verrà inviato.
- Gli eventi del calendario, che possono contenere dati clinici, non si
  inviano senza consenso esplicito per quella richiesta. Preferire titoli
  Todo scritti dall'utente.
- Prompt e risposte non si registrano nei log e non si sincronizzano.
- La scelta del fornitore conta per la privacy. DeepSeek elabora i dati in
  Cina secondo la propria informativa; Anthropic non usa per
  l'addestramento i dati inviati via API (impostazione predefinita). Da
  verificare sulle condizioni correnti prima di usare dati sensibili.
