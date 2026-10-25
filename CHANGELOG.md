# Changelog

Cronologia delle modifiche distribuite, dalla più recente.

## 2.121.2 (build 311) — Nessun doppione dal Cestino dopo Annulla

- Dopo l'Annulla di un completamento, la copia dell'occorrenza annullata non
  compare più nel Cestino: ripristinarla avrebbe duplicato la ricorrente. Se
  un ripristino creerebbe comunque un doppione, viene rifiutato con un
  messaggio.

## 2.121.1 (build 310) — Anche gli APK di agosto

- La pulizia cancella anche gli APK scaricati con il vecchio nome di agosto
  2026 (solo versione, senza build), che la 309 lasciava: sul Galaxy erano
  tre file per 68 MB.

## 2.121.0 (build 309) — Spazio liberato e Calendario in background più affidabile

- Gli aggiornamenti interni lasciavano sul telefono ogni APK scaricato (circa
  24 MB l'uno). Ora all'avvio e dopo ogni aggiornamento vengono cancellati
  quelli di versioni già installate; un APK più recente in attesa di
  installazione resta.
- L'invio del Calendario in background non segna più come fallito un invio
  che trova un altro invio in corso: aspetta e lo ripete. I job svegliati
  insieme per lo stesso stato del calendario fanno il lavoro una volta sola.
- Il motivo di ogni nuovo tentativo è registrato senza contenuti (solo classe
  di errore e conteggi) e leggibile con il provider di diagnostica ADB.
- Tolti i permessi non usati aggiunti dal plugin degli aggiornamenti e
  attivato il gesto «indietro» predittivo di Android, con la stessa
  navigazione di prima.

## 2.120.1 (build 308) — Release stabile e Todo Test: ricorrenti che non spariscono dopo Annulla

- Completare una ricorrente, premere Annulla e poi completarla di nuovo
  interrompeva la serie: il messaggio annunciava la prossima occorrenza, che
  però restava nel Cestino. Ora il nuovo completamento la ripristina. Se una
  ricorrente è sparita così in passato, si recupera dal Cestino.
- Il test sul Galaxy della vista Prossime a 400 px non risente più della
  tastiera reale (solo test, nessun cambiamento nell'app).

## 2.120.0 (build 307) — Bordo ambra anche sugli inviti, e toglibile a mano

- Gli inviti a cui non hai ancora risposto (per esempio Teams) che cadono in
  un orario Semble prenotabile ora hanno il bordo ambra e la notifica come
  gli altri eventi. Le fasce verdi libere non cambiano.
- Nella scheda di un evento con il bordo ambra, «⋯ → Togli il bordo ambra»
  lo toglie solo da quell'evento, senza toccare Semble né le disponibilità;
  da lì stesso «Rimetti il bordo ambra». Vale anche per la notifica. Se
  l'evento cambia orario il bordo torna.

## 2.119.0 (build 306) — Notifica che porta al blocco, Calendario e Impostazioni più ordinati

- Toccando la notifica di un evento in orario Semble si apre direttamente la
  scheda dell'evento, con «Blocca in Semble» in cima. Se gli eventi sono più
  di uno si apre il giorno del primo.
- Intestazione del Calendario più pulita: tolti l'icona Oggi e il contatore
  dei calendari («16/32»); «Calendari e filtri» è nel menu «Altro».
- Impostazioni divise in sezioni (Attività, Calendario e lavoro, Movimento,
  Dati). La pagina Semble mostra prima lo stato, poi cosa fa nel
  Calendario; i campi di collegamento sono raccolti e si chiudono quando la
  chiave funziona.
- Manutenzione del codice: eliminate le viste Mese, Elenco e 3 settimane
  (già tolte dal menu nella build 299; una scelta salvata apre 4 settimane),
  servizio Semble diviso in client, impostazioni e livello del Calendario,
  conversioni dell'ora di Londra in un solo modulo con test per ora legale e
  solare, una sola copia degli eventi e un registro delle notifiche comune.

## 2.118.0 (build 305) — Avviso Semble anche per gli eventi creati in Todo

- Quando Todo va in background, controlla subito gli eventi in orario
  Semble prenotabile non ancora segnalati: anche un evento creato o visto
  nell'app ora riceve la notifica, senza aspettare un altro cambiamento del
  calendario.

## 2.117.0 (build 304) — Avviso per eventi arrivati in orario Semble

- Se mentre l'app è chiusa arriva nel calendario un evento (Teams, KCL,
  Google…) che cade in un orario prenotabile di Semble, una notifica lo
  segnala con giorno e ora, senza titolo. Toccandola si apre il Calendario:
  l'evento ha il bordo ambra e si blocca in Semble con un tocco.
- Ogni evento è segnalato una sola volta. Interruttore in Impostazioni →
  Semble, «Avvisa per eventi in orario Semble» (attivo).
- Nessuna chiamata a Semble in background: usa le disponibilità lette
  l'ultima volta che l'app era aperta.

## 2.116.0 (build 303) — Proposta di blocco e visite annullate

- Se crei un evento che cade in un orario prenotabile di Semble, il
  messaggio di conferma offre subito **Blocca in Semble** (10 secondi).
- Una visita annullata in Semble resta nel Calendario come sagoma vuota e
  barrata, «Annullata · tipo», finché il suo orario non è passato: lo slot
  torna verde come libero.

## 2.115.0 (build 302) — Bordo ambra solo sul futuro

- Il bordo ambra (e il pulsante «Blocca in Semble») compare solo sugli
  eventi non ancora finiti.

## 2.114.0 (build 301) — Blocca dall'evento, griglie più pulite

- Toccando un evento con il bordo ambra, la scheda ha in alto il pulsante
  **Blocca in Semble**: un tocco blocca in Semble l'orario dell'evento
  (Other, senza commento), con «Annulla» per 8 secondi. Poi il bordo
  sparisce.
- Tolta la barretta di disponibilità sotto la data nelle viste a 2 e 4
  settimane.

## 2.113.0 (build 300) — Ritocchi Semble

- Nelle viste a più settimane toccare un gruppo «N visite» apre il giorno;
  nella giornata il gruppo si espande come prima.
- Il blocco Semble è sempre di tipo Other e senza commento: il modulo non
  chiede più il tipo.
- Il messaggio «Bloccato in Semble» sparisce da solo dopo 8 secondi
  (prima restava finché non lo si chiudeva).
- Gli eventi che non sono visite ma cadono in un orario prenotabile di
  Semble hanno un bordo ambra, nelle giornate, nelle settimane e nelle
  griglie.
- Palette Semble tutta verde: visite verde pieno, disponibilità verde
  chiaro, indisponibilità a righe grigio-verdi; leggibile anche in tema
  scuro.

## 2.112.0 (build 299) — Calendario più semplice

- Viste: restano 4 settimane, 2 settimane, Settimana e 3 giorni (toccando
  un giorno si apre la giornata). Tolte 3 settimane, Mese ed Elenco: se
  erano la vista salvata, il Calendario si apre su 4 settimane.
- L'Assistente ✨ passa nel menu «Altro» della barra.
- Scheda di un evento: in vista Partecipa, Modifica ed Elimina; Nascondi,
  Modifica solo in Todo, Preparare, Follow-up e Apri nel calendario sono
  sotto il pulsante «⋯».
- Nuovo evento: subito titolo, giorno e ore; calendario, Ripeti, fuso,
  luogo e note sotto «Altre opzioni».

## 2.111.0 (build 298) — Blocco Semble più semplice

- In cima al modulo **Nuovo evento** c'è la scelta **Evento | Blocco
  Semble** (al posto dell'icona senza testo). Con «Blocco Semble» il modulo
  mostra solo giorno, ora di inizio e fine e il tipo; il pulsante in alto
  diventa **Blocca** e crea subito il blocco, senza una seconda scheda.
- Tipi rapidi: Admin, Ferie, Malattia, Altro; gli altri sotto «Altri tipi».
  L'ultimo tipo usato resta selezionato finché l'app è aperta.
- Se Semble rifiuta, il modulo resta aperto con il motivo. «Annulla» nello
  snackbar per 8 secondi resta invariato.

## 2.110.0 (build 297) — Blocca orari in Semble dal Calendario

- Nel modulo **Nuovo evento** (anche aperto trascinando su uno spazio vuoto
  del Calendario) c'è l'icona **Blocca in Semble**: con gli orari del modulo
  apre una scheda che mostra giorno, orario (e l'ora di Londra se diversa) e
  il tipo (Altro, Admin clinico, Admin, Riunione, Ferie, Malattia, CPD,
  Studio). «Blocca in Semble» crea un'indisponibilità di un giorno con
  commento «Da Todo»; non viene salvato nessun evento nel telefono. Per
  8 secondi «Annulla» cancella esattamente quel blocco.
- Serve l'**ID stanza Semble** nel nuovo campo di Impostazioni → Semble: la
  chiave non può leggere le stanze. Senza, l'icona non compare.
- È la prima scrittura verso Semble e parte solo dopo la conferma. Blocchi
  oltre la mezzanotte di Londra sono rifiutati.

## 2.109.0 (build 296) — Semble anche fuori dal Regno Unito

- Gli orari di Semble sono ora di Londra: ora vengono convertiti nell'ora
  del telefono con le regole britanniche di ora legale e solare (ultima
  domenica di marzo e di ottobre). In Italia una visita alle 10:00 di Londra
  compare alle 11:00, come la copia del calendario Google, e la stima del
  lavoro privato usa l'orario giusto.
- Le disponibilità Semble non sono più nascoste fuori dal fuso di Londra:
  sono spostate nell'ora del telefono. Le Impostazioni lo indicano.

## 2.108.0 (build 295) — Orari Semble giusti, durata dal titolo

- Correzione delle build 291–294: l'API di Semble manda l'ora di Londra
  etichettata come UTC. Ora le cifre sono lette così come sono, quindi le
  prenotazioni coincidono con Semble e con il calendario. Il calendario
  Semble non viene più spostato di un'ora: era giusto.
- Le visite Semble nel Calendario finiscono quando finisce il tempo clinico
  scritto nel titolo («15 min», «60'»): i 15 minuti di pausa che Semble
  aggiunge a ogni slot non sono più disegnati come visita, e non diventano
  verdi negli spazi liberi.

## 2.107.1 (build 294) — Correzione dell'ora per giornata intera

- Le visite Semble a mezz'ora o un'ora di distanza non coincidevano con
  Semble: la copia del calendario un'ora prima cadeva spesso sull'orario di
  un'altra prenotazione e la build 292 la lasciava dov'era. Ora la decisione
  è presa per giornata: se le visite del calendario Semble coincidono con le
  prenotazioni più spesso spostate di un'ora che al loro orario, si spostano
  tutte insieme.

## 2.107.0 (build 293) — Stima dalle prenotazioni Semble

- Con chiave e cognome in Impostazioni → Semble, la **Stima lavoro privato**
  prende le visite Semble del mese direttamente dalle prenotazioni: tipo di
  visita, orario ed esito (svolta, DNA, cancellata) arrivano da Semble e non
  più dai titoli e dagli orari del calendario. Le copie del calendario Semble,
  e quelle di altri calendari privati che iniziano con una prenotazione
  (anche un'ora prima), non sono contate. heydoc e le altre visite restano
  dal calendario.
- Una prenotazione cancellata e sostituita nello stesso minuto non conta
  come cancellazione. Senza chiave, cognome o rete la stima resta quella
  per titolo e lo dice.

## 2.106.0 (build 292) — Visite Semble all'ora giusta

- Il calendario Google collegato a Semble scrive l'ora UTC come se fosse
  l'ora di Londra: con l'ora legale ogni visita compare un'ora prima. Con
  chiave e cognome in Impostazioni → Semble, una visita del calendario Semble
  che inizia esattamente un'ora (lo scarto UTC del telefono) prima di una
  prenotazione reale viene mostrata all'ora della prenotazione, con il suo
  titolo; la copia letta da Semble non viene più aggiunta. Gli eventi degli
  altri calendari non vengono mai spostati e il calendario del telefono non
  viene modificato.
- La Stima lavoro privato abbina DNA e cancellazioni anche a queste visite.
- Correzione delle note della build 291: l'API manda gli orari in UTC con
  `Z`; la lettura degli orari senza fuso resta come difesa ma non era la
  causa dei doppioni.

## 2.105.3 (build 291) — Orari Semble corretti

- Semble manda gli orari delle prenotazioni in UTC senza indicarlo: l'app li
  leggeva come ora del telefono e, con l'ora legale, le copie dirette
  comparivano un'ora prima di quelle del calendario, quindi doppie. Ora un
  orario senza fuso è letto come UTC. Lo stesso errore impediva di abbinare
  DNA e cancellazioni nella Stima lavoro privato.

## 2.105.2 (build 290) — Niente prenotazioni Semble doppie

- La prenotazione letta da Semble sparisce appena un qualsiasi evento con
  orario inizia nello stesso minuto, non solo uno del calendario chiamato
  Semble: la copia iCal può stare in un calendario con un altro nome e nella
  build 289 compariva due volte.

## 2.105.1 (build 289) — Prenotazioni Semble subito nel Calendario

- Con chiave e cognome in Impostazioni → Semble, le prenotazioni delle
  prossime 4 settimane compaiono nel Calendario appena esistono in Semble,
  senza aspettare il giro iCal → Google → telefono. Hanno il colore del
  calendario Semble, come titolo solo il tipo di visita e si aprono in una
  scheda di sola lettura con il pulsante «Apri Semble».
- Quando arriva la copia dal calendario Google (stesso minuto di inizio nel
  calendario Semble) quella diretta sparisce: nessun doppione. Le cancellate
  non compaiono; se il calendario Semble è nascosto non compare nulla.
- Lettura insieme alle regole di disponibilità, al massimo ogni 15 minuti
  all'apertura del Calendario; niente salvato, niente paziente.

## 2.105.0 (build 288) — DNA e cancellazioni da Semble nella stima

- **Stima lavoro privato** legge da Semble le prenotazioni del mese con il
  proprio cognome (nuovo campo in Impostazioni → Semble) e, per ogni visita
  del calendario Semble, l'esito registrato in reception: le visite segnate
  DNA (did not attend) e le prenotazioni cancellate in Semble escono dai
  totali e sono mostrate a parte con l'importo non maturato.
- Si leggono solo orario, tipo di visita, nome del medico e i quattro
  momenti del percorso (arrivo, visita, uscita, DNA): mai paziente, commenti,
  riferimenti o motivo di cancellazione. Nulla viene salvato. Senza chiave,
  senza cognome o se Semble non risponde la stima resta quella di prima e lo
  dice.

## 2.104.2 (build 287) — Solo gli spazi davvero liberi

- Il verde Semble (fasce in Giorno, 3 giorni e Settimana, barretta in 4
  settimane e Mese) non copre più il tempo già occupato da eventi con
  orario: resta solo dove si è prenotabili e liberi. Contano tutti gli
  eventi mostrati, visite Semble e riunioni di altri calendari; non contano
  eventi di giornata intera, attività Todo e inviti senza risposta. Le
  indisponibilità restano grigie com'erano.

## 2.104.1 (build 286) — Disponibilità Semble anche in 4 settimane e Mese

- Nelle viste 4 settimane e Mese ogni giorno con regole Semble mostra sotto
  la data una barretta sottile dalle 7 a mezzanotte: verde dove si è
  prenotabili, grigia dove l'orario è bloccato. Gli orari esatti sono letti
  dal lettore di schermo.
- Legenda di Impostazioni → Semble con colori pieni, leggibili anche nel
  tema scuro.

## 2.104.0 (build 285) — Disponibilità Semble nel Calendario

- Nuova voce **Impostazioni → Semble** (solo Android): si incollano la chiave
  API Semble e il proprio User ID; la chiave resta cifrata nel Keystore del
  telefono, fuori da backup, log e Supabase.
- Calendario: nelle viste Giorno, 3 giorni e Settimana le regole di
  disponibilità Semble compaiono dietro agli eventi, verde dove si è
  prenotabili e a righe grigie dove Semble blocca l'orario (ricorrenze
  settimanali, aggiunte una tantum, indisponibilità ed esclusioni).
- Sola lettura: l'app invia a Semble soltanto `__typename` per verificare la
  chiave e la lettura di `availabilityRules`; nessuna mutazione, nessun
  campo stanza o commento. Gli appuntamenti prenotati restano quelli del
  calendario Google alimentato dal feed iCal di Semble, senza duplicati.

## 2.103.1 (build 284) — Istruzioni diagnostiche indipendenti dall'assistente

- Il dialogo delle prestazioni invita a usare un assistente AI a scelta, senza
  indirizzare esclusivamente a Codex. Copia del prompt ed esportazione dei log
  mantengono il comportamento esistente e non inviano nulla automaticamente.

## Versioni precedenti

Archivio per mese:
[ottobre 2026, build 190–283](docs/archive/changelog/2026-10.md),
[settembre 2026, build 168–189](docs/archive/changelog/2026-09.md),
[agosto 2026 e prime versioni](docs/archive/changelog/2026-08.md).
