# ADB wireless sul telefono di collaudo

Questa procedura consente di leggere log e diagnostica del Galaxy S21 senza
lasciare il telefono collegato via USB. Il pairing autorizza il Mac, mentre la
connessione ADB è temporanea: sono due stati distinti.

## Prerequisiti

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
- VPN o rete guest: possono impedire la comunicazione locale anche quando
  entrambi i dispositivi hanno accesso a Internet.

Per revocare l'accesso, rimuovere il Mac da **Wireless debugging → Paired
devices** oppure disattivare completamente Wireless debugging.

## Ambito e sicurezza

ADB wireless è uno strumento di sviluppo, non una funzione necessaria al
funzionamento dell'app. Tenerlo attivo solo durante il collaudo. Usarlo per log,
stato del processo, versione installata e misure tecniche; non estrarre GPX,
database o altri dati personali senza una richiesta esplicita. Qualunque log
destinato al repository deve essere prima minimizzato e privato di coordinate,
identificatori e contenuti dell'utente.
