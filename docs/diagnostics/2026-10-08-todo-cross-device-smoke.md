# Collaudo Todo Android ↔ Web — 8 ottobre 2026

## Ambiente e ambito

- Web HTTPS pubblico 2.71.2 (247), sorgente `c508f5b`, profilo Chrome reale.
- Galaxy S21: Todo Test 2.71.2, versionCode 2247, ADB autorizzato.
- Una sola fixture sintetica, ID `aa37008c-aff5-41b7-ad6e-4ad885d3392b`,
  prefisso titolo `Collaudo sync 247`. Nessuna attività reale modificata.
- Operazioni attraverso le interfacce dell'app; nessuna scrittura diretta
  in SQLite o Supabase e nessuna modifica delle preferenze del browser.

## Risultati osservati

| Passaggio | Risultato |
|---|---|
| Creazione Web con data odierna | La stessa fixture appare sul Galaxy con titolo e data attesi. |
| Android: modifica titolo e cancellazione data | Il Web riceve titolo nuovo e data assente senza refresh. |
| Storico Android | Confronto della modifica locale: data `2026-10-08` → assente; stato `available` → `inbox`; titolo prima/dopo corretto. |
| Storico Web | Presenti creazione locale e revisione ricevuta da Android. |
| Web: seconda modifica a titolo e nota | Entrambi i campi coincidono sul Galaxy. |
| Storico Android dopo modifica Web | Presenti revisione ricevuta dal Web, modifica locale precedente e creazione ricevuta. |
| Senza data, ancora in progetto | La fixture mantiene il progetto predefinito ereditato dalla creazione rapida; è correttamente esclusa dalla vista Inbox. |
| Android: progetto impostato a Nessuno | La vista Web «Attività senza data» si aggiorna e mostra la fixture con sottotitolo Inbox. |
| Refresh Web | Fixture senza data e senza progetto presente in Oggi; storico completo delle modifiche ancora disponibile. |
| Pulizia Web via Cestino nell'editor | La fixture scompare dalla ricerca Android rimasta aperta; è presente nel Cestino Web con azione Ripristina. |
| Diagnostica Android finale | Build 2247, sync riuscita, zero pending e zero conflitti. |

Lo storico è **locale a ciascun dispositivo**: si verifica la conservazione
coerente delle modifiche osservate, non l'identità della lista di revisioni
tra client. Le ricevute e i tentativi di upload differiscono legittimamente.

## Limite e ripresa

La chiusura completa di Chrome **non è stata eseguita**: prima dell'uscita
normale è stata rilevata una sessione attiva con videocamera e microfono.
Chiudere il browser l'avrebbe interrotta. È stata chiesta la disponibilità a
rimandare questa sola prova; non sono state chiuse schede o sessioni altrui.
Refresh e riapertura di singola scheda erano già verificati, ma non sostituiscono
la terminazione completa del browser.

La fixture è nel Cestino, recuperabile; non è stato svuotato il Cestino.
Quando l'utente conferma che Chrome può essere chiuso, verificare dopo uscita
e riavvio normali la fixture nel Cestino, la diagnostica persistente e lo
storico (ripristinando soltanto la fixture se serve). Arrestarsi davanti a
qualsiasi avviso di lavoro non salvato. Non cancellare storage o credenziali.

Import/export JSON, conversione del vecchio progetto Inbox dell'utente e
svuotamento del Cestino restano fuori da questo collaudo.
