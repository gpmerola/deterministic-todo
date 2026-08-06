# Stato corrente

Aggiornato il 7 agosto 2026.

## Distribuzione

- Canali supportati: Android nativo e browser Chrome/Edge.
- Versione sorgente corrente: **2.16.19 build 63**.
- Ultima release pubblica verificata: **2.16.18 build 62**.
- Web, release Android pubblica e manifest di parità sono verificati sul commit
  `f433aee`.
- Il test interno Google Play è attivo; la 2.16.17 build 61 è disponibile alla
  lista `Test interno`. La produzione resta subordinata al test chiuso Google.
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
- Il composer riconosce linguaggio naturale, `#Progetto`, `p1`–`p4` e link;
  ricorda progetto e priorità recenti e resta fermo durante gli assestamenti
  della tastiera Android.
- La spunta è separata dallo swipe: completamento e avanzamento della ricorrenza
  non possono più avviare per errore il trascinamento verso il cestino.
- L'import Todoist supporta aggiornamento e sostituzione idempotente di task,
  progetti e sezioni e produce un rapporto prima del backup.
- Impostazioni contiene Cestino, attività completate, diagnostica e Salute dati;
  gli stati sani restano fuori dall'interfaccia principale.

## Verifica

- Analisi statica senza errori.
- 103 test automatici superati.
- Build web release completata localmente.
- Restano manuali il collaudo sul Galaxy S21, Google Calendar e il passaggio
  definitivo dall'ultimo export Todoist; vedi [TODO_NEXT.md](TODO_NEXT.md).

Architettura: [docs/ARCHITETTURA.md](docs/ARCHITETTURA.md). Procedure:
[docs/operations/](docs/operations/). Cronologia: [CHANGELOG.md](CHANGELOG.md).
