# Preparazione backup — baseline host del 13 ottobre 2026

## Scopo e riproduzione

Punto 4 preparato, senza cambiare il percorso applicativo del backup. Comando:

```sh
make benchmark-backup
```

Richiede lo stesso Flutter/SQLite dei test del progetto. Il test
`test/backup_preparation_benchmark_test.dart` è escluso dalle prove ordinarie
senza `RUN_BACKUP_BENCHMARK=true`; durate e RSS non impongono soglie in CI.
Usa SQLite in memoria, 100/1.000/10.000 righe deterministiche, note ASCII di
1.000 byte ciascuna, tre campioni per taglia. Nessun database personale, chiave,
file Android o servizio remoto viene usato. Il processo termina e libera la
fixture; non modifica backup esistenti. In caso di errore, correggere il
prerequisito e rieseguire, senza recovery dei dati utente.

Misura il vero `AutoBackupService.backupNow`: query, JSON, codifica e hash,
con store sintetico al posto della cifratura/scrittura Android. Ogni campione
forza una scrittura nello store di prova. Verifica formato 2 e numero righe.
Emette JSON con taglia, campione, durata, payload, massimo intervallo fra
opportunità del timer da 1 ms e RSS prima/dopo. Il parsing di validazione è
fuori dal tempo misurato. Primo campione incluso, nessun warm-up escluso.

## Risultati iniziali

Esecuzione locale Mac, Flutter test/JIT, database in memoria. Durate in ms:

| Righe | Campione 1 | Campione 2 | Campione 3 | Payload byte |
| --- | ---: | ---: | ---: | ---: |
| 100 | 28,0 | 5,5 | 4,4 | 164.421 |
| 1.000 | 36,7 | 27,8 | 24,9 | 1.647.621 |
| 10.000 | 231,2 | 234,4 | 243,5 | 16.524.621 |

Il massimo intervallo del timer è quasi pari alla durata totale in questa
fixture: le query in memoria e la preparazione concatenano lavoro sincrono e
microtask. Questo è un indizio per approfondire la disponibilità dell'event
loop, **non** una misura dei frame Flutter sul telefono.

La RSS è quella dell'intero processo di test, influenzata da JIT, garbage
collection e fixture precedenti. Le coppie prima/dopo non rappresentano il
picco né la memoria attribuibile al solo backup; non ricavarne risparmi previsti.
Cifratura, canale nativo e storage Android non sono misurati.

## Passo successivo e criterio di scelta

1. Ripetere la preparazione in build profile/release sul Galaxy, su database
   esclusivamente sintetico e isolato; registrare tempi build/raster durante
   un'interazione ripetibile, senza attivare backup sui dati personali.
2. Se la preparazione coincide con frame lenti ripetibili, confrontare
   serializzazione/hash in isolate con il percorso attuale, includendo il
   costo di trasferimento/copia dei dati.
3. Verificare equivalenza JSON/formato 2, hash indipendente da `exported_at`,
   ripristino e comportamento in caso di errore prima di adottare la variante.

Non aggiungere dipendenze o cambiare formato/cifratura per questo benchmark.
Le misure host giustificano il collaudo del punto 1; non dimostrano da sole un
problema percepibile con l'archivio reale.
