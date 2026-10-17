# Movimento: cronologia performance (archiviata)

Estratto il 7 ottobre 2026 da
[ANDROID_PERFORMANCE_E_AGGIORNAMENTI](../ANDROID_PERFORMANCE_E_AGGIORNAMENTI.md).
Funzioni rimosse dalla build 190: vedi [Movimento archiviato](MOVIMENTO.md).

Il test passivo Movimento è temporaneo e auto-scade dopo sette giorni. Dalla
2.25.5 usa un solo `PeriodicWorkRequest` ogni ora: legge da Health Connect la
giornata corrente e crea un file immutabile
`movement_snapshot_YYYY-MM-DD_HH.json` per fascia oraria. Conserva inoltre il
report definitivo `daily_audit_YYYY-MM-DD.json` del giorno concluso. Il primo
snapshot è pianificato circa un minuto dopo l'avvio e un test già attivo viene
aggiornato automaticamente dalla nuova build. I retry restano affidati a
WorkManager. Non registra GPS, non mantiene un servizio foreground e non usa
BLE; il costo va comunque misurato sul Galaxy S21 prima di rendere permanente
la frequenza di debug.

Dalla 2.25.12 snapshot e audit vivono in `02 Passive`; sessioni GPX/JSON,
blocchi intensivi, diagnostica app e prove Bip U usano rispettivamente
`01 Sessions`, `03 Intensive`, `04 App diagnostics` e `05 Bip U`. Le directory
sono create idempotentemente dentro la radice SAF già autorizzata.

Dalla 2.25.6 lo stato aggregato dell'ultimo tentativo è interrogabile dalla
shell ADB con il comando canonico documentato in
[`operations/ADB_WIFI.md`](../operations/ADB_WIFI.md). Il provider è read-only,
protetto da `android.permission.DUMP` e non rende debuggabile l'APK release.

La 2.25.7 non considera più `STILL` una causa di esclusione quando il sensore
registra passi nello stesso intervallo: quei passi alimentano il fallback
prudente da camminata e restano marcati come conflitto. Veicolo e bicicletta
dominanti restano esclusi e sono misurati separatamente nello schema 4 e nel
provider ADB, insieme alla baseline di distanza su tutti i passi.

La 2.25.8 porta la diagnostica passiva allo schema 5. Ogni snapshot registra
la finestra realmente letta, tempi delle query, conteggi e copertura dei record
passi, riconciliazione con l'aggregato, valori pre/post classificazione e delta
validato dallo snapshot precedente. Il confronto calcola errori assoluti e
percentuali, falcate effettive implicite e flag di qualità per dati mancanti,
record vecchi, prevalenza `unknown` o conflitti `STILL`. Non vengono registrate
coordinate, percorsi o contenuti Todo.

La 2.28.1 porta questi report allo schema 6 aggiungendo una timeline UTC al
minuto ricostruita durante la stessa lettura oraria. Non introduce risvegli al
minuto, BLE permanente o GPS passivo: il costo aggiuntivo è limitato alla
lettura dei record distanza e alla serializzazione del report durante il job
diagnostico temporaneo.

