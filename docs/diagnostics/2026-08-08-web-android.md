# Diagnostica Web e Android — 8 agosto 2026

Analisi aggregata dei due export forniti dall'utente. I file personali originali
restano fuori dal repository; questo documento conserva solo conteggi e misure
tecniche prive di titoli, note, URL, token o identificatori persistenti.

## Campione

- Web: 1.277 eventi, 27 avvii, versioni 2.14.1–2.16.19.
- Android: 563 eventi, 22 avvii, versioni 2.16.10–2.16.17.
- Baseline corrente confrontata: Web 2.16.19, Android 2.16.17.

## Risultati correnti

| Misura | Web 2.16.19 | Android 2.16.17 |
|---|---:|---:|
| Sessioni | 5 | 8 |
| Avvio medio | 568 ms | 239 ms |
| Avvio massimo | 833 ms | 378 ms |
| Sync riusciti | 67 | 54 |
| Sync medio | 407 ms | 1.063 ms |
| Sync massimo | 1.601 ms | 4.313 ms |
| Apertura composer media | 17 ms | 15 ms |
| Apertura editor media | 25 ms | 26 ms |
| Cambio schermata medio | 21 ms | 33 ms |
| Errori sync | 0 | 1 transitorio di rete |

Web 2.16.17 e 2.16.18 documentano rispettivamente i conflitti `23505` e
`42501` già corretti nella 2.16.19. Nelle cinque sessioni Web 2.16.19 non
compare alcun fallimento. L'unico errore Android corrente è una
`_ClientSocketException`, seguito da sync riusciti: non indica corruzione o
divergenza.

## Frame pacing

Web 2.16.19 registra 38 frame oltre 16,67 ms su 1.426 (2,7%); Android 2.16.17
70 su 1.463 (4,8%). I picchi isolati sono 71 ms Web e 55 ms Android in build;
non formano una sequenza persistente. Il completamento task misura circa
155 ms perché include intenzionalmente la breve conferma visiva prima della
scrittura, non perché SQLite sia lento.

## Decisioni applicate

1. Bootstrap indipendente in parallelo e preload di SQLite/worker sul Web.
2. Nessun nuovo polling o dipendenza: i dati non giustificano altro lavoro a
   riposo.
3. Target tattili, alto contrasto e semantica esplicita per priorità e
   ricorrenze.
4. Test automatico con due database indipendenti per ID ricorrenti e conflitti
   Lamport concorrenti.

## Prossima misura utile

Dopo l'installazione della 2.16.20, raccogliere almeno cinque cold start Web e
cinque Android. Confrontare soprattutto `startup`, `screen_change`, percentuale
di frame oltre 16,67 ms e sync massimo; evitare ulteriori ottimizzazioni se la
variazione resta entro il normale rumore del dispositivo o della rete.
