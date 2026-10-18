# Latenza tra dispositivi — 18 ottobre 2026, build 280

Domanda dell'utente: dopo un cambio di dispositivo servono a volte 5–10 s
prima che tutto sia sincronizzato.

## Condizioni

- Galaxy non raggiungibile via ADB (porta 5555 chiusa dopo il riavvio):
  nessuna lettura nuova di `todo_sync_debug`. Latenza per richiesta presa
  dalle misure reali della build 178 (25 richieste in 3.031 ms, circa
  120 ms ciascuna; un controllo invariato 203–250 ms).
- Mac → Supabase, solo endpoint di salute senza dati: 50–75 ms a connessione
  calda, circa 260 ms a freddo.
- Server sintetico (`test/support/sync_server.dart`) con latenza di 120 ms
  per richiesta, 300 attività sintetiche, nessun dato reale.

## Catena

| Tratto | Richieste | Tempo |
| --- | ---: | ---: |
| A: attesa outbox | 0 | 120 ms |
| A: invio di una modifica (lettura, CAS, ricevuta) | 3 | 376 ms |
| B in primo piano: evento Realtime, attesa e lettura per ID | 1 | 120 + 131 ms |
| B alla ripresa: controllo completo con una modifica | 3 | 392 ms |
| B alla ripresa: controllo senza novità | 1 | 132 ms |

Il protocollo arriva sotto 1,5 s anche sommando tutti i tratti. Il canale
Realtime è ancora attivo (`SyncConnection`); la pulizia del 13 ottobre ha tolto
solo due funzioni di supporto non usate.

## Dove si perdevano i secondi

Al risveglio la prima richiesta fallisce spesso per la rete non ancora pronta
(già osservato nelle build 185–187: `overview`, `ClientException`). Il retry
partiva dopo 2 s e il secondo dopo altri 10 s. Misura sintetica, dalla ripresa
di B alla modifica visibile:

| Fallimenti al risveglio | Prima (2 s, 10 s) | Dopo (1 s, 3 s) |
| ---: | ---: | ---: |
| 1 | 2.294 ms | 1.293 ms |
| 2 | 12.285 ms | 4.289 ms |

Altre ipotesi verificate e scartate: la ripresa non aspetta la chiusura del
canale Realtime precedente (fino a 10 s nel client): con un server locale che
non risponde al `phx_leave` il controllo parte in meno di 1 s; il secondo
controllo dopo l'iscrizione Realtime costa una richiesta e non ritarda il
primo.

Un socket Realtime caduto senza segnale con l'app visibile lasciava B
indietro fino al timer di 10 minuti o a una nuova pausa. Ora un ritorno al
focus dopo almeno 30 s dall'ultimo controllo ne avvia uno (una richiesta se
nulla è cambiato).

## Da misurare sul Galaxy

Con ADB riattivato: leggere `todo_sync_debug/status` dopo alcuni cambi di
dispositivo reali (`last_failure_*`, `consecutive_failures`, durata) per
confermare la quota di fallimenti al risveglio.
