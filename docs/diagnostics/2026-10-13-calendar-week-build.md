# Galaxy S21 — costruzione della vista Settimana, build 269 e 270

## Esito finale

La build 269 disegnava ogni evento in un solo elemento ed era più veloce
(misure sotto), ma l'utente ha visto la Settimana diversa: titoli andati a
capo e tagliati in altri punti, nessuna increspatura al tocco. Causa
principale: la 268 sceglie gli a capo misurando le parole con uno stile
senza le impostazioni del tema (per esempio la spaziatura delle lettere di
`bodyMedium`) e poi le disegna con quelle; la 269 misurava e disegnava con lo
stesso stile completo, quindi spezzava diversamente. La build 270 ripristina
il codice della 268 senza modifiche e aggiunge quattro immagini di
riferimento (`test/agenda_week_golden_test.dart`), verificate identiche pixel
per pixel alla 268. Una prova intermedia con il solo disegno delle linee
orarie in un elemento per colonna era identica ai pixel ma non ha mostrato
guadagni (una coppia di campioni: 99,1 contro 96,5 ms prima del blocco del
telefono), quindi non è stata tenuta.

Le misure e le analisi qui sotto restano valide come base per un nuovo
tentativo, che deve passare le immagini di riferimento senza aggiornarle.

## Riproduzione

`python3 tools/device_performance.py --serial SERIAL --scenario calendar`
compila il harness arm64 release nel package separato `.dev.validation`, come
in [device-performance](2026-10-13-device-performance.md): solo fixture
sintetiche, nessun accesso al database operativo, ai calendari di sistema o
alla rete. La fixture è la stessa della baseline: 12 eventi di 45 minuti al
giorno dalle 7 alle 18, 84 per settimana, titoli «Synthetic event N».

Per queste misure lo scenario alternava nello **stesso processo** la vista
della build 267 (una copia esatta usata solo dal harness, tolta nella 270) e
quella della 269: sei campioni ciascuna, con vista e controller
nuovi e un passaggio non misurato che carica le due pagine. Ogni campione
misura sei cambi di pagina animati da 300 ms. Le metriche sono quelle della
baseline (`FrameTiming`, durata build oppure raster).

Il confronto nello stesso processo serve perché i run separati non sono
confrontabili: durante questa sessione il telefono era in carica rapida, a
circa 43 °C di batteria, con stato termico Android 3. In queste condizioni
anche la vista della build 267 misura circa 100 ms, contro i 41–79 ms della
baseline di stamattina a freddo. Esiti grezzi:
[JSONL](2026-10-13-calendar-week-build.jsonl).

## Misure della 269

| Vista | Build p95 per campione (ms) | Mediana | Frame in 1,8 s | Frame oltre 16,7 ms |
| --- | --- | ---: | --- | --- |
| Build 267 | 98,6 / 118,1 / 91,6 / 104,1 / 129,9 / 101,7 | 102,9 | 56–69 | 7–11 |
| Build 269 | 41,8 / 41,2 / 37,5 / 43,2 / 44,2 / 41,1 | 41,5 | 94–97 | 7–11 |

Il fotogramma del cambio pagina costa circa il 60% in meno e il telefono
mostra circa il 50% di fotogrammi in più nella stessa finestra. Ogni cambio
di pagina resta però sopra i 16,7 ms: il numero di frame lenti non scende.
Raster p95 invariato (12–20 ms in entrambe). A freddo i valori assoluti
saranno più bassi; il rapporto a freddo non è stato misurato.

## Dove andava il tempo

Prove nello stesso processo con interruttori temporanei, non inclusi nel
codice consegnato:

- senza alcun testo nei blocchi la pagina costa circa 10 ms: il resto era
  quasi tutto impaginazione del testo;
- l'a capo tra le parole (`wrapWords`) misurava ogni riga candidata e poi
  impaginava ogni riga: circa cinque misure per evento;
- un paragrafo unico controllato con `getLineBoundary` ricadeva sempre sul
  percorso lento: in questa fixture ogni titolo contiene una parola più
  larga della colonna («Synthetic» supera i circa 47 px disponibili);
- una riga unica misurata con `getOffsetForCaret` era più lenta di
  `wrapWords`; con `getBoxesForSelection` e `getPositionForOffset` è più
  veloce.

## Modifiche della 269, ritirate nella 270

- `AgendaWeekEventBlock`: un `CustomPaint` con `GestureDetector` e
  `Semantics` al posto di Material, InkWell, due LayoutBuilder e un Text per
  riga. Stesso aspetto e stesse soglie; si perde l'effetto increspatura al
  tocco.
- Titolo impaginato una volta su una riga sola; i bordi delle parole danno
  gli stessi a capo di `wrapWords`, che resta per testo da destra a sinistra
  e spazi irregolari. Era equivalente a `wrapWords` con lo stesso stile, ma
  non a ciò che la 268 mostra davvero (vedi sopra).
- Orari e «…» impaginati una volta per testo e stile e condivisi. Gli orari
  della fixture si ripetono ogni giorno, come spesso nei calendari reali:
  il guadagno di questa parte è un limite superiore.
- Linee orarie e notte compressa disegnate da un `CustomPaint` per colonna
  invece di circa 30 widget per colonna.

## Limiti

Misurata solo la vista a sette colonne con questa fixture. Batteria non
misurata. Nella 270 `--scenario calendar` misura solo lo scorrimento, senza
la copia della 267: run separati vanno confrontati solo a parità di stato
termico.
