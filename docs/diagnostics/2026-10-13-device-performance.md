# Galaxy S21 — misure del 13 ottobre 2026, build 263

## Riproduzione e confini

`python3 tools/device_performance.py --serial SERIAL` compila arm64 release
nel package separato `.dev.validation`, con `TODO_VALIDATION=true`. Il main
rifiuta altri package e non importa il bootstrap applicativo. Richiede Flutter,
Java 17, firma locale e ADB autorizzato; seguire [ADB](../operations/ADB_WIFI.md).
Lo script ripristina gli APK operativi dopo la build e non pubblica il harness.
Non avvia passi, calendari nativi, connessioni Supabase o backup personali.

Il database usa file temporanei sintetici con `NativeDatabase.createInBackground`,
come il confine SQLite nativo dell'app. Ogni taglia (100, 1.000, 10.000 attività,
note ASCII da 1.000 byte) ha tre campioni. Le directory create dal harness
sono rimosse alla fine; un'interruzione può lasciare soltanto fixture nella
cache del package di validazione. Il timeout dello script ferma quel package.
In caso di FAIL/deadline il run non è valido: controllare i prerequisiti e
ripetere, senza cancellare dati del package operativo.

Si misura `AutoBackupService.backupNow`, store di cattura in memoria al posto
di cifratura e I/O Android. Formato 2 e numero attività sono validati fuori
dalla finestra misurata. Nessuna ottimizzazione del backup è inclusa qui.

La vera `AgendaWeekView` rende 12 eventi sintetici al giorno (84/settimana).
Ogni campione alterna sei animazioni di pagina da 300 ms. Il backup inizia
100 ms dopo l'avvio della prima animazione. `FrameTiming` è filtrato per il
clock monotono buildStart e atteso per 1,2 s per ricevere i batch release.
Contiamo frame con durata **build oppure raster** oltre 16.667/8.334 µs,
non totalSpan: le fasi possono sovrapporsi. Queste soglie non attestano la
frequenza effettiva del display. Il timer da 10 ms misura il massimo intervallo
tra opportunità dell'event loop **solo durante la preparazione backup**;
comprende anche il rendering concorrente. Non è una misura diretta dei frame
persi: un blocco tra due frame può sfuggire alle durate build/raster.

Dati minimizzati, schema e SHA-256 del sorgente eseguito:
[misure JSON](2026-10-13-device-performance.json). Nessun titolo o nota reale,
identificatore dispositivo, credenziale o contenuto diagnostico privato.

## Preparazione backup durante scorrimento

| Attività | Durate dei tre campioni (ms) | Massimo intervallo event loop (ms) | Payload byte |
| --- | --- | --- | ---: |
| 100 | 28,8 / 24,9 / 27,2 | 13,1 / 19,6 / 19,5 | 163.221 |
| 1.000 | 187,5 / 168,3 / 151,5 | 95,3 / 102,7 / 81,9 | 1.635.621 |
| 10.000 | 1.403,0 / 1.427,0 / 1.410,6 | 760,8 / 756,3 / 746,2 | 16.404.621 |

La RSS prima/dopo è dell'intero processo, comprende UI, query, copie, garbage
collection e fixture precedenti; non è il picco o il costo esclusivo del backup.
Con 10.000 attività cresce di circa 59–139 MiB nei tre campioni, senza prova
che tale memoria resti occupata dopo il GC. Non confrontare direttamente con
il benchmark host in memoria/JIT: cambiano piattaforma, executor e UI concorrente.

## Scorrimento senza backup

| Campione | Frame | Build p95 / massimo (ms) | Raster p95 / massimo (ms) | Frame oltre 16,7 ms |
| --- | ---: | --- | --- | ---: |
| 1 | 95 | 41,4 / 69,7 | 9,3 / 14,9 | 6 |
| 2 | 80 | 79,4 / 104,9 | 13,2 / 19,4 | 7 |
| 3 | 72 | 77,0 / 128,2 | 13,1 / 32,7 | 7 |

Ci sono frame lenti anche senza backup, quindi non attribuire ogni scatto alla
serializzazione. Il carico è intenso e sintetico, su telefono non isolato da
altri processi e senza controllo termico: non equivale all'esperienza quotidiana.

## Decisione successiva

Aggiornamento build 269: la costruzione delle pagine dense è stata ridotta;
confronto nello stesso processo in
[calendar-week-build](2026-10-13-calendar-week-build.md).


Le pause dell'event loop a 10.000 righe motivano un confronto controllato della
preparazione in isolate, includendo trasferimento/copie, formato, hash e recovery.
Separatamente, profilare la costruzione delle pagine dense del calendario:
la baseline mostra già lavoro UI sopra budget. Nessun risparmio è dimostrato
finché non esiste un confronto prima/dopo a parità di fixture. Batteria non
misurata in questo run.


## Avvio dell'app operativa

Comando riproducibile: `python3 tools/device_startup.py --serial SERIAL`.
Chiudere prima gli editor non salvati. Il test ferma solo il processo Todo
Test per i campioni cold e usa Home per i warm; non cancella né legge il
contenuto del database. Android `am start -W`, dopo installazione in-place
2263 / 2.84.0-dev, restituisce `TotalTime` in ms:

| Condizione | Campione 1 | Campione 2 | Campione 3 |
| --- | ---: | ---: | ---: |
| Processo chiuso, cache OS non svuotata | 319 | 266 | 316 |
| Ritorno dall'Home, processo vivo | 54 | 63 | 56 |

Questi tempi misurano la visualizzazione dell'Activity secondo Android, non
il caricamento completo delle attività né la fine della sincronizzazione.
Non sono cold boot del telefono. Il primo frame Dart del harness separato
(138,8 ms) e il suo lancio Android non sono tempi di avvio dell'app completa.
Non esiste una baseline equivalente precedente: nessun guadagno attribuito
alle correzioni di questa build.
