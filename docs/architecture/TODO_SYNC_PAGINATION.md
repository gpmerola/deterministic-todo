# Paginazione e divergenza Android–Web — build 179

## Riscontro del 12 settembre 2026

Il confronto visivo autorizzato mostrava una ricorrenza ancora in Oggi sul Web
174 e nessuna attività in Oggi su Todo Test 178. Lo storico Web della singola
attività terminava il giorno precedente. Non sono stati modificati dati per
la diagnosi; il telefono ha perso ADB prima della lettura del suo storico.
Non è quindi ricostruita l'operazione Android precisa (completamento, cambio data
o altra modifica). Nessun titolo, UUID personale o snapshot è conservato qui.

Il giornale Web registrava controlli da 20.100 righe task scaricate, con durate
fra circa 51 e 145 secondi. L'ispezione delle richieste reali di progetti e sezioni
ha mostrato `order=id.desc.nullslast` insieme a `id=gt.<cursor>`.
Nel codice canonico tutte queste letture, incluse le task, condividono
`remotePages`. Il metodo SDK `order('id')` ha `ascending = false` come default.

Il cursore crescente era quindi incompatibile con l'ordine effettivo: una prima
pagina da 200 righe veniva seguita da 199, 198, …, 1 righe già lette, poi dalla
pagina vuota. Il totale 20.100 è `200 × 201 / 2`, non 20.100 task distinte.
Le righe con ID inferiore alla prima pagina non venivano raggiunte. La guardia
sul solo ultimo ID non rilevava il difetto, perché gli ultimi ID crescevano.
Un client poteva dichiarare successo senza avere completato la scansione.

Anche la build 178 conteneva lo stesso difetto, ma scaricava gruppi di UUID
più piccoli e usava pagine da 500: il diverso protocollo può spiegare perché
i client raggiungessero insiemi diversi. Non implica che Android fosse immune.
L'errore di rete Android delle 15:14:32 Europe/Rome, recuperato alle 15:14:36,
è un evento distinto: non dimostra da solo la causa della singola differenza.

## Correzione e prevenzione

- Ordinamento esplicitamente crescente, coerente con il filtro `gt`.
- Validazione di ogni ID prima di consegnare una pagina al merge: ordine
  strettamente crescente anche rispetto alla pagina precedente e appartenenza
  al gruppo richiesto. Pagine duplicate, invertite o fuori gruppo falliscono
  con errore `pagination`, senza applicare la pagina invalida o dichiarare
  riuscita la scansione. Le pagine precedenti valide restano conservate.
- Nessun limite massimo di pagine o arresto su pagina corta: un limite server
  inferiore resta supportato. La pagina vuota conclude la scansione.
- I server sintetici Dart e HTTP rispettano ora l'ordine richiesto. Prima
  ordinavano sempre in senso crescente e nascondevano il bug del client.

Schema SQLite, RPC server, dipendenze, politiche CAS e dati Movimento invariati.
Le normali letture successive dei client aggiornati possono recuperare le
versioni remote prima saltate; non vengono forzati ripristini o modifiche locali.
Questo controllo verifica la scansione, non certifica da solo identità dei
contenuti con versioni uguali, né uno snapshot distribuito fra client concorrenti.

## Diagnostica

`sync_started`, `sync_completed` e `sync_failed` distinguono il controllo completo
(`pull_all`) dal solo invio. Avanzamento, successo e fallimento conservano
`pull_pages` (incluse pagine vuote), `pulled_rows` (tutte le tabelle paginate) e
`pull_table` (ultima tabella letta). `remote_rows` resta il solo download task;
le impronte non sono righe scaricate. La fase `overview` distingue la RPC iniziale
dalla lettura progetti. La classe `pagination` non produce retry automatici rapidi.

Il campo `conflicts`, già prodotto dal servizio ma scartato dal filtro del log,
è ora conservato. Il provider ADB espone conteggio conflitti, tipo di controllo,
pagine e righe dell'ultimo successo; tabella, pagine e righe dell'ultimo errore.
Lo stato aggregato del provider resta una cronologia di esiti, non una prova
di convergenza: leggere insieme `last_success_conflicts`, coda e timestamp.
I campi nuovi mancanti nei log vecchi sono null, non zero.
Nessun ID, cursore, titolo, nota, token o URL viene aggiunto alla diagnostica.

Il collaudo offline della build Web release ha inoltre mostrato un errore
`minified:*`: il riconoscimento basato su `runtimeType.toString()` non identificava
il trasporto dopo la minificazione dart2js e poteva omettere il retry. La 179
riconosce `http.ClientException`, `TimeoutException` e `AuthRetryableFetchException`
per tipo, con etichette diagnostiche stabili e senza messaggi dell'eccezione.
Questo secondo difetto è riprodotto in ambiente sintetico; non è attribuito
automaticamente all'evento reale, il cui log Web non registra un `sync_failed`.

## Verifica e distribuzione

Rendendo realistico il server sintetico, il test esistente con 1.501 task e
limite server 73 fallisce sul vecchio client: soltanto 73 task locali, pur con
esito current. Il client corretto recupera l'intero insieme.

`remote_pagination_test.dart` verifica 426 UUID una volta sola in tre pagine
non vuote più una vuota, e rifiuto di inversioni, sovrapposizioni e gruppi errati.
`sync_hardening_test.dart` confronta due client, interrompe la lettura e verifica
il recupero di un completamento su un UUID basso. Il test di export controlla
che i contatori sopravvivano al filtro senza includere contenuti privati.
Il test HTTP Python verifica separatamente ordine crescente e decrescente.
`sync_error_classification_test.dart` verifica il recupero anche quando il nome
runtime non contiene più informazioni sul trasporto.

Comandi: `make check`, `make check-generated`, build Web release e `make todo-test`.
Esiti e blocchi di distribuzione sono in [STATUS](../../STATUS.md).
Per proteggere entrambi i client occorre distribuire anche il Web e ricaricare
le schede precedenti. La pubblicazione stabile richiede conferma `PUBBLICA`;
il push Todo Test non aggiorna il Web. Non cancellare lo storage del browser.
