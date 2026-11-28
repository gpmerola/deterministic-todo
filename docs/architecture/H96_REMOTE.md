# Telecomando TV (H96 Remote)

Telecomando per il TV Box H96 Max dentro Todo, introdotto nella build 331.
È una funzione isolata: si accende e si spegne con un flag, si rimuove
cancellando due cartelle e poche righe, e il modulo nativo può diventare
un'app autonoma (repository `h96-remote`) senza modifiche al protocollo.

## Fase 0: compatibilità verificata (24 novembre 2026)

Box: modello `H96_Max_3518_TS`, chipset RK3518, Android TV OS 14 ufficiale
(launcher Android TV Home, Google Play), build `RZX.V01.20260812.1019`,
servizio Android TV Remote 7.00.

Dal Mac sulla stessa Wi-Fi, senza scansioni di porte: `dns-sd -B
_androidtvremote2._tcp` trova il box, che risolve sulle porte 6466
(controllo) e 6467 (abbinamento) con TLS 1.3 e certificato autofirmato.
Abbinamento con codice esadecimale a 6 caratteri mostrato sulla TV riuscito
con la libreria di riferimento `androidtvremote2` (Apache 2.0, usata solo
come prova, non inclusa). Connessione in 0,3 s; Home, frecce e volume
eseguiti; testo sintetico «Prova perché città ç € ? 123» comparso identico
nella ricerca del Play Store (conferma visiva dell'utente). Poi lo stesso
codice Java del modulo, eseguito sulla JVM del Mac, ha raggiunto lo stato
pronto in 0,35 s, inviato frecce e rifiutato un pin errato.

Decisione: trasporto **Android TV Remote v2**. ADB non serve. Il box espone
anche ADB di rete sulla porta 5555, consigliato disattivarlo se non usato.

## Struttura

```
android/h96remote/                     modulo Gradle, Java puro, zero dipendenze
  ProtoWriter, ProtoReader, Framing    protobuf minimale e cornici varint
  PairingMessages, PairingSecret,      abbinamento Polo (porta 6467)
  PairingSession
  RemoteMessages, RemoteProtocol       messaggi e handshake di controllo (6466)
  RemoteCommand                        comandi astratti → KeyEvent Android
  TvTransport, TlsTransport            trasporto sostituibile
  RemoteSession                        stato, riconnessione, nessuna ripetizione
  PinningTrustManager, TlsContexts,    identità e pin del certificato
  ClientIdentity, KeyStoreIdentity
  BoxStore, BoxDiscovery, LanAddress   preferenze, mDNS, solo indirizzi LAN
  WizProtocol, WizClient               lampadina WiZ via UDP locale
  H96RemoteController                  unica facciata per l'host
android/app/.../H96RemoteChannel.java  ponte MethodChannel, controller pigro
lib/features/h96_remote/               UI Flutter e client del canale
  h96_remote.dart                      flag e unico punto di ingresso
  h96_remote_client.dart               client del canale
  h96_remote_page.dart                 schermata
  h96_light_card.dart                  sezione Luce (WiZ)
```

Livelli separati come da proposta: UI (Flutter) → sessione e comandi
(`RemoteSession`, `RemoteCommand`) → trasporto (`TvTransport`). Un altro
trasporto (companion, Bluetooth HID) implementa `TvTransport` senza toccare UI
e sessione. Le classi di protocollo e sessione non dipendono da Android e sono
testate sulla JVM.

## Comportamento

- Nessun lavoro all'avvio dell'app: il controller nativo nasce alla prima
  chiamata dalla schermata. Nessun servizio in background, nessun polling.
- La schermata si connette quando è visibile e si disconnette quando la si
  lascia o l'app va in background.
- Il box invia un ping ogni 5 s; senza traffico per 16 s la connessione è
  considerata persa. Riconnessione automatica con attese 1, 2, 4, 8, 8 s,
  poi «Box non raggiungibile» con «Riprova». Se l'indirizzo DHCP è
  cambiato, una sola ricerca mDNS trova il nuovo indirizzo; il pin conferma
  che è lo stesso box.
- I comandi sono inviati solo nello stato pronto e mai accodati: una
  riconnessione non può ripetere un tasto. Tenendo premuti frecce e volume
  si inviano `START_LONG` e, al rilascio o all'uscita, `END_LONG`: è il box
  a ripetere il tasto, quindi non parte una raffica di messaggi.
- Mentre la schermata è aperta si tiene un `WifiLock` a bassa latenza
  (`WAKE_LOCK`), rilasciato alla disconnessione. Il tempo di apertura della
  connessione è mostrato come «Rete lenta» sopra 1,5 s.
- Il testo viene inviato solo con «Invia» e sostituisce il contenuto del
  campo attivo sulla TV; «Cancella» e «Invio» mandano i tasti corrispondenti.
  Gli appunti non vengono mai letti.
- Scorciatoie app (`RemoteApp`): link fissi aperti dal box con l'app
  installata (YouTube `https://www.youtube.com`, Netflix
  `https://www.netflix.com/title`, Prime Video `https://app.primevideo.com`,
  Google Play `market://launcher`). Dal canale arriva solo il nome della
  scorciatoia, mai un link arbitrario.
- Funzioni chieste al box: ping, tasti, IME, accensione, volume, link app.
  La voce non è richiesta: nessun microfono, nessun audio esce dal telefono.

## Sicurezza e privacy

- Solo rete locale: l'abbinamento accetta indirizzi IPv4 privati e IPv6
  link-local; la ricerca usa mDNS e dura 4 s.
- Chiave client RSA 2048 generata nell'Android Keystore, non esportabile.
- Durante l'abbinamento il certificato del box viene registrato; il segreto
  di abbinamento include la sua chiave pubblica, quindi un abbinamento
  riuscito prova che il codice letto sulla TV viene da quel certificato.
  Dopo, solo quel certificato (pin SHA-256) è accettato.
- `BoxStore` (SharedPreferences `h96_remote`) conserva indirizzo, nome e pin:
  nessun segreto. Il codice di abbinamento non viene salvato.
- «Dimentica il box» cancella le preferenze e la chiave: il vecchio
  abbinamento non è più utilizzabile. Sulla TV l'abbinamento si revoca
  anche dalle impostazioni del servizio telecomando.
- Nessun log del testo digitato, dei codici o dei nomi delle app; nessuna
  telemetria. Il trust manager accetta certificati non firmati da una CA
  solo durante l'abbinamento: se la funzione andasse su Google Play va
  rivalutato rispetto alle policy sui TrustManager.

## Accendere, spegnere, rimuovere, estrarre

Spegnere: compilare con `--dart-define=H96_REMOTE=false`. Le icone in Oggi spariscono e il codice nativo resta inattivo (nessuna chiamata).
Riaccendere: togliere il define (il valore predefinito è acceso).

Rimuovere del tutto:

1. cancellare `lib/features/h96_remote/`, `android/h96remote/`,
   `test/h96_remote_test.dart` e
   `android/app/src/main/java/app/deterministic/todo/deterministic_todo/H96RemoteChannel.java`;
2. (l'icona di Oggi include lampadina e telecomando) togliere da `lib/main.dart` l'import `features/h96_remote/h96_remote.dart`,
   da
   `lib/ui/shell/shell_layout.dart` il blocco `H96RemoteAction` (icona in
   Oggi);
3. togliere `H96RemoteChannel.register(...)` dai tre `MainActivity.kt`
   (`direct`, `dev`, `play`);
4. togliere `include(":h96remote")` da `android/settings.gradle.kts` e
   `implementation(project(":h96remote"))` da `android/app/build.gradle.kts`.

Rimettere: ripristinare gli stessi file e righe da git (commit della build
331).

Estrarre in `h96-remote`: copiare `android/h96remote` come modulo di
un'app nuova; `H96RemoteController` è già l'API completa. La UI Flutter va
riscritta (per esempio in Compose come nella proposta) chiamando gli stessi
metodi. Il protocollo, i test e questo documento si spostano invariati.

## Verifiche

- `./gradlew :h96remote:testDebugUnitTest` (JDK 17): codifica byte per byte
  confrontata con lo schema protobuf di riferimento, segreto di abbinamento,
  cornici, indirizzi LAN, sessione con trasporto simulato (nessun invio prima
  di pronto, nessuna ripetizione dopo riconnessione, rifiuto TLS come
  abbinamento non valido).
- `flutter test test/h96_remote_test.dart`: flag, voce nascosta fuori da
  Android, ricerca, invio tasti e testo solo da pronto, disconnessione.
- Collaudo reale: Galaxy S21 con Todo Test e box sulla stessa Wi-Fi.

## Luce WiZ (build 338, 27 novembre 2026)

Nella stessa schermata, sezione Luce per una lampadina WiZ: accensione,
intensità (10–100%) e otto preset (bianchi 2700, 4000 e 6500 K; rosso,
arancio, verde, blu, viola). Protocollo locale WiZ: JSON su UDP porta 38899,
nessun cloud, nessuna autenticazione; richiede «Consenti comunicazione
locale» nell'app WiZ. `WizProtocol` (puro, testato sulla JVM) costruisce e
legge i messaggi, `WizClient` li invia: ricerca con un solo `getPilot` in
broadcast (finestra di 2 s, su richiesta), comandi con una risposta attesa
400 ms e un solo reinvio, innocuo perché i comandi sono assoluti. Indirizzo
e MAC della lampadina nelle preferenze `h96_remote`; se l'indirizzo cambia la
si ritrova per MAC. Cursore con anteprima a non più di cinque comandi al
secondo. Indipendente dalla connessione alla TV; nessun lavoro all'avvio o in
background. Solo indirizzi LAN privati.

Dalla build 340 l'icona lampadina in Oggi apre gli stessi controlli in un
foglio. Fuori casa (rete mobile) il comando locale è impossibile e WiZ non ha
un'API cloud pubblica: il foglio mostra «Fuori dalla Wi-Fi di casa» e «Apri
WiZ», che lancia `com.wizconnected.wiz2` (dichiarato in `<queries>` del
modulo). Verificato sul Galaxy in rete mobile: il pulsante apre l'app WiZ.

## Bluetooth: provato e scartato (24 novembre 2026)

Con il Wi-Fi del box lento è stato provato un secondo trasporto Bluetooth
HID (telefono come tastiera e telecomando consumer, `BluetoothHidDevice`,
build 334–335 di Todo Test). Il profilo HID Device c'è sul Galaxy (Android
15), ma «Add accessory» sul box elenca solo dispositivi con classe periferica
e non vede il telefono; l'abbinamento avviato dal telefono arriva alla
finestra di conferma sulla TV, che però non accetta la conferma né dal
telecomando fisico né da quello Wi-Fi, e fallisce dopo circa 25 s. Senza
permessi di sistema non c'è via d'uscita: codice rimosso per tenere il modulo
leggero. Il trasporto resta sostituibile tramite `TvTransport`.

## Collaudo sul Galaxy (24 novembre 2026)

Build 331: abbinamento sempre fallito per la chiave Keystore senza
decifratura raw, necessaria a Conscrypt per RSA-PSS con TLS 1.3 (corretto
nella 332, alias `h96remote_client_v2`). Build 332: abbinamento e comandi
riusciti; tasti a volte poco reattivi. Misura via ADB: ping telefono → box
2,4–3,8 s contro 50 ms verso il router, poi box irraggiungibile anche dal
Mac. La lentezza dipende soprattutto dal collegamento Wi-Fi del box; la 333
migliora la parte dell'app.

## Limiti noti

Non ancora: touchpad e puntatore, dettatura, risveglio dallo
standby (il comando POWER esiste ma non è nella UI), ripetizione a pressione
lunga. Il collegamento Wi-Fi del box può introdurre secondi di ritardo che
l'app non può eliminare: con il cavo Ethernet il problema sparisce.
