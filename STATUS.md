# Stato corrente

Aggiornato l'8 agosto 2026.

## Distribuzione

- Canali supportati: Android nativo e browser Chrome/Edge.
- Versione sorgente in preparazione: **2.18.3 build 75**.
- Ultima release pubblica verificata: **2.18.2 build 74** (commit `96abd76`).
- Web, release Android pubblica, Google Play interno e manifest di parità sono
  verificati sul commit `96abd76`.
- Il test interno Google Play è attivo; la 2.18.2 build 74 è disponibile alla
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
  controllo completo ogni dieci minuti recupera eventi persi, riprese e periodi
  offline mentre l'app è visibile.
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

## Verifica

- Analisi statica senza errori.
- 115 test automatici superati, incluso uno scenario di convergenza con due
  database indipendenti che rappresentano Android e Web.
- Build Web locale e pipeline coordinata completate. La build Android locale
  non è disponibile su questo Mac perché manca l'Android SDK; la pipeline
  firmata ha verificato e distribuito AAB/APK applicando il budget.
- Restano manuali il collaudo sul Galaxy S21, Google Calendar e il passaggio
  definitivo dall'ultimo export Todoist; vedi [TODO_NEXT.md](TODO_NEXT.md).

Architettura: [docs/ARCHITETTURA.md](docs/ARCHITETTURA.md). Procedure:
[docs/operations/](docs/operations/). Cronologia: [CHANGELOG.md](CHANGELOG.md).
