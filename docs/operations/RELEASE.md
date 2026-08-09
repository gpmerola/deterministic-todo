# Release coordinata Android e browser

## Prerequisiti

- versione `x.y.z+build` monotona in `pubspec.yaml`;
- branch `agent/**` autorizzato negli environment `android-release` e
  `github-pages`;
- secret Android e `RELEASE_REPO_TOKEN` configurati;
- working tree senza segreti o artefatti generati.

## Flusso canonico

1. Eseguire formatter, generazione Drift, analisi e test.
2. Aggiornare documentazione, stato e changelog quando pertinenti.
3. Commit e push del branch `agent/**`.
4. `Publish Android and Web Release` verifica una volta e avvia in parallelo
   bundle Play, APK diretti e Web.
5. Il bundle Play viene caricato nel track interno appena pronto, senza
   attendere gli APK o il deploy Web.
6. Chrome viene distribuito e controllato tramite `release-info.json`.
7. Solo dopo il successo web viene creata la release Android diretta `latest`.
8. Il job finale confronta versione, build e commit dei due endpoint pubblici;
   inoltre richiede tutti e quattro gli APK Android, con hash e URL appartenenti
   alla release corrente.

Output atteso: workflow verde, `release-info.json` raggiungibile, manifest
Android con gli stessi identificativi e quattro APK con SHA-256 (universale più
tre architetture).

## Fallimento e recovery

- Prima del deploy: nessun canale viene pubblicato; correggere e usare una nuova
  versione/build.
- Web fallisce: Android non viene pubblicato.
- Android fallisce dopo il web: incrementare versione/build e ripetere la
  pipeline senza riscrivere release già pubblicate.
- Non cancellare una release usata da dispositivi installati e non fare
  force-push.
