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
   disponibile prima dell'autenticazione. Entrambi sono risultati validi. Se
   Drive Movimento è collegato, l'esito compare automaticamente in `05 Bip U`.
   Dalla build 121 l'app conserva l'identificatore SAF verificato della
   sottocartella, evitando copie omonime dovute alla cache del provider Drive.
4. La chiave ricavata legittimamente dal proprio account Zepp può essere
   inserita per conservarla nel Keystore. Viene usata soltanto in memoria
   durante il challenge-response della prova cardiaca e non entra nei report.

## Prova cardiaca build 122

1. Salvare una volta la chiave Huami di 32 caratteri nel Keystore Android.
2. Indossare l'orologio e premere **Autentica e leggi battito · 60 s**.
3. Restare fermi fino al primo valore. L'app mostra BPM e numero campioni,
   arresta il sensore entro 60 secondi e si disconnette automaticamente.
4. Verificare in `05 Bip U` il file `bip_u_heart_rate_probe_*.json`. Il report
   non contiene chiave, MAC o pacchetti grezzi.

La prova invia challenge-response e comandi cardiaci temporanei; non modifica
firmware o impostazioni persistenti. Se autenticazione o servizio cardiaco non
sono disponibili, non ripetere rapidamente: conservare il report e analizzarlo.

Non condividere chiave, MAC, GPX o database nei bug report. Non usare il modulo
per firmware, reset o scritture sperimentali.

## Importazione attività build 126

1. Indossare o tenere vicino il Bip U e premere **Importa attività Bip U ·
   ultime 24 h** una sola volta.
2. Attendere la conferma con minuti, passi, campioni battito e record nuovi.
3. Un retry è sicuro: la chiave timestamp+sorgente impedisce duplicati e
   vengono aggiunti soltanto i minuti comparsi nel frattempo.
4. Il telefono continua a funzionare senza orologio. I dati Bip U restano una
   sorgente locale separata e non vengono ancora sommati a Health Connect.

L’import non invia il comando finale che potrebbe marcare i campioni come
consumati. Drive riceve solo il riepilogo tecnico aggregato, non la timeline
sanitaria.
