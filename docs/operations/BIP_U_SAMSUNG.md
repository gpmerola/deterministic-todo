# Installazione e collaudo Bip U su Samsung

## Installazione

1. Attendere che Google Play mostri la build 83 nel test interno e premere
   **Aggiorna**. In alternativa installare l'APK `arm64-v8a` firmato della
   release 2.19.0; non alternare firme diverse.
2. Aprire **Impostazioni → Movimento · passi, calorie e GPS**.
3. Alla prima corsa concedere **Posizione precisa** e **Notifiche**. Non serve
   Posizione sempre: il servizio viene avviato dalla schermata visibile e resta
   esplicitamente in foreground.
4. Per il primo collaudo Samsung aprire **Impostazioni di sistema → App →
   Deterministic Todo → Batteria → Senza restrizioni**. È una tutela contro la
   sospensione OEM durante lo schermo spento; rivalutare dopo le misure.

## Prova GPS

1. Attendere un'accuratezza inferiore a circa 15 m all'aperto.
2. Premere **Avvia corsa**, bloccare lo schermo e percorrere un tracciato noto.
3. Restare fermi per almeno due minuti: la distanza non deve crescere in modo
   evidente.
4. Terminare dalla notifica o dalla schermata, quindi esportare il GPX.
5. Conservare il GPX solo per la propria diagnosi: contiene il percorso reale.

Durante la calibrazione premere **Collega cartella Google Drive per i test** e
scegliere `Deterministic Todo Movement Tests`. La scelta persiste. Ogni sessione
produce automaticamente GPX e JSON diagnostico; non aggiungere mai questi file
al repository e non condividere la cartella.

Se Android mostra una notifica GPS ma la distanza resta ferma, controllare che
la Posizione di sistema sia attiva e precisa. Se la notifica scompare durante
lo schermo spento, verificare la modalità Batteria Samsung.

## Prova BLE sicura

1. Chiudere Zepp per evitare due client GATT concorrenti. Non è necessario
   disassociare l'orologio dalle impostazioni Bluetooth di Android.
2. Aprire **Bip U · prova BLE in sola lettura**, concedere **Dispositivi nelle
   vicinanze** e avviare il collegamento. La prova usa prima il Bip U già
   associato; la scansione di 12 secondi è soltanto il fallback.
3. La prova può mostrare la batteria oppure spiegare che il servizio non è
   disponibile prima dell'autenticazione. Entrambi sono risultati validi.
4. La chiave ricavata legittimamente dal proprio account Zepp può essere
   inserita per conservarla nel Keystore, ma questa versione non la trasmette.

Non condividere chiave, MAC, GPX o database nei bug report. Non usare il modulo
per firmware, reset o scritture sperimentali.
