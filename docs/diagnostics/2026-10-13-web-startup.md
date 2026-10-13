# Web — tempo alla prima schermata, build 270

## Riproduzione

```sh
python3 tools/build_web.py
node tools/web_startup.mjs --runs 7
node tools/web_startup.mjs --runs 7 --network fast4g
```

`tools/web_startup.mjs` serve `build/web` su `127.0.0.1` come GitHub Pages
(gzip, ETag, `max-age=600`) e apre Chrome headless con un profilo temporaneo
nuovo per ogni campione, cancellato alla fine. Le richieste CanvasKit a
gstatic sono reindirizzate alla copia nella build, servita dallo stesso
server; ogni altra richiesta esterna (Supabase, Google Fonts, GitHub) è
rifiutata. Nessun account, nessun dato reale: il database SQLite del
profilo di prova è vuoto. Chrome 155, Flutter 3.44.7, Mac della macchina di
collaudo.

Misure per campione: `cold` è la prima apertura del profilo, `warm` la
ricarica nello stesso profilo (cache HTTP e codice, database già creato).
`first_frame_ms` è l'evento `flutter-first-frame` (indicatore di
caricamento); `today_ms` è il momento in cui la vista Oggi compare
nell'albero di accessibilità, attivato dal probe. `fast4g` è il profilo
«Fast 4G» di DevTools (9 Mbit/s, 150 ms). Esiti grezzi:
[JSONL](2026-10-13-web-startup.jsonl).

## Esito

| Condizione | Oggi, mediana di 7 (ms) | Intervallo |
| --- | ---: | --- |
| Loopback, prima apertura | 411 | 407–650 |
| Loopback, ricarica | 204 | 202–221 |
| Fast 4G, prima apertura | 4.212 | 4.202–4.222 |
| Fast 4G, ricarica | 206 | 203–222 |

Con Fast 4G il tempo è quasi tutto trasferimento: `main.dart.js` finisce a
circa 3,1 s e `canvaskit.wasm` a circa 3,9 s, scaricati in parallelo.
Byte compressi: CanvasKit (variante Chromium) 2,19 MB, `main.dart.js`
1,33 MB, `sqlite3.wasm` 0,36 MB, `drift_worker.js` 0,11 MB. Nella source map
di `main.dart.js` il codice dell'app è una parte piccola: framework Flutter,
SDK Dart e `flutter_localizations` (tutte le lingue) prevalgono.

## Caricamento differito

Prova: `agenda_view.dart` importato `deferred`. `main.dart.js` scende di
97 KB (32 KB compressi, nella parte separata).

| Condizione | Prima | Differito |
| --- | ---: | ---: |
| Loopback, prima apertura | 411 | 417 |
| Fast 4G, prima apertura | 4.212 | 4.189 |

Circa 23 ms su 4,2 s con Fast 4G, nessuna differenza in loopback: non
applicato. Impostazioni, editor e altre schermate sono ancora più piccole e
Impostazioni è una `part` di `main.dart`; il differimento non è stato
esteso. Avviare il Calendario dopo un caricamento aggiuntivo avrebbe anche
un costo alla prima apertura della sezione.

## Possibili passi, non misurati

- Solo l'italiano nelle localizzazioni Flutter invece di tutte le lingue:
  meno byte in `main.dart.js`; richiede delegate e dati data/ora propri.
- Build WebAssembly (skwasm): motore e codice diversi, da verificare con
  Drift e con il fallback quando il browser non lo supporta.

Nessuno dei due è stato provato; servono misure prima di proporli.
