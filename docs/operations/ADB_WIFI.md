# ADB wireless sul telefono di collaudo

Questa procedura consente di leggere log e diagnostica del Galaxy S21 senza
lasciare il telefono collegato via USB. Il pairing autorizza il Mac, mentre la
connessione ADB è temporanea: sono due stati distinti.

## Requisiti generali del progetto

ADB serve solo al collaudo: l’app e la CI non richiedono Tailscale, un Mac o un
LaunchAgent. Usare un dispositivo autorizzato e specificare sempre il target
quando sono presenti più trasporti. Non riavviare indiscriminatamente il server
ADB condiviso (`adb kill-server`) e non scollegare altri dispositivi.
Non configurare port forwarding, Funnel o esposizione Internet di ADB.

## Configurazione locale Mac / Samsung S21

Configurazione del 12 settembre 2026, fornita e collaudata dall’utente.
Sul Mac eseguire:

```sh
s21-adb
adb -s '[fd7a:115c:a1e0::e736:ed30]:5555' shell
```

`s21-adb` verifica una risposta reale del modello SM-G991N e riconnette con
timeout e fino a tre tentativi. Un lock impedisce esecuzioni simultanee; il
comando ricicla soltanto il trasporto del telefono, senza riavviare il server
ADB o scollegare altri dispositivi. `s21-adb --watch` è il controllo opzionale
in primo piano; normalmente basta il LaunchAgent.

Il LaunchAgent utente `local.s21-adb.reconnect` esegue un controllo ogni
30 secondi (`StartInterval=30`) e all’accesso (`RunAtLoad=true`). Non opera
mentre il Mac è spento o sospeso; lo stato `not running` tra due controlli è
normale. Per verificare installazione e ultimo esito:

```sh
plutil -lint "$HOME/Library/LaunchAgents/local.s21-adb.reconnect.plist"
launchctl print "gui/$(id -u)/local.s21-adb.reconnect"
```

Mac e telefono appartengono alla stessa tailnet. Sul Galaxy Tailscale usa
**VPN sempre attiva** ed è esente dall’ottimizzazione batteria. Preferire
l’IPv6 privato sopra: TCP IPv4 Tailscale presenta timeout, la cui causa precisa
non è stata risolta. Il comando locale conserva IPv4 come alternativa.
Collegamento e riconnessione manuale e automatica sono stati collaudati anche
su rete mobile, con Wi-Fi spento. Una diversa VPN Android può interrompere
Tailscale. L’endpoint è riportato su richiesta esplicita dell’utente; non
aggiungere al repository account, altri identificatori della tailnet o segreti.

ADB TCP ascolta sulla porta 5555. Il listener legacy è su tutte le interfacce:
con Wi-Fi acceso può essere raggiungibile anche dalla LAN, non soltanto dalla
VPN. La vecchia procedura LAN `adbtodo` non è più il percorso preferito;
usare l’indirizzo LAN corrente soltanto come fallback autorizzato.

### Provenienza e gestione dei file locali

Fonte della configurazione: `LEGGIMI-ADB.md` nella cartella locale
`~/Documents/Codex/2026-09-12/referenced-chatgpt-conversation-this-is-an/outputs/`.
`/opt/homebrew/bin/s21-adb` e
`~/Library/LaunchAgents/local.s21-adb.reconnect.plist` sono collegamenti ai file
in quella cartella: non spostarla o cancellarla mentre vengono usati. Python
3.13 e ADB sono dipendenze già installate sul Mac, non nuove dipendenze Todo.
Gli script e il plist restano configurazione locale esterna al repository;
questa procedura ne documenta l’uso, senza introdurre copie operative.

Per sospendere e ripristinare l’automazione, solo quando richiesto:

```sh
launchctl bootout "gui/$(id -u)/local.s21-adb.reconnect"
launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/local.s21-adb.reconnect.plist"
```

### Dopo un riavvio Android

VPN sempre attiva e LaunchAgent non possono riabilitare da soli ADB TCP.
`persist.adb.tcp.port` era vuota al collaudo: la porta 5555 potrebbe richiedere
riattivazione dopo reboot. Non è stata verificata persistenza attraverso un
riavvio. Con USB già autorizzata:

```sh
adb devices -l
adb -s SERIAL_USB tcpip 5555
s21-adb
```

In alternativa usare Debug wireless sul Wi-Fi: recuperare **IP address & port**
corrente dalla schermata Android o da `adb mdns services`, poi:

```sh
adb connect IP_LOCALE:PORTA
adb -s IP_LOCALE:PORTA tcpip 5555
s21-adb
```

Per questo fallback Mac e telefono devono essere sulla stessa LAN, Debug wireless
attivo e il Mac già associato. Ripetere il pairing solo se richiesto, senza
salvare il codice temporaneo. Non richiedere root o modifiche a proprietà protette.

## Fallback: connessione Debug wireless sulla LAN

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

Il canale operativo del Galaxy è **Todo Test**, package `.dev`, con firma
diretta stabile. Per consegnare usare `make todo-test`; per controllare la
versione senza modificare dati:

```sh
adb -s '[fd7a:115c:a1e0::e736:ed30]:5555' shell dumpsys package app.deterministic.todo.deterministic_todo.dev
```

Play e APK diretto dello stesso package non sono intercambiabili in-place.
`INSTALL_FAILED_UPDATE_INCOMPATIBLE` richiede di verificare canale e firma,
non di disinstallare l’app. Seguire [ANDROID_DEV_CHANNEL](ANDROID_DEV_CHANNEL.md);
non riattivare il fallback Play per questo collaudo.

## Ambito e sicurezza

ADB wireless è uno strumento di sviluppo, non una funzione necessaria al
funzionamento dell'app. Tenerlo attivo solo durante il collaudo. Usarlo per log,
stato del processo, versione installata e misure tecniche; non estrarre GPX,
database o altri dati personali senza una richiesta esplicita. Qualunque log
destinato al repository deve essere prima minimizzato e privato di coordinate,
identificatori e contenuti dell'utente.
