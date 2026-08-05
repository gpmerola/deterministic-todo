# Stato corrente

Aggiornato il 5 agosto 2026.

## Distribuzione

- Canali supportati: Android nativo e browser Chrome/Edge.
- Versione in preparazione: **2.16.1 build 45**.
- Ultima release pubblica verificata: **2.16.0 build 44**.
- Un solo workflow coordina web e Android e rifiuta versioni, build o commit
  discordanti.

## Dati e sincronizzazione

- SQLite Drift è la fonte locale immediata; Supabase con RLS è la replica
  personale facoltativa.
- Le scritture locali entrano in una outbox persistente e vengono inviate
  subito.
- Supabase Realtime notifica Android e browser; dalla 2.16.0 vengono richiesti
  soltanto gli ID cambiati. Un controllo completo ogni 15 minuti recupera
  eventi persi, riprese e periodi offline.
- Task, progetti, sezioni, priorità, date civili, ricorrenze e tombstone sono
  sincronizzati. Non si sincronizzano segreti o contenuti dei log.

## Esperienza corrente

- Oggi, Prossime, Progetti, ricerca e composer condividono lo stesso modello su
  Android e web, con layout desktop adattivo.
- Il composer riconosce linguaggio naturale, `#Progetto`, `p1`–`p4` e link;
  ricorda progetto e priorità recenti.
- L'import Todoist supporta aggiornamento e sostituzione idempotente di task,
  progetti e sezioni e produce un rapporto prima del backup.
- Impostazioni contiene Cestino, attività completate, diagnostica e Salute dati;
  gli stati sani restano fuori dall'interfaccia principale.

## Verifica

- Analisi statica senza errori.
- 86 test automatici superati.
- Build web release completata localmente.
- Restano manuali il collaudo sul Galaxy S21, Google Calendar e il passaggio
  definitivo dall'ultimo export Todoist; vedi [TODO_NEXT.md](TODO_NEXT.md).

Architettura: [docs/ARCHITETTURA.md](docs/ARCHITETTURA.md). Procedure:
[docs/operations/](docs/operations/). Cronologia: [CHANGELOG.md](CHANGELOG.md).
