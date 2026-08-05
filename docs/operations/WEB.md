# Browser

La web app pubblica è `https://gpmerola.github.io/deterministic-todo/`.

- SQLite usa OPFS/IndexedDB e deve sopravvivere a refresh e riapertura.
- La diagnostica usa un database IndexedDB separato e non contiene contenuto
  delle attività.
- Sotto 900 px la UI usa la navigazione Android; sopra 900 px usa una barra
  laterale compatta con le stesse tre sezioni.
- `release-info.json` identifica versione, build e commit serviti.

Smoke test: aprire il sito non in incognito, creare una task sentinella,
aggiornare la pagina, verificare persistenza e sincronizzazione bidirezionale con
Android. Se il bootstrap rileva soltanto storage volatile deve fallire in modo
esplicito.
