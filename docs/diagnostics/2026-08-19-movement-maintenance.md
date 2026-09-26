# Audit manutentivo Movimento — 19 agosto 2026

## Ambito

Revisione conservativa della diagnostica intensiva durante l'esperimento già
avviato sulla build 117. Sono rimasti invariati algoritmo di distanza,
classificazione, falcate, frequenze sensori, schema delle finestre e scadenza.

## Difetti corretti

1. Il worker controllava la scadenza passiva prima di caricare i blocchi
   intensivi. Se entrambi i test terminavano insieme, l'ultimo JSONL poteva
   restare locale senza ulteriori job. Il servizio ora pianifica un upload
   finale con rete e il worker lo esegue prima del gate passivo.
2. Il checkpoint cancellava dalle preferenze il nome attivo anche quando
   `renameTo` falliva. Ora un fallimento conserva il riferimento, non apre una
   continuazione concorrente e viene ritentato.
3. Timestamp uguali potevano produrre collisioni. La policy assegna suffissi
   deterministici e recupera `.active` non più referenziati senza sovrascrivere
   file completati.
4. Un errore di apertura segmento veniva subito mascherato dallo stato
   `stopped`; ora resta diagnosticabile.

## Verifica e debito controllato

La policy dei file ha test JVM per nome, rifiuto di input inatteso, collisione
e rinomina con conservazione dei byte. L'integrazione WorkManager viene inoltre
compilata nella build Android e richiede conferma sul Galaxy S21.

`DriveTestExportManager` (circa 700 righe) e `RunTrackerActivity` (circa 600)
superano la soglia di revisione perché aggregano più responsabilità. Non sono
stati rifattorizzati durante la raccolta per evitare una modifica ampia e non
necessaria. Dopo l'esperimento conviene separare export sessioni, snapshot
passivi e upload intensivi, e dividere composizione UI da orchestrazione.

La scrittura JSONL usa `fsync` ogni cinque secondi sul thread del servizio. È
intenzionale per massimizzare la durabilità dell'esperimento; CPU e frame
del Galaxy S21 vanno misurati prima di spostarla su una coda asincrona. La
versione finale a basso consumo non dovrà mantenere GPS o sensori continui.
