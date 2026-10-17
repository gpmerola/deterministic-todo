# Backup in isolate e a capo memorizzati, build 278

## Backup automatico

`ExportService.exportBackup` legge le righe nella stessa transazione di
prima; da 500 attività la codifica JSON, l'UTF-8 e lo SHA-256 del contenuto
passano a un isolate con `compute` (sul Web restano inline). Sotto la soglia
tutto resta sul thread principale, perché avviare un isolate costerebbe più
del lavoro. Byte e hash sono identici a `exportJson` e alla formula
precedente: `test/export_service_test.dart` lo verifica con entrambi i
percorsi, quindi il primo backup dopo l'aggiornamento non appare cambiato.

Misura sull'host (Mac della macchina di collaudo, `make benchmark-backup`,
database sintetico in memoria con note da 1.000 byte, tre campioni):

| Righe | Pausa massima event loop prima (ms) | Dopo (ms) | Durata totale prima → dopo (ms) |
| ---: | --- | --- | --- |
| 100 | 28 / 5 / 4 | 28 / 5 / 4 | invariata (sotto soglia) |
| 1.000 | 36 / 28 / 25 | 16 / 6 / 5 | 30 → 34 circa |
| 10.000 | 242 / 247 / 242 | 56 / 61 / 59 | 244 → 256 circa |

La pausa residua è lettura SQLite, `toJson` e copia del messaggio verso
l'isolate. Sul Galaxy (0,75 s misurati a 10.000 righe) non è ancora stata
rimisurata: ADB non raggiungibile il 16 ottobre 2026.

## A capo dei titoli nella Settimana

`wrapWords` memorizza le righe per testo, stile, larghezza e scala del
testo (al massimo 1.024 voci, meno recenti eliminate per prime; svuotata
quando cambiano i font di sistema). Stessi input, stesse righe: le immagini
di riferimento di `test/agenda_week_golden_test.dart` passano senza essere
aggiornate. Il guadagno riguarda le settimane già viste e i titoli
ricorrenti; la prima visita di titoli nuovi costa come prima. Non misurato
sul Galaxy per lo stesso motivo; va ripetuto
`python3 tools/device_performance.py --serial SERIAL --scenario calendar`.
