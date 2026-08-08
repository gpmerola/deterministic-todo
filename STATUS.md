# Stato corrente

Aggiornato l'8 agosto 2026.

## Distribuzione

- Canali supportati: Android nativo e browser Chrome/Edge.
- Versione sorgente in preparazione: **2.17.5 build 71**.
- Ultima release pubblica verificata: **2.17.4 build 70**.
- Web, release Android pubblica, Google Play interno e manifest di parità sono
  verificati sul commit `f25278b`.
- Il test interno Google Play è attivo; la 2.17.4 build 70 è disponibile alla
  lista `Test interno`. Dalla build 65 la pipeline pubblica automaticamente nel
  test interno; la produzione resta manuale e subordinata al test chiuso.
- Un solo workflow coordina web e Android e rifiuta versioni, build o commit
  discordanti.
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
  controllo completo ogni minuto recupera eventi persi, riprese e periodi
  offline mentre l'app è visibile.
- Task, progetti, sezioni, priorità, date civili, ricorrenze e tombstone sono
  sincronizzati. Non si sincronizzano segreti o contenuti dei log.
- Le occorrenze ricorrenti hanno ID deterministici condivisi tra dispositivi;
  il client riconcilia anche le collisioni storiche `23505` scegliendo la
  versione Lamport più recente.

## Esperienza corrente

- Oggi, Prossime, Progetti, ricerca e composer condividono lo stesso modello su
  Android e web, con layout desktop adattivo.
- `Ctrl/⌘ K` apre il comando universale: testo libero cerca, `+` crea, `>`
  naviga e `#` limita la ricerca a un progetto. Sul desktop una task selezionata
  si modifica direttamente nel pannello laterale opzionale.
- Il composer riconosce linguaggio naturale, `#Progetto`, `p1`–`p4` e link;
  ricorda il progetto recente, parte sempre senza priorità e resta fermo durante
  gli assestamenti della tastiera Android.
- Nel campo titolo Invio conferma sia la creazione sia la modifica in ogni
  sezione; la descrizione conserva il comportamento multilinea.
- La spunta è separata dallo swipe: completamento e avanzamento della ricorrenza
  non possono più avviare per errore il trascinamento verso il cestino.
- L'Undo usa un solo comportamento per task, progetti e sezioni e, sulle
  ricorrenze, inverte atomicamente anche la nuova occorrenza.
- L'import Todoist supporta aggiornamento e sostituzione idempotente di task,
  progetti e sezioni e produce un rapporto prima del backup.
- Impostazioni contiene Cestino, attività completate, diagnostica e Salute dati;
  gli stati sani restano fuori dall'interfaccia principale.

## Verifica

- Analisi statica senza errori.
- 112 test automatici superati, incluso uno scenario di convergenza con due
  database indipendenti che rappresentano Android e Web.
- Build web release completata localmente. La build Android locale non è
  disponibile su questo Mac perché manca l'Android SDK; la pipeline firmata
  esegue build AAB/APK e applica il budget prima di distribuire.
- Restano manuali il collaudo sul Galaxy S21, Google Calendar e il passaggio
  definitivo dall'ultimo export Todoist; vedi [TODO_NEXT.md](TODO_NEXT.md).

Architettura: [docs/ARCHITETTURA.md](docs/ARCHITETTURA.md). Procedure:
[docs/operations/](docs/operations/). Cronologia: [CHANGELOG.md](CHANGELOG.md).
