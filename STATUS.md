# Stato corrente

Aggiornato il 12 agosto 2026.

## Distribuzione

- Canali supportati: Android nativo e browser Chrome/Edge.
- Versione coordinata corrente: **2.25.1 build 109**, finestra del test passivo
  estesa a sette giorni. La 2.25.0 build 108 introduce classificazione passiva
  cammino/corsa/trasporto e calibrazione distinta delle falcate. La 2.24.2 build 107 aggiunge export diagnostico Drive
  giornaliero con retention di 15 file. La 2.24.1 build 106 riduce la memoria
  in background e telemetria PSS Android. La 2.24.0 build 105 introduce layout compatto di
  Movimento e confronto Google Fit persistente con timeout/retry → JSON Drive. La base funzionale
  **2.22.3 build 95** ha superato pubblicazione diretta, Google Play interno,
  Web e controllo finale di parità.
- Il test interno Google Play è attivo. Dalla build 65 la pipeline pubblica automaticamente nel
  test interno; la produzione resta manuale e subordinata al test chiuso.
- Un solo workflow coordina web e Android e rifiuta versioni, build o commit
  discordanti; l'AAB raggiunge il track Play interno appena supera test e build,
  mentre APK diretti e Web continuano in parallelo.
- La stessa pipeline produce APK per gli aggiornamenti diretti e AAB firmato
  per Google Play.

## Dati e sincronizzazione

- SQLite Drift è la fonte locale immediata; Supabase con RLS è la replica
  personale facoltativa.
- Le scritture locali entrano in una outbox persistente e vengono inviate
  subito. Le ricevute remote sono immutabili e i retry usano inserimenti
  idempotenti senza richiedere permessi di aggiornamento.
- Supabase Realtime notifica Android e browser; dalla 2.16.0 vengono richiesti
  soltanto gli ID cambiati. Il canale si riapre dopo errori o timeout; un
  controllo completo ogni dieci minuti recupera eventi persi, riprese e periodi
  offline mentre l'app è visibile. Quando l'app passa in background il canale
  viene rimosso per liberare socket e memoria; al resume viene ricreato prima
  del pull di recupero.
- Task, progetti, sezioni, priorità, date civili, ricorrenze e tombstone sono
  sincronizzati. Il tipo `reference` della 2.18.0 resta leggibile come normale
  task per non perdere dati. Non si sincronizzano segreti o contenuti dei log.
- Le occorrenze ricorrenti hanno ID deterministici condivisi tra dispositivi;
  il client riconcilia anche le collisioni storiche `23505` scegliendo la
  versione Lamport più recente.

## Esperienza corrente

- Oggi, Prossime, Progetti, ricerca e composer condividono lo stesso modello su
  Android e web, con layout desktop adattivo. Progetti è l'unico sistema di
  organizzazione persistente esposto nell'interfaccia.
- `Ctrl/⌘ K` apre il comando universale: testo libero cerca, `+` crea, `>`
  naviga e `#` limita la ricerca a un progetto. Sul desktop una task selezionata
  si modifica direttamente nel pannello laterale opzionale.
- Il composer riconosce linguaggio naturale, `#Progetto`, `p1`–`p4` e link;
  ricorda il progetto recente, parte sempre senza priorità e resta fermo durante
  gli assestamenti della tastiera Android.
- Nel campo titolo Invio fisico conferma sia la creazione sia la modifica in
  ogni sezione; la descrizione conserva il comportamento multilinea.
- Le scorciatoie globali richiedono Ctrl/⌘: caratteri come `n` e `/` restano
  testo normale quando un editor è attivo.
- La spunta è separata dallo swipe: completamento e avanzamento della ricorrenza
  non possono più avviare per errore il trascinamento verso il cestino. La riga
  resta ferma durante la conferma e viene rimossa solo dopo la dissolvenza.
- L'Undo usa un solo comportamento per task, progetti e sezioni e, sulle
  ricorrenze, inverte atomicamente anche la nuova occorrenza.
- L'import Todoist supporta aggiornamento e sostituzione idempotente di task,
  progetti e sezioni e produce un rapporto prima del backup.
- Impostazioni contiene Cestino, attività completate, diagnostica e Salute dati;
  gli stati sani restano fuori dall'interfaccia principale.
- Su Android, Movimento è una quarta destinazione principale accanto a
  Progetti. Camminata è l'azione primaria; Drive, export manuali e BLE sono
  raccolti negli strumenti avanzati.
- Android contiene il modulo separato `runtracker`: registra corse usando il
  GPS del telefono in foreground, salva campioni e scarti in Room ed esporta
  GPX. La prima prova BLE è limitata a scansione, connessione e batteria.
- Il modulo legge il totale passi aggregato da Health Connect e
  conserva distanza e calorie attive stimate in Room. Activity Recognition
  distingue cammino, corsa e trasporto senza GPS permanente; falcate separate
  vengono calibrate dopo tre sessioni valide per tipo. Peso personale e
  attribuzione precisa attraverso mezzanotte/reboot restano da completare. Le sessioni leggono inoltre il
  contatore hardware Android e possono confrontare l'ultima attività con i
  dati attribuiti a Google Fit in Health Connect. Camminata e corsa sono
  sessioni distinte; la camminata applica un limite anti-salto GPS dedicato di
  6 m/s e non accumula fix privi di nuovi passi quando il sensore è attivo.
  I GPX reali verificati non contengono battito, cadenza o dati del Bip U;
  l'integrazione Amazfit resta una fase successiva in sola lettura. Il quadro è in
  [docs/HANDOFF.md](docs/HANDOFF.md).

## Verifica

- Analisi statica senza errori.
- 123 test Flutter superati, incluso uno scenario di convergenza con due
  database indipendenti che rappresentano Android e Web.
- I test JVM coprono filtro GPS, gate passi, timeline, reset/duplicati del
  contatore e stime. Build Android, firma, manifest pubblico e parità con Web
  sono verificati dalla pipeline coordinata.
- La build 98 ha confermato il gate durante due soste: 0 m nella prima e circa
  1,5 m nella seconda. Ha inoltre isolato il blocco del confronto automatico:
  Health Connect richiede il consenso separato per le letture in background.
  La build 99 dichiara e richiede tale consenso, ma sul Galaxy S21 non ha
  riprogrammato né riesportato la sessione 14. La build 100 ha aggiunto il
  recupero in primo piano, ma lo stato persistito era `scheduled`, non
  `permission_required`. La build 101 recupera qualunque stato non concluso. Il
  controllo ADB ha poi confermato permessi corretti e due job conclusi senza
  aggiornamento Drive: la build 102 conserva il codice di errore, riesporta
  ogni tentativo e non lascia più il fallback riuscito su `scheduled`. Il test
  reale della 102 non ha avviato il recupero perché il gate leggeva lo stato
  globale di una sessione precedente; la 103 usa lo stato della sessione più recente
  e ha completato il confronto della sessione 14. Il provider Drive ha però
  conservato il vecchio file nonostante l'esito locale positivo; la 104 forza
  troncamento e sincronizzazione e verifica la dimensione scritta. Anche la
  104 non ha aggiornato il file remoto: la 105 usa quindi sidecar immutabili,
  lo stesso modello create-only affidabile degli export iniziali.
- La 105 introduce inoltre un audit passivo, esteso a sette giorni dalla build
  109: WorkManager
  legge una volta ogni sei ore ma produce al massimo un report definitivo per
  giorno precedente, senza GPS o servizio permanente.
- Restano da collaudare sulla build 109 la finestra estesa e, dalla build 108,
  la classificazione su almeno tre giorni
  misti (cammino, corsa e treno/auto), lo schema 2 dei report Drive e la
  calibrazione dopo tre sessioni valide per tipo; resta inoltre il BLE reale
  con Bip U. I test brevi hanno già validato passi, Drive e confronto Health
  Connect.
- Restano manuali il collaudo sul Galaxy S21, Google Calendar e il passaggio
  definitivo dall'ultimo export Todoist; vedi [TODO_NEXT.md](TODO_NEXT.md).

Architettura: [docs/ARCHITETTURA.md](docs/ARCHITETTURA.md). Procedure:
[docs/operations/](docs/operations/). Cronologia: [CHANGELOG.md](CHANGELOG.md).
