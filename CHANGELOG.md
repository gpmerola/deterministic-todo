# Changelog

Cronologia delle modifiche distribuite, dalla più recente.

## 2.23.1

- Reso il confronto Google Fit un lavoro persistente: parte dopo lo stop,
  applica timeout e retry e non dipende più dalla schermata Movimento aperta.
- Il risultato viene salvato nel JSON Drive e mostrato nella schermata con uno
  stato esplicito; gli errori Health Connect non restano più indefinitamente
  su “attendo”.
- Compattata Movimento in righe metriche, azioni affiancate e testi essenziali;
  il focus iniziale resta in alto per evitare contenuti coperti dalla toolbar.

## 2.23.0

- Promossa Movimento a destinazione principale accanto a Progetti; rimossa la
  vecchia voce nascosta nelle Impostazioni.
- Ridisegnata la schermata attorno a una sola azione primaria per la camminata,
  con corsa secondaria, stati leggibili e strumenti tecnici comprimibili.
- Dopo lo stop, confronto Google Fit e aggiornamento del JSON Drive partono
  automaticamente; confronto, riesportazione e GPX manuali restano disponibili
  come recovery.
- Il JSON diagnostico include una sezione versionata
  `google_fit_comparison` con osservazione e valori locali/riferimento.

## 2.22.4

- Estratta dal servizio Android la politica che combina attività, stato del
  sensore e incremento passi; aggiunti test per camminata, corsa, sensore
  indisponibile e reset del contatore.
- Allineati README, stato, handoff e checklist operativa ai collaudi reali
  delle build 93–95 e al test lungo ancora necessario sul Galaxy S21.
- Rimossa un'importazione Java inutilizzata senza cambiare l'algoritmo GPS.

## 2.22.3

- Durante una camminata con contatore hardware attivo, un intervallo GPS senza
  nuovi passi viene conservato ma non incrementa più la distanza.
- Alla ripartenza, il primo nuovo passo consente di recuperare il segmento
  plausibile dall'ultimo punto valido; corsa e dispositivi senza sensore
  mantengono il filtro GPS precedente come fallback.

## 2.22.2

- Il JSON diagnostico registra ora timestamp, totale progressivo e stato di
  ogni variazione del contatore passi durante la sessione.
- La timeline viene mantenuta in memoria e salvata al massimo ogni 30 secondi,
  oltre che alla chiusura, per limitare I/O e consumo energetico.
- Il conteggio quotidiano resta affidato a Health Connect quando l'app è
  chiusa; non viene introdotto un servizio permanente né GPS in background.

## 2.22.1

- La ripartenza dopo una sosta usa l'incremento del contatore passi hardware
  come prova di movimento per ridurre soltanto la soglia anti-rumore GPS.
- Accuratezza, velocità massima, discontinuità e zigzag restano vincoli
  obbligatori, così i passi non possono trasformare un salto GPS in distanza.
- Il consumo attribuibile all'app continua a essere rappresentato da CPU e
  memoria del processo; la variazione percentuale di batteria è dell'intero
  dispositivo e può includere YouTube, schermo e rete.

## 2.22.0

- Le sessioni contano i passi direttamente con `TYPE_STEP_COUNTER`, anche a
  schermo spento, e li mostrano separatamente nella schermata Movimento.
- Il JSON diagnostico conserva passi diretti e stato del sensore senza
  confonderli con il totale giornaliero Health Connect.
- Aggiunto il confronto dell'ultima sessione con i dati attribuiti a Google Fit
  in Health Connect: distanza, passi, calorie attive, intervallo e scarto.

## 2.21.4

- Il filtro camminata recupera ora un intervallo inizialmente sospetto quando
  il fix di conferma rende plausibile la velocità complessiva, evitando di
  perdere movimento reale durante brevi oscillazioni GPS.
- L'export automatico mantiene attivo il servizio fino alla scrittura effettiva
  di GPX e JSON, attende Health Connect con timeout e mostra esito o codice di
  errore nella schermata Movimento.
- Le scritture Drive sono idempotenti e `Riesporta ultima attività` permette di
  rigenerare entrambi i file, inclusa una sessione registrata con una build
  precedente.
- Il GPX usa estensioni esplicite per accuratezza in metri e distanza
  cumulativa; non presenta più l'accuratezza Android come `hdop`.

## 2.21.3

- Separata la build AAB Google Play dalla generazione degli APK diretti: dopo i
  test, il bundle viene costruito e caricato subito nel track interno mentre
  APK GitHub e Web proseguono in parallelo.
- Conservata la verifica coordinata finale di Play, Web e release GitHub; la
  corsia rapida usa quindi la normale firma Play e non richiede reinstallazione
  né cambio del canale installato.

## 2.21.2

- Corretto il contratto Room di `run_sessions.activityType`: ora nullabilità e
  default del modello coincidono con la migrazione 2→3 già applicata.
- Risolto il crash silenzioso che chiudeva Movimento sulle installazioni
  aggiornate da uno schema precedente; i dati esistenti vengono conservati.

## 2.21.1

- Reso il selettore della cartella Drive indipendente dal registro moderno dei
  permessi Health Connect, evitando la chiusura silenziosa di Movimento vista
  sul Galaxy S21 con la build 87.
- Gli errori nel conservare il permesso Drive vengono ora mostrati senza
  chiudere la schermata.

## 2.21.0

- Sostituito il trasferimento USB con una cartella Google Drive scelta una sola
  volta tramite Android e autorizzata in modo persistente.
- Ogni sessione genera automaticamente un GPX e un JSON diagnostico omonimo con
  passi, errori GPS, campioni, batteria, CPU, memoria, rete, dispositivo e tempi.
- I file usano nomi ordinabili con timestamp, attività e ID sessione; nessuna
  credenziale Google viene incorporata nell’app.

## 2.20.1

- Separate le sessioni GPS `camminata` e `corsa`: il profilo camminata usa una
  soglia GPS dedicata e ri-ancora le discontinuità senza sommarne la distanza.
- Aggiunta una modalità di test opzionale che salva automaticamente ogni GPX
  in `Download/DeterministicTodoTests` al termine dell’attività.
- Aggiunto `tools/pull_latest_movement_gpx.sh` per copiare via USB/ADB l’ultimo
  GPX in una cartella temporanea, senza passare da Google Drive.
- Database movimento migrato senza perdita di dati allo schema 3, conservando
  il tipo di attività per ogni sessione.

## 2.20.0

- Aggiunta la prima schermata Android Movimento con passi odierni aggregati da
  Health Connect, così il sistema può continuare a registrarli anche quando
  Deterministic Todo non è aperta.
- Distanza e calorie attive sono mostrate esplicitamente come stime locali
  derivate dai passi; la sorgente aggregata evita di sommare due volte record
  sovrapposti provenienti da telefono e future integrazioni.
- Il database separato `run_tracker.sqlite` passa allo schema 2 con una
  migrazione non distruttiva e conserva giorno civile, fuso, provenienza,
  passi, distanza e calorie stimate.
- Aggiunta una pagina privacy dedicata ai permessi salute. Passi e stime
  restano locali e non entrano nel database Todo o in Supabase.
- Il requisito minimo Android passa da API 24 ad API 26, minimo supportato dal
  client stabile Health Connect; il Galaxy S21 di riferimento non è coinvolto.

## 2.19.1

- Corretto l'avvio GPS su Android richiedendo insieme posizione approssimativa
  e precisa, come previsto dal modello permessi recente.
- La schermata corsa distingue ora ricerca satelliti, GPS di sistema spento,
  permesso preciso assente, segnale debole e fix attivo. Dopo venti secondi
  senza coordinate suggerisce esplicitamente di spostarsi all'aperto.

## 2.19.0

- Aggiunto un modulo Android isolato e rimovibile per corsa con Amazfit Bip U:
  GPS del telefono tramite foreground service Android 14, funzionamento a
  schermo spento, durata, distanza, passo medio e accuratezza.
- I campioni sono salvati in un database Room separato. Coordinate imprecise,
  salti, zigzag, rumore da fermo e timestamp non monotoni non aumentano la
  distanza ma restano disponibili con il motivo dello scarto.
- Aggiunto export GPX con traccia valida e waypoint diagnostici scartati.
- Aggiunta una prova BLE conservativa che cerca il Bip U e legge la batteria
  standard senza modificare orologio o firmware; la chiave Huami può essere
  conservata cifrata tramite Android Keystore.
- Scelta un'implementazione indipendente del protocollo: non è stato copiato o
  adattato codice AGPLv3 di Gadgetbridge, preservando la licenza MIT dell'app.

## 2.18.10

- Ridotta a due secondi la permanenza dell'avviso Annulla dopo il completamento.
  Gli avvisi di cancellazione restano a cinque secondi.

## 2.18.9

- L'intera riga attività offre un feedback visivo leggero e uniforme al tocco,
  senza aggiungere icone o cambiare la geometria della lista.
- Oggi, Completate e Progetti condividono uno stato vuoto su una sola riga;
  Prossime mantiene lo stesso stile discreto per i giorni senza attività.
- Il pannello editor Web non viene più ricreato durante gli aggiornamenti
  sincronizzati: conserva focus e bozze locali e assorbe dati remoti soltanto
  quando non esistono modifiche in corso.
- L'avviso Annulla dopo un completamento dura quattro secondi; eliminazioni e
  altre azioni più rischiose conservano cinque secondi.

## 2.18.8

- Accorciata leggermente la scomparsa dopo il completamento: conferma visiva
  da 240 a 200 ms e chiusura verticale da 190 a 170 ms. Spunta, area di tocco,
  feedback tattile e stabilità della riga restano invariati.

## 2.18.7

- Reso il completamento mobile stabile e vicino a Todoist: un unico controllo
  circolare conserva posizione e dimensione durante tutta l'interazione.
- Rimossi rimbalzo, cambio di icona, tinta verde della riga e dissolvenza
  simultanea. La spunta e il feedback tattile sono immediati; dopo una breve
  conferma la riga chiude gradualmente il proprio spazio e Undo resta presente.

## 2.18.6

- Resa più stabile la cancellazione mobile ispirandosi alla micro-interazione
  Todoist: soglia swipe più deliberata, azione Cestino esplicita e feedback
  tattile soltanto quando la cancellazione è realmente armata.
- Rallentati il completamento del gesto e il riassestamento della lista; uno
  swipe incompleto torna al suo posto senza modificare i dati e Undo resta
  disponibile dopo la cancellazione.

## 2.18.5

- La vista Oggi separa ora le attività arretrate dalle attività odierne con due
  intestazioni leggere; le arretrate restano in alto e non vengono
  riprogrammate automaticamente.
- Priorità e ordinamento stabile continuano ad applicarsi all'interno di ogni
  gruppo senza caricare anticipatamente l'intera lista nell'interfaccia.

## 2.18.4

- `Esc` chiude ora prima l'editor laterale Web senza cambiare sezione.
- Completando una ricorrenza, l'avviso indica il giorno esatto della prossima
  occorrenza generata.
- Tutti gli avvisi temporanei espongono un pulsante di chiusura immediata su
  Android e Web, mantenendo la scomparsa automatica.

## 2.18.3

- Rimosse tutte le scorciatoie globali di creazione e ricerca, incluse le
  combinazioni Ctrl/⌘, per impedire qualsiasi interferenza con l'editor Web.
- Restano soltanto `Esc` per tornare indietro o chiudere e `Invio` per
  confermare il titolo nell'editor attivo.

## 2.18.2

- Corretto l'editor laterale Web: digitare `n` o `/` non apre più il composer
  o la ricerca interrompendo la modifica.
- Le azioni globali Nuova attività e Cerca richiedono ora Ctrl/⌘; Invio resta
  dedicato al salvataggio dell'editor attivo.

## 2.18.1

- Rimossa Riferimenti dall'interfaccia: Progetti torna a essere l'unico sistema
  per organizzare materiale e attività. Eventuali record creati nella 2.18.0
  restano visibili come normali task, senza perdita di titolo, note o link.
- Invio fisico salva ora una modifica anche nell'editor laterale Web; non
  dipende più dalla sola azione `Done` della tastiera virtuale.
- Il controllo completo Supabase in foreground passa da uno a dieci minuti,
  riducendo del 90% i risvegli periodici. Realtime, modifiche locali,
  riconnessione e ritorno in primo piano restano immediati.

## 2.18.0

- Aggiunta la sezione autonoma Riferimenti per conservare link e note
  persistenti senza mostrarli in Oggi, Prossime o Progetti. Il sistema Progetti
  e l'import Todoist restano invariati e reversibili.
- Riferimenti sincronizzati tra Android e Web e inclusi nei backup JSON/CSV;
  i backup precedenti restano compatibili e vengono interpretati come attività.
- Il completamento non sposta più lateralmente la riga: mostra una conferma
  verde, conclude una dissolvenza breve e solo allora aggiorna la lista, così
  gli elementi circostanti non saltano durante il tocco.

## 2.17.5

- Invio nel titolo conferma ora anche la modifica, sia nell'editor inline web
  sia nel foglio Android; la descrizione resta intenzionalmente multilinea.
- Creazione e modifica condividono una sola operazione di conferma, protetta da
  doppi invii mentre il salvataggio locale è in corso.

## 2.17.4

- Sul desktop il pannello laterale è ora direttamente un editor: titolo,
  descrizione, data, priorità, ricorrenza, progetto e sezione si modificano
  senza aprire un secondo foglio.
- La documentazione operativa è stata riallineata al default senza priorità,
  alle release correnti e agli eventi Google Calendar esclusivamente giornalieri.

## 2.17.3

- Il pannello dettagli desktop espone ora la modifica nell'intestazione, sempre
  visibile senza dover raggiungere il fondo della colonna.
- Ogni apertura del composer parte da nessuna priorità; una scelta precedente
  non viene più memorizzata, mentre `p1`–`p4` nel titolo resta supportato.

## 2.17.2

- Gli annunci con azioni, incluso Undo, ora scompaiono dopo cinque secondi
  anche quando Android o il browser hanno l'accessibilità di navigazione attiva.
- Il pannello dettagli desktop entra, esce e cambia attività con una breve
  transizione coordinata, senza modificare l'apertura istantanea del `+`.

## 2.17.1

- Il composer mostra ora il titolo come riga larga sopra descrizione, priorità,
  progetto e invio; su desktop Invio crea sempre la task senza andare a capo.
- Lo stesso composer resta la fonte unica per Oggi, Prossime e Progetti; il
  contesto cambia soltanto progetto e sezione predefiniti.
- Ogni attività espone un menu `⋮` con Modifica e Cestino. L'editor offre anche
  Cestino accanto a Salva e tutte le eliminazioni mantengono l'Undo.

## 2.17.0

- Aggiunto il comando universale: `Ctrl/⌘ K` cerca attività, `+` crea con
  linguaggio naturale, `>` apre una sezione e `#` filtra per progetto.
- Centralizzato l'Undo di completamento, cestino, progetto e sezione. Per le
  ricorrenze annulla anche l'occorrenza successiva appena generata.
- Il desktop usa una vista master–detail opzionale; liste e tipografia sono più
  dense sul computer, mantenendo target ampi su Android.
- L'import Todoist analizza JSON e ricorrenze fuori dal frame UI su Android.
- Aggiunti profili Android di avvio e baseline, più un budget CI di 25 MiB per
  ogni APK specifico per CPU.

## 2.16.21

- Automatizzata la pubblicazione dell'AAB firmato nel test interno Google Play
  dopo la riuscita coordinata di test, Android e Web.
- Limitata l'identità CI alla sola app e ai soli canali di test; la produzione
  resta manuale.

## 2.16.20

- Aggiunti temi ad alto contrasto, target di tocco da almeno 48 px e descrizioni
  semantiche di priorità, data e ricorrenza: le informazioni non dipendono più
  soltanto dal colore e restano leggibili dagli screen reader.
- L'avvio Web sovrappone inizializzazione diagnostica, attivazione delle task e
  bootstrap Supabase; SQLite WebAssembly e worker Drift vengono precaricati e
  una schermata HTML immediata copre il tempo prima del primo frame Flutter.
- Aggiunto un test automatico con database Android e Web indipendenti che
  verifica ID ricorrenti deterministici e convergenza Lamport dopo modifiche
  offline concorrenti.
- Analizzati i report reali del 5–8 agosto: la Web 2.16.19 non mostra fallimenti
  di sync; su Android 2.16.17 resta un solo errore di rete transitorio.


## 2.16.19

- Le ricevute remote dell'outbox sono ora trattate come record immutabili:
  durante un retry, un `operation_id` già confermato viene ignorato invece di
  richiedere un aggiornamento vietato dalla RLS Supabase (`42501`).
- La riconciliazione delle collisioni ricorrenti può quindi completare anche
  quando la coda contiene ricevute già registrate da un tentativo precedente.

## 2.16.18

- Il sync riconcilia automaticamente le vecchie collisioni tra occorrenze
  ricorrenti create in parallelo da Android e browser, conservando la versione
  Lamport più recente invece di restare bloccato con errore Supabase `23505`.
- Le nuove occorrenze ricorrenti usano un UUID v5 deterministico derivato da
  serie e data civile: dispositivi diversi generano lo stesso record e non
  possono più introdurre questa duplicazione.
- La diagnostica registra soltanto l'avvenuta riconciliazione e quale lato ha
  prevalso, senza titolo, descrizione, data o altri contenuti dell'utente.

## 2.16.17

- Realtime ora rileva chiusure, timeout ed errori del canale e si riconnette
  automaticamente dopo due secondi.
- Ogni nuova sottoscrizione esegue una riconciliazione completa, recuperando
  modifiche avvenute durante la disconnessione senza attendere un evento nuovo.
- La rete di sicurezza in foreground passa da 15 a 1 minuto: Realtime resta il
  percorso immediato, mentre il pull periodico garantisce convergenza rapida.

## 2.16.16

- La coda di sincronizzazione non interpreta più l'aggiornamento interno del
  numero di tentativi come una nuova modifica, eliminando il lampeggio ciclico
  dell'indicatore di errore sul Web.
- La build Web riusa la risoluzione delle dipendenze già completata e non
  esegue il controllo WebAssembly non utilizzato, riducendo lavoro duplicato.
- Il workflow usa la generazione corrente dell'azione di checkout.
- La build Web usa un runner Ubuntu stabile per evitare fallimenti del pool
  GitHub prima ancora dell'inizializzazione del job.
- Il deployment Web usa esplicitamente il limite massimo di 10 minuti imposto
  da GitHub Pages; code eccezionalmente più lunghe restano un limite esterno.

## 2.16.15

- Navigazione tra Oggi, Prossime, Progetti, Impostazioni e dettaglio progetto
  resa più professionale con dissolvenza e spostamento minimo di 140 ms.
- Titolo della schermata, cambio data futura e passaggio tra lista e stato
  vuoto usano micro-animazioni da 110 ms, senza ritardare input o operazioni.
- Gli stati vuoti hanno ora icone discrete e testo contestuale.
- Il composer `+` conserva intenzionalmente apertura e chiusura a durata zero.

## 2.16.14

- La build Google Play verifica automaticamente gli aggiornamenti dopo il
  primo frame e al ritorno in primo piano, mostrando il flusso flessibile
  ufficiale di Play soltanto quando una nuova versione è disponibile.
- Il controllo manuale nelle Impostazioni usa la stessa API; se non è
  disponibile sul dispositivo, apre come fallback la scheda Play Store.
- Eliminato il doppio sync completo all'avvio causato dalla sovrapposizione tra
  sessione già attiva ed evento iniziale di autenticazione.
- La diagnostica anonima misura apertura composer/editor, cambio schermata,
  salvataggio, creazione e completamento, senza registrare titoli, note o URL.

## 2.16.13

- Gli aggiornamenti dello stato di sincronizzazione ricostruiscono soltanto la
  piccola icona nell'AppBar, non più l'intera schermata e tutte le attività.
- La creazione rapida riusa la cache dei progetti e non interroga SQLite nel
  momento in cui si preme Invio o Aggiungi.
- L'avvio usa una sola lettura condivisa per Inbox e cache progetti; la pulizia
  delle attività completate viene eseguita al massimo una volta al giorno.
- Il promemoria diagnostico giornaliero è ora una notifica discreta in basso;
  il pannello dettagliato si apre soltanto scegliendo `Apri`.

## 2.16.12

- Nelle Impostazioni della build Google Play compare ora `Aggiorna da Google
  Play`: apre direttamente la scheda ufficiale dell'app, mostrando il comando
  Aggiorna non appena la nuova versione è disponibile.
- Il controllo automatico dell'APK resta confinato alla distribuzione diretta;
  la build Play non apre mai lo Store da sola.

## 2.16.11

- Il completamento di un'attività risponde più rapidamente: conferma, spunta,
  dissolvenza e rimozione dalla lista terminano circa 90 ms prima.
- Aggiornamento incrementale pubblicato per verificare il recapito automatico
  tramite Google Play dopo la migrazione dal canale APK diretto.

## 2.16.10

- La privacy policy descrive correttamente la cancellazione dei dati
  sincronizzati tramite l'amministrazione del progetto Supabase privato.
- Il primo canale di test interno Google Play è configurato con lista tester e
  App Bundle firmato; Android diretto, Play e web restano versionati insieme.

## 2.16.9

- La release coordinata genera anche un Android App Bundle firmato, pronto per
  il caricamento su Google Play con la stessa chiave di upload degli APK.
- Le build Play e diretta sono separate: Play non dichiara il permesso di
  installazione APK e non mostra né esegue il controllo aggiornamenti GitHub.
- Aggiunta una privacy policy pubblica e minimale per la scheda Google Play.
- Il nome mostrato dal launcher Android è ora `Deterministic Todo`.

## 2.16.8

- Il composer mantiene stabile il massimo spazio occupato dalla tastiera fino
  alla chiusura, evitando salti durante gli assestamenti dell'IME Android.
- La spunta è ora una zona protetta: un gesto orizzontale iniziato sul controllo
  di completamento non può trascinare o mandare nel cestino l'attività.
- Lo swipe lungo verso sinistra sul corpo della riga e il relativo `Annulla`
  restano disponibili.

## 2.16.7

- Favicon e bookmark Chrome usano ora una superficie rossa piena senza angoli
  trasparenti, eliminando il bordo bianco imposto dallo sfondo del browser.
- Gli errori di rete della sincronizzazione attivano retry progressivi in
  foreground; l'outbox conserva tentativi e codice tecnico senza dati utente.
- Il controllo Lamport di progetti e sezioni passa da una query SQLite per
  elemento a un'unica lettura indicizzata per ogni sync completo.
- Rimossa la dipendenza diretta `collection`, non usata dal codice applicativo.

## 2.16.6

- Il composer richiede il focus prima di montare il foglio, permettendo ad
  Android di avviare la tastiera nello stesso frame dell'apertura.
- L'identità rossa è ora dichiarata esplicitamente per scheda e bookmark
  Chrome, favicon SVG/PNG, Apple touch icon, PWA e launcher Android.

## 2.16.5

- Il composer `+` si apre ora al primo frame senza attendere query SQLite o il
  caricamento delle preferenze; progetti e scelte recenti vengono precaricati e
  aggiornati in background.
- Aggiunto un test che impedisce di reintrodurre I/O prima dell'apertura.

## 2.16.4

- Il riconoscimento intelligente ora funziona anche modificando un'attività già
  esistente: espressioni come `domani` vengono evidenziate, convertite nella
  data pianificata e rimosse dal titolo al salvataggio.
- Aggiunto un test completo del percorso editor con sintassi intelligente.

## 2.16.3

- L'editor rispetta ora l'area sicura inferiore Android: il pulsante Salva non
  viene più coperto dalla barra di navigazione Samsung.
- Aggiunto un test completo della riprogrammazione: apertura Data, scelta del
  giorno, salvataggio e passaggio dell'attività allo stato pianificato.

## 2.16.2

- L'icona Android usa ora il formato adattivo nativo: il launcher applica
  direttamente la propria forma senza creare un doppio bordo bianco.
- Anche il fallback per dispositivi Android meno recenti riempie tutto lo
  sfondo, evitando angoli bianchi attorno all'icona.

## 2.16.1

- Nuova icona originale rossa con segno di spunta, coerente su Android, web,
  favicon e installazione PWA.
- Accento principale rosso Todoist-like e superfici chiare/scure più neutre;
  i colori semantici delle priorità restano distinti.

## 2.16.0

- Sync invisibile quando sano, indicatore soltanto dopo due secondi o in caso
  di errore/offline ed evidenziazione breve delle attività ricevute.
- Realtime incrementale: gli eventi vengono raggruppati per 120 ms e scaricano
  soltanto task, progetti e sezioni effettivamente modificati.
- Composer con ultimo progetto/priorità ricordati, selettore progetto e sintassi
  `#Progetto`/`p1`; URL grezzi trasformati in etichette leggibili.
- Ricerca unica per testo, descrizione, progetto e link, con filtri Oggi, senza
  data, ricorrenti e priorità alta.
- Menu attività con pressione lunga/clic destro, scorciatoie `N`, `/`, `Esc` e
  conservazione della posizione nelle liste.
- Import Todoist con rapporto finale esplicito e backup JSON immediatamente
  disponibile; nuova schermata minimale Salute dati nelle Impostazioni.

## 2.15.0

- Sincronizzazione Android↔browser guidata dagli eventi: outbox inviata subito,
  ricezione Supabase Realtime e aggiornamento Drift/UI senza ricaricare.
- Debounce di 120 ms, secondo passaggio se un evento arriva durante il sync e
  timer da 15 minuti conservato soltanto come recupero.
- Riconoscimento automatico di link `http://`, `https://` e `www.` in titoli,
  descrizioni, editor e nuovi import Todoist.

## 2.14.1

- Il fallback Android universale viene ora ricostruito a ogni release e pubblicato
  insieme agli APK per architettura, senza collegamenti a versioni storiche.
- La verifica finale rifiuta manifest con piattaforme mancanti, hash non validi o
  URL che non appartengono alla versione appena pubblicata.

# Funzioni completate e verificate

Aggiornato il 5 agosto 2026.

## Completate

- Scaffold Flutter nativo Android/macOS/Windows, senza target web.
- Schema SQLite tipizzato Drift con task, impostazioni, outbox persistente, WAL, tombstone e metadati Lamport.
- Creazione rapida dal solo titolo con Invio; Inbox e viste Oggi, Prossime, In attesa, Completate.
- UI adattiva con NavigationRail desktop e NavigationBar Android, tema chiaro/scuro e localizzazione italiana predisposta.
- Ordinamento Oggi deterministico e riordino manuale persistente.
- Modifica titolo, note, stato, “Mostra il”, scadenza, ora e tipo di ricorrenza esplicito.
- Ricorrenze giornaliere, settimanali e mensili, da calendario e dal completamento; chiave serie/occorrenza univoca e inserimento idempotente.
- Ricerca locale su titolo e note con ordine stabile.
- Notifiche locali pianificate, aggiornate e annullate; permessi Android/macOS e receiver Android al riavvio.
- Export JSON versionato e CSV; validazione, anteprima e import JSON con merge per versione.
- Migrazione Supabase PostgreSQL, RLS, indici, outbox remota e funzione deterministica `merge_task`.
- Worker push/pull non bloccante, retry implicito tramite outbox persistente, trigger su connessione e timer.
- Aggiornamento Android diretto nell’app con avanzamento, verifica SHA-256, firma release stabile e scelta automatica dell’APK per ABI.
- APK Android misurati a circa 19–23 MB per ABI, contro 59 MB universali.
- Ottimizzazioni runtime: stream SQLite attivi/completati separati e persistenti, indici schema 2, riordino senza scritture invariate, fusi/permessi notifiche differiti e controllo release ogni sei ore.
- Documentazione operativa Android e regole permanenti per mantenere codice, documentazione e GitHub allineati.
- Fuso IANA nativo Android per notifiche e task con ora, senza dipendenza dalla rete.
- Export esplicito e idempotente al Calendar Provider Android, con preferenza stabile per Google primario e aggiornamento dello stesso evento.
- Launcher Android aggiornato per scaricare l’artefatto ARM64 del Galaxy S21 prodotto dalla CI split-per-ABI.
- Impostazioni raggiungibili dall'AppBar Android, con ritorno esplicito alla navigazione principale.
- Vista Prossime ordinata e raggruppata per giorno, con export calendario opzionale per ogni attività datata.
- Creazione in una riga con riconoscimento locale di date e orari italiani comuni.
- Sessione Supabase persistente nel secure storage, rinnovo automatico e collegamento account una tantum; la verifica live resta subordinata a un progetto remoto configurato.
- Stato sync reale nelle Impostazioni e protezione single-flight contro esecuzioni di rete sovrapposte.
- Anteprima della data naturale durante la digitazione e correzione della ripianificazione/annullamento notifiche dopo modifica o eliminazione.
- Workflow Android di pubblicazione protetto: ricompilazione, test, APK per ABI, manifest/hash, release `latest` e verifica pubblica nello stesso processo.
- Release pubblica `v1.1.0` build 8 con APK ARM64/ARM32/x86_64 e manifest verificato byte per byte dopo il download pubblico.
- Progetto Supabase personale e publishable key pubblica collegati automaticamente a launcher e build Android/macOS.
- Migrazione Supabase applicata e endpoint RLS `tasks`/`sync_operations` verificati; autenticazione Email attiva con conferma una tantum.
- Release pubblica `v1.1.1` build 9 con Supabase configurato, manifest pubblico confrontato byte per byte e hash ARM64 verificato.
- Composer mobile dal basso e calendario futuro orizzontale con filtro per giorno e conteggi, senza nuovi servizi o dipendenze runtime.
- Android impostato come primo canale di collaudo: pubblicazione automatica per ogni push funzionale versionato e controllo aggiornamenti a ogni apertura.
- Navigazione Android ridotta a Oggi/Prossime/Completate, timeline fino a dieci anni con salto data ed evidenziazione live della sintassi intelligente.
- Schema SQLite 3 predisposto per import Todoist idempotente: progetti, sezioni, priorità e identificativi esterni univoci, senza incorporare metadati nel titolo.
- Repository sorgente pubblico con cronologia pulita e licenza MIT; release 1.4.1 dedicata alla verifica end-to-end di firma, token fine-grained e pubblicazione Android dalla nuova infrastruttura.
- Ricorrenze rapide Todoist-like per giorni, giorni della settimana, settimane, mesi e anni; completamento con creazione idempotente dell'occorrenza successiva.
- Ricorrenze avanzate per giorno del mese, giorno/mese annuale e giorno ordinale mensile; parser Todoist avviato con anteprima read-only e blocco esplicito delle espressioni ambigue.
- Frasi intelligenti per feriali, weekend, ultimo giorno/weekday mensile, intervalli dal completamento e date relative; piano Todoist tipizzato con progetti, sezioni, task, descrizioni, priorità, date, fusi, ricorrenze e UUID v5 deterministici.
- Import Todoist attivo-only completo: anteprima obbligatoria, transazione SQLite atomica, reimportazione senza duplicati, outbox per tutti i task e sincronizzazione Supabase di progetti, sezioni, priorità e identificativi esterni.
- Il vero export personale è stato simulato soltanto in memoria: 5 progetti, 13 sezioni, 110 task attivi, 46 pianificati e 25 ricorrenti; seconda esecuzione con zero duplicati. Il file personale non è stato copiato nel repository.
- Vista Progetti Android con sezioni e attività attive, Completate spostata nelle Impostazioni e rendering cliccabile dei link Markdown Todoist senza URL estesi in elenco.
- Progetti personalizzabili in stile Todoist: selettore con colori/conteggi, layout elenco o bacheca persistente per progetto, creazione di progetti/sezioni/task e spostamento task da editor.
- Diagnostica locale strutturata e rotante su Android/macOS, esportabile su richiesta e priva di contenuti utente o credenziali.
- Release 2.3.0: animazione breve al completamento, indicatore visibile delle ricorrenze, bandierine P1–P4 coerenti con le priorità importate da Todoist e navigazione gerarchica con il tasto Indietro Android.
- Release 2.3.1: descrizioni naturali delle ricorrenze in elenco, editor attività compatto come bottom sheet e completamento in due fasi con conferma verde prima della dissolvenza.
- Release 2.4.0: densità visiva ridotta sulla base del confronto con Todoist, editor sotto i 460 px, date non duplicate, priorità integrate nel checkbox, contatori rimossi da Prossime e Inbox Todoist nascosta dai progetti.
- Release 2.5.0: Progetti con intestazione unica, Impostazioni raccolte, guide testuali rimosse, priorità con tinta leggera e ordinamento automatico, chiusura tastiera/composer Android con una sola pressione e animazione inversa da 90 ms.
- Release 2.6.0: descrizioni Todoist visibili sotto il titolo con link compatti, eliminazione via swipe sempre annullabile, filtro “Tutte” rimosso da Prossime e sincronizzazione condensata in una sola riga.
- Release 2.7.0: Progetti ridisegnato come navigazione gerarchica minimale compatibile con Todoist, composer aperto/chiuso in 80/45 ms con descrizione opzionale immediata e ora rimossa dalla UI e dalla creazione naturale.
- Release 2.8.0: supporto orario rimosso da parser, import, sync, calendario e runtime; eliminati plugin di notifiche/fusi e receiver Android. Priorità P1–P4 impostabile direttamente dal composer rapido.
- Release 2.9.0: swipe verso il cestino limitato a destra→sinistra con soglia 62% e Undo; composer rapido riusato dentro Progetti; descrizioni ridotte a una riga; editor senza Stato e Scadenza, con stato derivato dalla sola data; Google Calendar spostato nel menu `⋮`. Link Todoist e highlighting naturale estratti da `main.dart` in componenti UI dedicati.
- Release 2.10.0: menu minimale `⋮` su progetti e sezioni con rinomina, spostamento su/giù ed eliminazione reversibile con Undo; riordino e archiviazione incrementano la versione logica e convergono tramite la sincronizzazione esistente senza cancellare task o mapping Todoist.
- Release 2.11.0: composer/editor e completamento accelerati; padding tastiera immediato; Prossime trasformata in timeline lazy con giorni vuoti, senza chip e senza doppio Indietro; editor link senza URL Markdown visibili; Completate limitata a 200 record con retention di 365 giorni; reset locale transazionale protetto; controllo update ogni sei ore soltanto in foreground.
- Release 2.11.1: controllo aggiornamenti con query cache-buster e header `no-cache`, per evitare che la cache CDN GitHub ritardi il prompt dopo una nuova pubblicazione.
- Release 2.12.0: apertura e chiusura del composer `+` senza animazione; link delle descrizioni presentati come chip apribili e rimovibili senza URL grezzi; Cestino in Impostazioni con ripristino di attività, progetti e sezioni.

## Verificate in questa macchina

- `flutter analyze`: nessun problema.
- `flutter test`: suite completa superata, inclusi dominio, database, UI Android, parser italiano, calendario idempotente e import Todoist ripetibile.
- Build macOS tentata: non eseguibile perché `xcodebuild` non è installato/selezionato in questa macchina.
- Build Android tentata: non eseguibile perché Android SDK/`ANDROID_HOME` non è presente.
- Build Windows non eseguibile da macOS; va verificata su Windows come descritto nel README.

## Non dichiarate complete

Vedi “Limiti noti” nel README e [TODO_NEXT.md](TODO_NEXT.md): pairing/sync live, recupero cestino, selezione multipla/undo, scheduler automatico dell'orizzonte calendario e backup cifrato. Notifiche, calendario e aggiornamento OTA superano build/test, ma i flussi completi non sono ancora stati provati fisicamente sul Galaxy S21; Supabase non è stato provato contro un progetto reale.
# Versione 2.1.0

- Reimport Todoist incrementale tramite checkpoint `updated_at`: nuovi record aggiunti, record cambiati aggiornati, nessun duplicato.
- Opzione “Sostituisci da zero” con doppia conferma, limitata ai dati Todoist e compatibile con la sincronizzazione Android/macOS.
- Import del layout elenco/bacheca indicato dal progetto Todoist.
- Log diagnostico con conteggi separati per aggiunte, aggiornamenti e rimozioni.

# Versione 2.1.1

- Polling di sincronizzazione ridotto da 5 a 15 minuti, sospeso quando l’app non è in primo piano e riattivato immediatamente al ritorno.
- Upload di progetti e sezioni invariati eliminato tramite fingerprint Lamport locale; nessuna modifica allo schema Supabase.
- Outbox compattata per attività e confronto del pull remoto eseguito in batch, eliminando RPC e query SQLite duplicate.
- Simboli Dart separati dagli APK release e conservati privatamente per 30 giorni, riducendo lo storage sul dispositivo senza perdere la possibilità di diagnosticare crash.
- APK ARM64 2.1.2 misurato a 22.364.249 byte: circa 1,25 MB (5,3%) in meno rispetto alla 2.1.1.

# Versione 2.2.0

- Profilazione locale event-driven di avvio, RAM RSS, dimensione SQLite, code di sync e frame build/raster.
- Metriche del sync per durata, volume remoto, upload compattati e progetti/sezioni invariati saltati.
- Nessun analytics, nuovo polling o contenuto utente nei log; esportazione manuale dalle Impostazioni.
- Promemoria interno massimo una volta al giorno con esportazione diretta e prompt di analisi pronto da copiare.
- Oggi esclude il backlog senza data appartenente ai progetti, mantenendo visibili le attività libere senza progetto.
- Conteggio frame lenti sia sul budget 60 Hz sia sul budget 120 Hz del Galaxy S21.
# 2.12.1

- Ripristino automatico delle migrazioni SQLite interrotte: macOS e Android possono completare lo schema locale senza perdere attività quando alcune colonne erano già state create.
- Aggiunto un test di regressione che parte intenzionalmente da una migrazione versione 2 rimasta a metà.

# 2.13.0

- Aggiunto il client browser Flutter per macOS e Windows con SQLite Drift WebAssembly, sincronizzazione Supabase e import/export compatibili.
- La web app rifiuta esplicitamente uno storage soltanto volatile; i salvataggi non vengono mai presentati come persistenti se il browser non li supporta.
- Aggiunto deployment automatico GitHub Pages insieme alla release Android.
- Rimossi target, workflow, launcher e build locali macOS/Windows obsoleti; le utilità Android residue sono state raccolte in `tools/launchers`.
- README, architettura, handover e regole operative aggiornati al modello Android + browser.

# 2.13.1

- Rimossa la vecchia navigazione desktop con Inbox e In attesa: Chrome usa la
  stessa interfaccia minimale Oggi/Prossime/Progetti di Android.
- Contenuto centrato su schermi larghi, stesso composer `+`, stessa barra
  inferiore e nessun titolo o campo di inserimento desktop duplicato.

# 2.13.2

- Chrome mantiene le sole sezioni Oggi/Prossime/Progetti ma, sopra 900 px, usa
  una barra laterale compatta, un'area di lavoro più ampia e comandi adatti a
  mouse e tastiera; sui viewport stretti resta identico ad Android.
- Il workflow web osserva tutti i percorsi che possono produrre una release
  Android: ogni aggiornamento Android avvia automaticamente anche il deployment
  Chrome dello stesso commit e della stessa versione.

# 2.14.0

- Release Android e Chrome consolidate in un'unica pipeline: verifica condivisa,
  build di entrambi i canali, deploy web precedente alla pubblicazione Android e
  confronto finale pubblico di versione, build e commit.
- Logging browser persistente in IndexedDB; export Android e web comprensivo del
  blocco ruotato precedente, con versione/build e sessione anonima per apertura.
- UI suddivisa in moduli dedicati per impostazioni, account sync, cestino, task
  ed editor; `main.dart` ridotto senza cambiare dominio o persistenza.
- Documentazione riorganizzata in changelog, stato e runbook operativi.
