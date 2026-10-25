# Tappe di comportamento per build

Paragrafi storici spostati dal [README](../../README.md) il 25 ottobre 2026,
senza modifiche ai contenuti. Il comportamento corrente è descritto nei
contratti collegati; la cronologia completa è in [CHANGELOG](../../CHANGELOG.md).

## Introduzione del README

Passi: dalla build 190 Android conserva solo il conteggio quotidiano dei passi
del telefono; GPS, Amazfit, Health Connect e diagnostica Movimento sono
[archiviati](../archive/MOVIMENTO.md) per ridurre peso e consumo di batteria.

Dalla build 172 la sincronizzazione applica solo i campi modificati e impedisce
che il cambio di giorno ripubblichi copie vecchie. **Impostazioni → Dati e
manutenzione → Storico attività** conserva 90 giorni di revisioni locali,
consultabili, esportabili e ripristinabili per singola attività. Architettura,
privacy e limiti: [sincronizzazione e storico](TODO_SYNC_AND_HISTORY.md).

La build 179 corregge una scansione remota incompleta causata dall'ordinamento
delle pagine e rende osservabili pagine, righe e conflitti. Diagnosi, test e
limiti: [paginazione sync](TODO_SYNC_PAGINATION.md).
Disponibilità effettiva Android/Web: [STATUS](../../STATUS.md).

La build 189 fa dipendere la pianificazione dalla sola data, definisce le viste
una sola volta in SQLite, rimuove `due_date` e il riconoscimento dell'Inbox per
nome: un vecchio progetto "Inbox" si converte con **Azioni progetto → Sposta in
Inbox**. Dettagli: [pianificazione e viste](TODO_PLANNING_MODEL.md).

La build 180 corregge il ripristino di attività dopo un invio incerto: la scelta
fatta nello storico supera gli intenti precedenti e conserva le modifiche
successive. Cronologia e ricevute restano protette; dettagli nel
[contratto di sincronizzazione](TODO_SYNC_AND_HISTORY.md).

## Todo: sincronizzazione

La sincronizzazione dalla build 177 confronta impronte delle versioni prima di
scaricare le attività; protocollo, compatibilità e recovery sono descritti in
[sincronizzazione compatta](TODO_SYNC_PERFORMANCE.md).

Dalla build 178 un controllo unificato evita le richieste delle tabelle invariate;
SQLite 10 conserva le impronte con invalidazione transazionale. Stato e collaudi
sono in [STATUS](../../STATUS.md).

## Avvio e caricamento

Dalla build 260 le attività locali sono disponibili prima dell’inizializzazione
della sincronizzazione; un errore remoto permette di riprovare senza chiudere
l’app. La ricerca eventi accorpa la digitazione e il calendario riusa gli
intervalli non modificati tramite notifiche del provider Android. Dettagli e
limiti in [avvio e caricamento](STARTUP_AND_CALENDAR_LOADING.md).

Dalla build 261 anche le viste Calendario limitano le pagine conservate in
memoria; le operazioni dopo l'avvio procedono indipendentemente. Il comando
`make benchmark-backup` misura la preparazione su sole fixture sintetiche:
[metodo e limiti](../diagnostics/2026-10-13-backup-preparation.md).
