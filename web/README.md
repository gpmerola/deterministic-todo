# Asset browser

`sqlite3.wasm` e `drift_worker.js` provengono dalla release ufficiale
[`drift-2.34.3`](https://github.com/simolus3/drift/releases/tag/drift-2.34.3)
e devono essere aggiornati insieme alla versione Drift bloccata in
`pubspec.lock`.

SHA-256 verificati il 5 agosto 2026:

- `sqlite3.wasm`: `41cf968998241465d8b1dfffb1eb60dd10c35de5022a3647e14174ea3af84143`
- `drift_worker.js`: `4db0469de8ceabad8d5cd3d920614486ba587e100e39523f36f704a3aec5f26c`

Il database usa OPFS quando disponibile e ricade su IndexedDB. La modalità in
sola memoria non è accettata dal client.
