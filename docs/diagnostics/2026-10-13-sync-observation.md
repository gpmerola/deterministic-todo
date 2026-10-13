# Osservazione tecnica sul Galaxy — 13 ottobre 2026

Lettura in sola lettura tramite `todo_sync_debug/status`, prima di installare
la build 262, senza forzare un ciclo né accedere a titoli o payload. Ultimo
successo registrato dalla build **2261** alle **00:45:30 BST del 13 ottobre**
(`2026-10-12T23:45:30.321125Z`):

| Misura | Valore |
| --- | ---: |
| Durata totale | 203 ms |
| Tempo rete | 194 ms |
| Confronto locale | 4 ms |
| Richieste | 1 |
| Righe remote ricevute | 0 |
| Intenti pendenti | 0 |
| Conflitti | 0 |

Lo stato `recovered` conserva la memoria di un problema precedente, non
significa che questo ciclo sia fallito. Questo campione mostra un controllo
invariato con una sola richiesta e costo locale ridotto; non è una distribuzione
di latenze né dimostra un miglioramento rispetto a un'altra build.

Il provider accessibile espone lo stato sync, non i campioni frame/RAM, né
il tempo di preparazione backup. Non è stata eseguita una nuova prova di
batteria e non sono stati esportati log privati completi. La baseline host del
[backup](2026-10-13-backup-preparation.md) resta separata: non giustifica ancora
l'introduzione di isolate o modifiche alla cifratura sul telefono.
