# Diagnostica intensiva Movimento

## Scopo e durata

È un esperimento temporaneo di osservabilità, non l'architettura energetica
finale. Dura sette giorni da un istante assoluto e può attraversare build
intermedie senza ripartire. `experiment_id` identifica l'intera raccolta;
`segment_id`, versione e build delimitano ogni riavvio o aggiornamento.

## Flusso canonico

`sensori/GPS -> finestre locali append-only -> checkpoint immutabile -> Drive`

`IntensiveDiagnosticService` campiona GPS, accelerometro, giroscopio,
barometro e sensori passi. Ogni cinque secondi salva statistiche aggregate,
attività riconosciuta, qualità/velocità GPS e costo CPU, rete, heap, batteria e
power-save. Non salva coordinate. `PassiveMovementAuditWorker` chiude il blocco
attivo ogni ora, ne apre subito la continuazione e carica fino a otto blocchi
pendenti. Un blocco locale viene eliminato soltanto dopo successo Drive.
Quando il servizio termina viene pianificato anche un job finale vincolato alla
rete; viene eseguito prima del controllo di scadenza del test passivo.

Dalla build 135 ogni finestra dichiara durata reale, durata attesa e ritardo.
Se fra l’ultima finestra persistita e un riavvio passano più di 15 secondi, o
una singola finestra supera tale soglia, viene scritto un evento
`coverage_gap` con inizio, fine, durata, causa e numero stimato di finestre
mancanti. Conteggio, massimo e ultimo gap sono persistiti anche nel provider
ADB; il watchdog rende il buco osservabile, ma non pretende di ricostruire
campioni che Android non ha consegnato.

## Privacy e limiti

Sono vietati coordinate, percorsi ricostruibili, identificatori dei record
Health Connect e contenuti Todo. La distanza grezza tra fix e le distribuzioni
dei sensori sono dati derivati. Il foreground service e la notifica sono
obbligatori; consumo e calore saranno intenzionalmente superiori alla versione
finale. Il test passivo resta una baseline indipendente a basso consumo.

## Aggiornamenti e recovery

Installare una build intermedia non cambia `experiment_id` né `end_at_ms`.
Aprire l'app una volta dopo l'update riavvia il servizio e crea un nuovo
segmento. Se Drive è temporaneamente offline, i `.jsonl` completati restano
nello storage privato e vengono ritentati al job successivo. Il pulsante o
l'azione **Termina** della notifica cancellano la scadenza e chiudono il blocco;
la scadenza naturale fa lo stesso automaticamente. La chiusura rimuove il
riferimento al file attivo soltanto dopo una rinomina riuscita. Nomi già
occupati ricevono un suffisso deterministico e i `.active` rimasti orfani dopo
un arresto vengono recuperati come blocchi immutabili al checkpoint seguente.

## Analisi offline riproducibile

I blocchi scaricati da Drive si analizzano senza ADB e senza accedere al
telefono:

```sh
python3 tools/analyze_movement_intensive.py ~/Downloads/intensive_*.jsonl
python3 tools/analyze_movement_intensive.py --json \
  ~/Downloads/intensive_*.jsonl > /tmp/movement-intensive-report.json
```

Lo strumento non modifica gli input. Valida le righe, deduplica le finestre
per esperimento, segmento e intervallo e segnala buchi o sovrapposizioni sia
nello stesso segmento sia fra segmenti. Riporta separatamente anche gli eventi
`coverage_gap` dichiarati dal telefono. Aggrega copertura, attività, passi, qualità GPS, CPU, rete,
heap, batteria e stato schermo. Il calo tra percentuali batteria osservate non
è attribuzione energetica all'app: comprende ricariche, schermo e altre app.
Il JSON prodotto è un risultato derivato rigenerabile, non un input canonico.
