# ADB wireless sul telefono di collaudo

Questa procedura consente di leggere log e diagnostica del Galaxy S21 senza
lasciare il telefono collegato via USB. Il pairing autorizza il Mac, mentre la
connessione ADB è temporanea: sono due stati distinti.

## Prerequisiti LAN

- Mac e telefono sulla stessa rete Wi-Fi locale;
- **Developer options → Wireless debugging** attivo sul telefono;
- `adb` disponibile sul Mac;
- Mac già presente in **Wireless debugging → Paired devices**.

Non salvare nel repository codici di pairing, seriali ADB, MAC address o output
che possano contenere dati personali. L'eccezione dichiarata per il telefono di
collaudo sulla rete domestica è l'endpoint stabile documentato sotto; non
riutilizzarlo su altre reti.

## Endpoint domestico stabile

Il router domestico riserva `192.168.1.120` al Galaxy S21 di collaudo. ADB
classico è configurato sulla porta 5555 fino al successivo riavvio del telefono:

```sh
adb connect 192.168.1.120:5555
```

Nel profilo shell personale lo stesso comando è disponibile come `adbtodo` e
viene ricordato all'apertura di un terminale. Dopo un riavvio del telefono,
riattivare temporaneamente ADB TCP/IP tramite la connessione Wireless debugging:

```sh
adb connect <ip>:<porta-wireless-debugging>
adb tcpip 5555
adb connect 192.168.1.120:5555
```

La prenotazione DHCP sopravvive ai riavvii; la modalità ADB TCP/IP 5555 no.
Usare questo endpoint soltanto sulla LAN privata e disabilitare ADB sulle reti
non fidate.

## Connessione privata tra reti diverse

Mac e telefono possono usare la stessa rete privata Tailscale. Questa
configurazione è stata collaudata con il Wi-Fi del Galaxy spento: il tunnel è
rimasto raggiungibile sulla rete mobile e ADB TCP ha risposto sulla porta
5555. Tailscale fornisce connettività e un nome/IP stabile, ma non avvia ADB.

Con una connessione Wireless debugging già autorizzata:

```sh
adb connect <ip-tailscale>:<porta-wireless-debugging>
adb -s <ip-tailscale>:<porta-wireless-debugging> tcpip 5555
adb connect <nome-magicdns-o-ip-tailscale>:5555
adb devices -l
```

Non documentare nome, IP o account personali della tailnet. Non pubblicare né
inoltrare la porta 5555 sul router: deve essere raggiungibile soltanto nella
rete privata. Dopo il riavvio Android può disattivare la modalità TCP 5555; in
quel caso riabilitarla tramite la porta temporanea di Wireless debugging o USB.
Se il tunnel è raggiungibile ma `adb connect ...:5555` risponde `Connection
refused`, la rete funziona e manca soltanto `adb tcpip 5555`.

## Connessione ordinaria

Sul telefono aprire **Settings → Developer options → Wireless debugging** e
leggere il valore corrente di **IP address & port**. Poi sul Mac eseguire:

```sh
adb connect <ip>:<porta>
adb devices -l
```

L'output atteso di `adb devices -l` contiene una riga con lo stesso indirizzo e
stato `device`. Uno stato `offline` o l'assenza della riga non costituiscono una
connessione valida.

Per verificare se Android annuncia automaticamente il servizio sulla rete:

```sh
adb mdns services
```

mDNS è solo una comodità: alcune reti o versioni Samsung non annunciano il
servizio in modo affidabile. In quel caso usare direttamente **IP address &
port** mostrato sul telefono.

## Riconnessione dopo un'interruzione

Allontanarsi dalla rete, disattivare il Wi-Fi, riavviare uno dei dispositivi o
disattivare Wireless debugging interrompe la sessione. Il pairing normalmente
resta valido, ma Android può cambiare indirizzo IP o porta.

Quando il telefono torna sulla stessa rete:

1. controllare che **Wireless debugging** sia ancora attivo;
2. provare `adb connect` con il valore precedente;
3. se fallisce, rileggere il nuovo **IP address & port** e riprovare;
4. ripetere il pairing soltanto se il Mac non compare più in **Paired devices**
   o se ADB risponde con un errore di autenticazione.

La riconnessione automatica non è garantita. Una futura automazione può cercare
il servizio tramite mDNS e chiamare `adb connect`, ma deve prevedere come
fallback l'inserimento della porta corrente.

## Nuovo pairing, solo quando necessario

Sul telefono scegliere **Pair device with pairing code**. Senza chiudere la
finestra, eseguire:

```sh
adb pair <ip>:<porta-pairing>
```

Inserire il codice temporaneo quando richiesto. La porta di pairing non è
necessariamente la stessa porta mostrata nella schermata principale per
`adb connect`. Il codice scade rapidamente e non deve essere annotato o
inserito in log, documentazione o Git.

## Diagnosi dei problemi comuni

- `adb devices -l` vuoto: nessuna connessione attiva; usare `adb connect`.
- `adb mdns services` vuoto: usare l'indirizzo esplicito; non implica che il
  pairing sia perso.
- `Connection refused` o timeout: controllare porta corrente, stessa rete,
  Wireless debugging e l'eventuale isolamento client della rete guest.
- `unauthorized`: sbloccare il telefono e verificare l'autorizzazione; se
  persiste, rimuovere soltanto il Mac da **Paired devices** e rifare il pairing.
- VPN o rete guest: possono impedire la comunicazione locale. Una tailnet
  Tailscale esplicitamente configurata è il percorso remoto supportato; non
  esporre ADB direttamente su Internet.

Per revocare l'accesso, rimuovere il Mac da **Wireless debugging → Paired
devices** oppure disattivare completamente Wireless debugging.

## Stato passivo Movimento nelle build release

Dalla build 114 l'ultimo tentativo orario è leggibile senza aprire l'app e
senza abilitare `run-as`:

```sh
adb shell content query --uri content://app.deterministic.todo.deterministic_todo.movement_debug/status
```

Solo sul canale Todo Test, la shell autorizzata può programmare lo stesso
upload completo del pulsante nell'interfaccia, senza sbloccare il telefono:

```sh
adb shell content call \
  --uri content://app.deterministic.todo.deterministic_todo.dev.movement_debug/status \
  --method export_now
```

Il provider resta protetto dal permesso Android `DUMP`; l'operazione non è
accessibile ad app ordinarie e non avvia GPS o BLE.

L'output atteso contiene una sola riga con `phase`, `result_code`, timestamp,
nome dello snapshot, stato Drive, passi classificati e aggregati Todo/Google
Fit. Dalla build 116 include anche finestra misurata, quantità e somma dei
record grezzi, intervalli invalidi, fattore di riconciliazione e millisecondi
impiegati da Health Connect e dalla scrittura Drive. `phase=success` e
`result_code=ok` confermano lettura Health Connect e
scrittura Drive; `health_connect_error` o `drive_error` identificano il confine
del problema. `next_expected_ms` è una previsione: Android può differire il
job. Il provider è in sola lettura e richiede il permesso di sistema `DUMP`,
posseduto dalla shell ADB ma non dalle normali app. Non espone GPX, coordinate,
database Todo o preferenze complete.

Dalla build 135 la stessa riga espone campi `bip_sync_*` per l’ultimo recupero
orologio e `intensive_*gap*` per la copertura della diagnostica. Un sync Bip
riuscito termina con `bip_sync_phase=success`, esito
`activity_sync_success` e `bip_sync_drive_result=ok`; `running` persistente o
`drive_error` localizzano il confine senza dover interpretare uno screenshot.

## Stato sincronizzazione Todo dalla build 154

Todo Test espone un provider distinto, in sola lettura e protetto dallo stesso
permesso Android `DUMP`:

```sh
adb shell content query --uri \
  content://app.deterministic.todo.deterministic_todo.dev.todo_sync_debug/status
```

`state` distingue `healthy`, `recovered`, `error` e `unknown`. Gli altri campi
riportano ultimo successo, fallimento e recupero, fase, classe tecnica, stato
rete/sessione, quantità in attesa e retry. Il provider legge esclusivamente il
giornale diagnostico minimizzato: non apre SQLite e non espone attività,
progetti, titoli, note, email, URL, token o messaggi restituiti dal server.

## Aggiornamenti e firma del dispositivo di test

Prima di usare `adb install -r`, verificare la provenienza dell'app installata.
Il Galaxy S21 di test usa attualmente la firma di **Google Play App Signing**:
un APK diretto GitHub con la stessa `applicationId` ma firmato dalla chiave del
repository viene rifiutato con `INSTALL_FAILED_UPDATE_INCOMPATIBLE`. È un
controllo di integrità, non un blocco di sicurezza aggirabile.

Su questa installazione usare il test interno Play e non disinstallare l'app:
la disinstallazione eliminerebbe i dati locali. Il canale APK diretto resta
valido per dispositivi che hanno iniziato con quella stessa linea di firma,
ma i due canali non sono intercambiabili in-place. Per controllare la versione:

```sh
adb shell dumpsys package app.deterministic.todo.deterministic_todo \
  | grep -E 'versionCode|versionName|lastUpdateTime'
```

## Ambito e sicurezza

ADB wireless è uno strumento di sviluppo, non una funzione necessaria al
funzionamento dell'app. Tenerlo attivo solo durante il collaudo. Usarlo per log,
stato del processo, versione installata e misure tecniche; non estrarre GPX,
database o altri dati personali senza una richiesta esplicita. Qualunque log
destinato al repository deve essere prima minimizzato e privato di coordinate,
identificatori e contenuti dell'utente.
