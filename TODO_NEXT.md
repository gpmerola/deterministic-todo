# TODO e handover

Aggiornato il 4 agosto 2026. Questo file è il punto di partenza per una nuova sessione.

## Stato pronto al passaggio

- Repository sorgente privato: `gpmerola/deterministic-todo`.
- Repository release pubblico: `gpmerola/deterministic-todo-releases`.
- Branch di lavoro: `agent/android-apk-sync-pairing`.
- Pull request draft: <https://github.com/gpmerola/deterministic-todo/pull/1>.
- Release pubblica corrente verificata: `v1.2.0`, build Android `10`; `v1.3.0` build `11` è nella pipeline automatica al momento di questo aggiornamento.
- Telefono principale: Samsung Galaxy S21, ABI `arm64-v8a`.
- L’albero Git deve risultare pulito dopo il commit di handover; verificare con `git status -sb`.
- Le ultime CI Android, macOS e Verify risultavano verdi. Riconfermare sempre dalla PR prima di un merge.

La PR rimane volutamente draft: non è stata autorizzata una fusione in `main`. Il nuovo agente deve leggere integralmente `AGENTS.md`, questo file, README e i due documenti in `docs/` prima di modificare codice.

## P0 — Completare e provare la sincronizzazione persistente

Il client ora offre collegamento account una tantum, rinnovo automatico e sessione nel secure storage. Database locale, outbox, versioni Lamport, tombstone, worker Supabase e migrazione RLS sono presenti, ma manca ancora la configurazione di un progetto reale e quindi la sincronizzazione end-to-end non è dichiarata completa.

Obiettivo concordato:

1. configurazione iniziale una sola volta (implementata lato client);
2. collegamento permanente tramite lo stesso account personale (implementato); QR/codice monouso resta un miglioramento server;
3. nessun login quotidiano (implementato con refresh automatico);
4. sessione e token conservati nel secure storage (implementato);
5. possibilità di revocare un dispositivo;
6. SQLite sempre fonte della UI e rete mai bloccante;
7. conflitti deterministici `(logical_version, device_id)` e operazioni idempotenti.

Architettura raccomandata: vault personale, token dispositivo casuale memorizzato solo come hash sul server, codice pairing a scadenza breve e Supabase Edge Function che usa `service_role` soltanto lato server. Non trasferire refresh token Supabase dentro un QR e non includere `service_role` nel client.

Il progetto Supabase personale, la configurazione client pubblica e la migrazione iniziale sono collegati e verificati. Accesso permanente e convergenza telefono → Supabase → Mac sono stati provati con un'attività sentinella. Il deployment di future Edge Functions richiede autorizzazione esplicita.

## P0 — Test reale sul Galaxy S21

La build e i test automatici sono verdi, ma questi flussi devono ancora essere verificati fisicamente:

- aggiornamento in-app da una versione senza Impostazioni → 1.1.1, eventualmente tramite installazione manuale sopra l'app esistente;
- installazione dell’APK ARM64 con conservazione di una task sentinella;
- permesso “Installa app sconosciute” e prompt finale Android;
- permessi calendario Samsung/Google;
- “Salva + calendario” crea nel Google Calendar primario;
- ripetere il comando aggiorna lo stesso evento senza duplicarlo;
- nuova attività con ora salva un identificatore IANA;
- cambio manuale del fuso del telefono e comportamento delle notifiche;
- riavvio del telefono e ripristino notifiche.

La release pubblica `1.1.0` contiene l'APK ARM64 per Galaxy S21. Il launcher `SCARICA_APK_ANDROID.command` scarica l'asset ARM64 dalla release latest e lo rinomina nel nome stabile usato dall’installer.

## P1 — Calendario: confini e completamento

L’integrazione corrente è intenzionalmente unidirezionale ed esplicita:

- SQLite è la fonte di verità;
- “Salva + calendario” preferisce Google primario;
- il mapping `calendar_event:<task_id>` è locale in `app_settings`;
- ripetere il comando aggiorna l’evento esistente;
- nessun pull dal calendario modifica task;
- completamento ed eliminazione non modificano automaticamente l’evento.

Prossimi miglioramenti possibili, da autorizzare separatamente:

- mostrare nell’editor quale calendario/evento è collegato;
- comando esplicito “Rimuovi dal calendario”;
- scelta manuale del calendario quando esistono più account;
- sincronizzare il mapping evento tra dispositivi soltanto dopo il backend;
- gestire in modo chiaro un evento eliminato esternamente, senza creare duplicati silenziosi.

Non implementare sincronizzazione bidirezionale implicita: violerebbe la promessa deterministica e richiederebbe una regola di conflitto separata.

## P1 — Completare la configurazione dell'automazione release

Il workflow protetto `Publish Android Release` ora ricompila, verifica, genera manifest/hash, pubblica nel repository release e ricontrolla il manifest pubblico. Per renderlo operativo su GitHub manca soltanto configurare l'environment `android-release` e il secret fine-grained `RELEASE_REPO_TOKEN`, limitato al repository pubblico.

Requisiti:

- build Android solo `--split-per-abi`;
- firma stabile dai Secrets `ANDROID_KEYSTORE_*`;
- asset ARM64, ARM32 e x86_64 con SHA-256;
- manifest pubblico coerente;
- fallback `android` verso l’universale 1.0.4 per client 1.0.3;
- rendere `latest` soltanto dopo verifica;
- mantenere symbol map private se si abilita offuscamento.

Soluzioni ammissibili: fine-grained token limitato al repository release oppure workflow nel repository pubblico attivato in modo controllato. Non usare token amministrativi generici.

## IN PAUSA — Import Todoist e dominio progetti

Un export personale Todoist è stato verificato localmente il 4 agosto 2026. Non copiarlo nel repository perché contiene dati personali. L'implementazione è intenzionalmente in pausa durante la preparazione del repository pubblico.

Contenuto disponibile:

- 5 progetti personali, incluso Inbox;
- 13 sezioni, tutte collegabili ai rispettivi progetti;
- 110 attività attive, delle quali 46 pianificate e 25 ricorrenti;
- 13 descrizioni, nessun commento/nota separata, nessuna sotto-attività, nessun reminder e nessuna durata;
- priorità Todoist: 75 p4/default, 8 p3, 6 p2, 21 p1 (nel JSON i valori sono invertiti rispetto alle etichette mostrate da Todoist: `4` è la priorità massima);
- 2 etichette definite ma nessuna assegnata alle 110 attività;
- 2 filtri personali;
- `completed_info` contiene soltanto contatori aggregati per progetto, non titoli o record completati. La cronologia completata non è quindi importabile da questo file.

Incremento critico da implementare prima degli altri:

1. ~~aggiungere tabelle/colonne locali per progetti, sezioni, priorità e `external_source`/`external_id`, con migrazione Drift e indici;~~ completato nello schema locale 3;
2. estendere schema, funzione `merge_task` e RLS Supabase senza interrompere i client precedenti;
3. parser Todoist dedicato: anteprima read-only di conteggi, priorità e ricorrenze implementata; restano mapping completo di progetti/sezioni/task, date/fusi/descrizioni e ID deterministici;
4. import transazionale e idempotente: ripetere lo stesso file non crea duplicati;
5. mostrare Progetti nell'interfaccia soltanto quando ne esiste almeno uno, preservando Inbox Todoist come progetto importato e non come destinazione mobile principale;
6. test fixture anonima minima; mai committare l'export reale;
7. dopo import sul telefono, verificare i conteggi attesi e la convergenza sul Mac prima di dichiararlo completo.

Le ricorrenze presenti includono giornaliere, settimanali, ogni N giorni/settimane/mesi, annuali e giorni fissi dell'anno. Le stringhe ambigue `ogni 1` e `ogni 26` vanno interpretate secondo il campo `due.date` e verificate in anteprima, non indovinate silenziosamente.

## P1 — UX Android richiesta

- Spostare Completate dentro Impostazioni, lasciando nella barra primaria soltanto Oggi e Prossime.
- Rendere Prossime una timeline verticale virtualizzata senza limite pratico, con separatori giornalieri e sezioni comprimibili; mostrare le task del giorno dall'SQLite dell'app. Google Calendar resta export esplicito e non diventa fonte di verità.
- Estendere il linguaggio naturale evidenziato a ricorrenze: ogni giorno, ogni N giorni/settimane/mesi, ogni secondo martedì del mese, ogni giorno/mese annuale. La frase riconosciuta viene rimossa dal titolo.
- Aggiungere bandierine priorità opzionali e pulite, coerenti con il mapping Todoist.
- Aggiungere Undo per completamento, eliminazione, spostamento e ripianificazione.
- Aggiungere swipe sperimentale con direzioni chiaramente colorate e sempre annullabile; se il test sul telefono non convince, rimuoverlo senza cambiare il dominio.
- Non materializzare calendari infiniti: usare liste lazy e caricare finestre di date progressivamente.

## P1 — Funzioni originali ancora incomplete

- schermata cestino con ripristino tombstone;
- selezione multipla per stato, mostra il e scadenza;
- undo per completamento, eliminazione, spostamento e modifica recente (incluso nel piano UX Android sopra);
- scheduler automatico dell’orizzonte delle ricorrenze calendario;
- backup cifrato;
- test end-to-end contro Supabase e due dispositivi;
- test/installazione Windows su una macchina Windows reale.

Non ampliare l’ambito con progetti, etichette, priorità, AI, collaborazione o calendario completo.

## P2 — Performance misurata

Il Galaxy S21 riceve l’APK ARM64 da circa 21 MB. Le ottimizzazioni strutturali sono documentate, ma RAM, CPU, startup time e frame pacing non sono ancora stati profilati su hardware reale.

Procedura consigliata:

```sh
flutter run --profile -d <device-id>
flutter devtools
```

Misurare prima di cambiare codice:

- tempo cold start e warm start;
- RAM con 100, 1.000 e 10.000 task;
- CPU a riposo per almeno cinque minuti;
- frame build/raster durante scroll e riordino a 120 Hz;
- latenza ricerca e apertura Completate;
- costo prima pianificazione notifica e primo accesso calendario.

Ottimizzazioni candidate solo se giustificate dai dati: paginazione Completate, ricerca SQL/FTS5, `--split-debug-info`, riduzione dipendenze. Non sacrificare affidabilità o multipiattaforma per benchmark teorici.

## Sicurezza e backup operativo

- Non committare `private_release_keys/`.
- Eseguire un backup cifrato esterno del keystore Android e della password; perdere la chiave impedisce aggiornamenti delle installazioni esistenti.
- Non mostrare segreti nei log o nei comandi copiati nella documentazione.
- La chiave pubblica Supabase è ammessa nel client; `service_role` non lo è.
- Titoli e note non devono entrare nei log.

## Checklist di ogni sessione

1. Leggere `AGENTS.md` e `TODO_NEXT.md`.
2. `git status -sb` e controllo delle modifiche dell’utente.
3. Scegliere un solo incremento verificabile.
4. Aggiornare test e documentazione insieme al codice.
5. Eseguire `dart format lib test`, `flutter analyze`, `flutter test`.
6. Commit intenzionale e push obbligatorio sul branch.
7. Attendere la pipeline Android automatica; eseguire Verify/build separata e macOS manualmente soltanto ai checkpoint necessari.
8. Per release Android, misurare asset, calcolare hash, pubblicare manifest e provare l’upgrade dalla versione precedente.

## Comandi rapidi

```sh
flutter pub get
dart run build_runner build
flutter analyze
flutter test
git status -sb
gh pr checks 1 --repo gpmerola/deterministic-todo
gh release list --repo gpmerola/deterministic-todo-releases
```

La documentazione autorevole è: `AGENTS.md` per le regole, README per l’uso, `docs/ARCHITETTURA.md` per il dominio, `docs/ANDROID_PERFORMANCE_E_AGGIORNAMENTI.md` per distribuzione/performance e `COMPLETATO.md` per ciò che è stato verificato.
