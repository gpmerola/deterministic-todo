# Web — modifiche dopo la chiusura completa di Chrome, build 270 e 271

## Riproduzione

```sh
python3 tools/build_web.py
node tools/web_persistence.mjs --rounds 3
```

`tools/web_persistence.mjs` usa lo stesso confine di
[web-startup](2026-10-13-web-startup.md): build release su `127.0.0.1`,
Chrome headless con un profilo temporaneo, nessuna richiesta esterna,
nessun account, solo attività sintetiche «Collaudo persistenza …». Il
server resta acceso tra i riavvii, quindi l'origine e lo storage del
profilo sono gli stessi.

Per ogni giro e ogni modifica: si creano le attività di partenza e un
controllo, si chiude Chrome normalmente dopo 2 s e lo si riapre; si fa la
modifica dall'interfaccia e, appena è visibile, si chiude Chrome per intero
con `Browser.close` (come Esci dal menu) oppure con SIGKILL (come un crash o
un'uscita forzata). Poi un nuovo Chrome sullo stesso profilo deve mostrare il
controllo e la modifica. Esiti grezzi: [JSONL](2026-10-13-web-persistence.jsonl).

## Esito

| Modifica | Chiusura normale | Chiusura forzata |
| --- | --- | --- |
| Nuova attività | 3 su 3 conservate | 3 su 3 conservate |
| Titolo modificato | 3 su 3 conservati | 3 su 3 conservati |
| Attività completata | 0 su 3 | 0 su 3 |

Il completamento si perde perché la riga mostra la spunta per 200 ms e si
chiude in 170 ms, e solo dopo l'app scrive su SQLite
(`_TaskTileState._setCompleted`). Chiudendo Chrome 300 ms dopo il tocco il
completamento si perde ancora; dopo 500 ms o 1 s è sempre conservato (un
giro per durata, entrambe le chiusure). Lo stesso ritardo esiste su Android
se l'app viene chiusa in quella frazione di secondo.

Una prova che anticipava la scrittura quando l'app viene nascosta o chiusa
(`AppLifecycleListener`) non ha cambiato l'esito con `Browser.close` e non è
stata tenuta.

## Correzione nella build 271

Il completamento si scrive al tocco; `CompletionHold` fa sì che le liste
(Oggi, Prossime, Progetti, ricerca) continuino a mostrare la riga com'era
fino alla fine dell'animazione, senza farla entrare in liste che non la
mostravano. Test: `test/completion_hold_test.dart` e il test widget che
verifica completamento già salvato a 50 ms con la riga ancora visibile,
spuntata e aperta, chiusa a 250 ms. Le immagini di riferimento della
Settimana sono invariate.

| Build 271, chiusura subito dopo il tocco | Chiusura normale | Chiusura forzata |
| --- | --- | --- |
| Nuova attività | 3 su 3 | 3 su 3 |
| Titolo modificato | 3 su 3 | 3 su 3 |
| Attività completata | 2 su 3 | 3 su 3 |
| Completata, chiusura dopo altri 50 ms | 3 su 3 | 3 su 3 |
| Completata, chiusura dopo altri 100 ms | 3 su 3 | 3 su 3 |

Il caso perso è stato chiuso circa 9 ms dopo il tocco, prima che la scrittura
finisse: è il tempo minimo di qualunque salvataggio, non più l'attesa
dell'animazione. Esiti grezzi nello stesso JSONL, con `build` ed
`extra_wait_ms`.
