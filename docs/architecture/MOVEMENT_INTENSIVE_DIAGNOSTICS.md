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
la scadenza naturale fa lo stesso automaticamente.
