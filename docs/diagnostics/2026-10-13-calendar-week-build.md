# Galaxy S21 — costruzione della vista Settimana, build 269

## Riproduzione

`python3 tools/device_performance.py --serial SERIAL --scenario calendar`
compila il harness arm64 release nel package separato `.dev.validation`, come
in [device-performance](2026-10-13-device-performance.md): solo fixture
sintetiche, nessun accesso al database operativo, ai calendari di sistema o
alla rete. La fixture è la stessa della baseline: 12 eventi di 45 minuti al
giorno dalle 7 alle 18, 84 per settimana, titoli «Synthetic event N».

Lo scenario alterna nello **stesso processo** la vista della build 267
(`integration_test/legacy/agenda_week_view_b267.dart`, copia esatta usata solo
dal harness) e quella attuale: sei campioni ciascuna, con vista e controller
nuovi e un passaggio non misurato che carica le due pagine. Ogni campione
misura sei cambi di pagina animati da 300 ms. Le metriche sono quelle della
baseline (`FrameTiming`, durata build oppure raster).

Il confronto nello stesso processo serve perché i run separati non sono
confrontabili: durante questa sessione il telefono era in carica rapida, a
circa 43 °C di batteria, con stato termico Android 3. In queste condizioni
anche la vista della build 267 misura circa 100 ms, contro i 41–79 ms della
baseline di stamattina a freddo. Esiti grezzi:
[JSONL](2026-10-13-calendar-week-build.jsonl).

## Esito

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

## Modifiche

- `AgendaWeekEventBlock`: un `CustomPaint` con `GestureDetector` e
  `Semantics` al posto di Material, InkWell, due LayoutBuilder e un Text per
  riga. Stesso aspetto e stesse soglie; si perde l'effetto increspatura al
  tocco.
- Titolo impaginato una volta su una riga sola; i bordi delle parole danno
  gli stessi a capo di `wrapWords`, che resta per testo da destra a sinistra
  e spazi irregolari. Test di equivalenza in
  `test/agenda_week_block_test.dart`.
- Orari e «…» impaginati una volta per testo e stile e condivisi. Gli orari
  della fixture si ripetono ogni giorno, come spesso nei calendari reali:
  il guadagno di questa parte è un limite superiore.
- Linee orarie e notte compressa disegnate da un `CustomPaint` per colonna
  invece di circa 30 widget per colonna.

## Limiti

Misurata solo la vista a sette colonne con questa fixture. Tre giorni usa lo
stesso codice ma non è stata misurata; Mese, 2 settimane e Giorno non sono
cambiati. Batteria non misurata.
