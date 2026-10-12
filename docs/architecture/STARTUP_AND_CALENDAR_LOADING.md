# Avvio locale e caricamento Calendario — build 260

## Confini

- `services/app_runtime.dart` apre il repository locale; avvia Supabase
  separatamente dopo il primo frame dell'interfaccia locale. Diagnostica e
  sincronizzazione non bloccano la disponibilità delle attività.
- `ui/shell/bootstrap_app.dart` conserva la stessa shell quando arrivano client
  e servizio remoto. Un fallimento remoto mostra una spiegazione e **Riprova**;
  un fallimento SQLite resta bloccante, senza ripiegare su un archivio vuoto.
- `ui/shell/sync_lifecycle.dart` sospende/riprende il servizio anche quando
  l'avvio avviene in background. La shell collega i servizi remoti arrivati
  dopo l'apertura senza ricreare navigazione o editor.
- `data/sync/sync_connection.dart` possiede auth, connettività e Realtime;
  `sync_service.dart` orchestra outbox, ricevute, merge e cancellazione delle
  richieste. Stato immutabile in `sync_status.dart`, politiche in
  `sync_policy.dart`, lettura delle versioni in `realtime_versions.dart`.
  Nessuna modifica al protocollo, allo schema o alle regole di convergenza.

## Calendario

`AgendaLoadController` coordina le letture indipendenti e accorpa richieste
sovrapposte. Una modifica esplicita durante un caricamento richiede un ulteriore
passaggio; tutti i chiamanti attendono il risultato finale. La vista conserva
il risultato precedente in caso di errore, ma nasconde gli eventi quando il
permesso è revocato. Un semplice passaggio `inactive → resumed` non richiede
un nuovo caricamento; il ritorno da vero background sì.

Android `AgendaRevision` registra, al primo utilizzo autorizzato, un
`ContentObserver` sul provider Calendario. Il contatore cambia senza leggere
contenuti e senza polling, timer, wake lock o accesso di rete. Vive quanto il
processo e il token include un'identità casuale di processo. Se l'osservatore
non è disponibile, o manca il permesso, il token è nullo e le letture restano
sempre fresche.

`AgendaService.events` riusa un intervallo solo quando il token coincide e la
lettura ha meno di due minuti. Il limite temporale protegge anche da notifiche
omesse dal provider. Le richieste contemporanee per lo stesso intervallo e
revisione condividono il lavoro. Il token viene controllato anche dopo la
lettura: un cambiamento nel frattempo non valida la cache. Scritture esplicite
ed **Aggiorna** invalidano anche i risultati ancora in volo.

La cache contiene al massimo 64 intervalli, solo in memoria, e rimuove il più
vecchio quando serve spazio. Impostazioni, colori, filtri e task vengono
riletti normalmente: la revisione dei widget può ancora cambiare, ma una
riapertura senza modifiche evita di rieseguire le query native sugli eventi.
Il Web mantiene il proprio servizio di lettura della copia del telefono;
non usa l'osservatore Android.

## Ricerca e navigazione

La ricerca eventi attende 250 ms dall'ultimo carattere. Ha al massimo una
richiesta attiva e conserva soltanto l'ultima richiesta pendente. Non può
annullare una query nativa già iniziata; ne scarta l'esito se superato. Cache
limitata a otto ricerche per venti secondi, distrutta chiudendo la ricerca e
invalidata al rientro nell'app o dopo l'apertura di un evento. Errori mostrati
con **Riprova**. La ricerca task continua a usare SQLite senza questa attesa.

Durante il cambio di query della vista, `StreamBuilder` conserva internamente
l'ultimo risultato: la shell ora lo rende solo quando lo stream nuovo è
attivo. Questo evita di passare attività Inbox senza data alla vista Prossime,
che richiede date, e di mostrare temporaneamente righe della vista sbagliata.

## Verifica e limiti

Test specifici: `app_runtime_test.dart`, `event_search_controller_test.dart`,
`agenda_loading_test.dart`, oltre alle suite di calendario e sincronizzazione.
Il test nativo `integration_test/agenda_provider_smoke.dart` verifica che una
scrittura sintetica cambi il token dell'osservatore, su emulatore isolato.

I conteggi di richieste nei test sono deterministici; tempi di avvio, RAM,
fluidità e batteria richiedono misure sul dispositivo. La misura diagnostica
`startup` indica ora il repository locale pronto; non comprende più l'avvio
remoto. Un tempo Android `am start -W` misura l'Activity e non certifica da
solo il primo frame interattivo Flutter. Esiti e numeri sono in
[diagnostica build 260](../diagnostics/2026-10-12-performance-260.md).

## Pagine e operazioni foreground — build 261

Le viste settimana/tre giorni, mese e due–quattro settimane usano
`AgendaPageCache`: massimo sette pagine per vista, inclusi errori e richieste
pendenti. Le letture recenti restano in memoria; la pagina visibile è protetta
dall'espulsione. Una pagina espulsa viene riletta quando serve. Un risultato
arrivato dopo espulsione, invalidazione o dispose viene ignorato e non può
ricreare stato vecchio. La revisione conserva l'anteprima fino al nuovo esito;
cambio giorno o numero di giorni/settimane cancella le pagine incompatibili.
Le anteprime provenienti dalla cache del servizio vengono comunque validate
con una lettura della revisione corrente. Nessun precaricamento aggiunto.

`ForegroundJobs` avvia indipendentemente passi, aggiornamenti, backup,
manutenzione iniziale e diagnostica. Al resume usa gli stessi identificatori
per evitare sovrapposizioni. La manutenzione conserva la frequenza precedente
(all'avvio, una volta al giorno); i backup conservano la propria politica
settimanale. Promemoria e visite urgenti mantengono l'ordine richiesto dai
permessi, separati dalle altre operazioni.

Un errore produce soltanto fase e classe dell'errore nella diagnostica locale.
Scadenza osservazione: 30 secondi, due minuti per il backup. Il timeout non
annulla IO né consente una seconda scrittura: il lavoro mantiene la propria
esclusione finché termina davvero. Per aggiornamenti e richieste permessi non
si applica un timeout all'attesa dell'utente; il controllo HTTP mantiene il
proprio timeout. Nessun timer periodico nuovo e nessun retry automatico nuovo.

Test: `agenda_page_cache_test.dart`, `foreground_jobs_test.dart` e suite UI
Calendario. La preparazione dell'ottimizzazione backup è separata:
[benchmark sintetico](../diagnostics/2026-10-13-backup-preparation.md).
