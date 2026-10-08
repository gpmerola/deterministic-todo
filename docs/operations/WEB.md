# Browser

La web app pubblica è `https://gpmerola.github.io/deterministic-todo/`.

- SQLite usa OPFS/IndexedDB e deve sopravvivere a refresh e riapertura.
- La diagnostica usa un database IndexedDB separato e non contiene contenuto
  delle attività.
- Sotto 900 px la UI usa la navigazione Android; sopra 900 px usa una barra
  laterale compatta con le stesse tre sezioni.
- `release-info.json` identifica versione, build e commit pubblicati; non prova
  quale codice una scheda aperta stia eseguendo.
- Dalla build 247 UI, diagnostica e updater leggono versione/build incorporate
  nel JavaScript. Su Web non si usa `PackageInfo.fromPlatform()`, che scarica
  separatamente `version.json` e poteva attribuire la build nuova al codice
  vecchio nella cache.

## Build e cache

Dopo `flutter pub get`, usare `make build-web` (anche nelle due pipeline di
pubblicazione). `tools/build_web.py` legge `pubspec.yaml`, passa `TODO_VERSION`
e `TODO_BUILD` al compilatore e aggiunge SHA-256 agli URL di `main.dart.js`
e, successivamente, `flutter_bootstrap.js` nell'HTML. I percorsi restano
stabili con query `?v=hash`: anche un vecchio HTML in cache può ancora caricare
un asset esistente dopo il deploy. Le build dirette non configurate mostrano
`dev (unknown)` invece di prendere l'identità da un'altra release.
Il bootstrap resta quello generato da Flutter, secondo il
[contratto ufficiale](https://docs.flutter.dev/platform-integration/web/initialization).

L'HTML può restare nella cache HTTP fino alla sua scadenza: non è previsto
un aggiornamento forzato delle schede aperte. In caso di versione incoerente,
ricaricare ignorando la cache; non cancellare IndexedDB/OPFS, non fare logout
e non modificare a mano task o marker di riparazione.

## Incidente dell'8 ottobre 2026

Due schede dichiaravano build 246 ma il JavaScript realmente caricato non
conteneva `sync_repair:remote_nulls_v1`; l'asset corrente sul server lo
conteneva. `version.json`, letto con cachebuster dal plugin, mascherava il
codice obsoleto. Il refresh senza cache ha caricato il bundle corretto:
un ciclo ha scaricato 599 task, senza conflitti o outbox residua; i cicli dopo
ulteriori refresh hanno scaricato zero righe. La task segnalata ha perso data
e ripetizione obsolete. Nessuna modifica manuale al database o al server.

## Collaudo

Smoke test: aprire il sito non in incognito, creare una task sentinella,
aggiornare la pagina, verificare persistenza e sincronizzazione bidirezionale con
Android. Se il bootstrap rileva soltanto storage volatile deve fallire in modo
esplicito.

Per provare import ed export senza dati personali, usare una fixture sintetica
creata nell'app: esportare il JSON, rinominare la task sentinella, importare in
modalità aggiornamento e verificare anteprima, conteggi e ripristino. Chiudere
completamente la scheda, riaprire lo stesso URL e riesportare. Il collaudo è
superato soltanto se task e diagnostica persistono dopo la riapertura; i test
Flutter verificano la logica ma non sostituiscono questa prova sul profilo
Chrome reale.

Dalla build 172, ripetere il refresh anche dopo una **modifica** a un'attività
già salvata, non solo dopo la creazione. Aprire lo storico della singola task e
verificare che rimangano sia il nuovo valore sia la revisione prima/dopo; quindi
chiudere la scheda e riaprire lo stesso URL. Il fix della barriera IndexedDB è
documentato in [sincronizzazione e storico](../architecture/TODO_SYNC_AND_HISTORY.md#persistenza-web--build-172).
