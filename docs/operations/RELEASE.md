# Release coordinata Android e browser

## Prerequisiti

- versione `x.y.z+build` monotona in `pubspec.yaml`;
- branch `agent/**` autorizzato negli environment `android-release` e
  `github-pages`;
- secret Android e `RELEASE_REPO_TOKEN` configurati;
- working tree senza segreti o artefatti generati.

## Flusso canonico

1. Eseguire formatter, generazione Drift, analisi e test.
2. Aggiornare documentazione, stato e changelog quando pertinenti.
3. Commit e push del branch `agent/**`.
4. `Publish Android and Web Release` verifica una volta e avvia in parallelo
   bundle Play, APK diretti e Web.
5. Il bundle Play viene caricato nel track interno appena pronto, senza
   attendere gli APK o il deploy Web.
6. Chrome viene distribuito e controllato tramite `release-info.json`.
7. Solo dopo il successo web viene creata la release Android diretta `latest`.
8. Il job finale confronta versione, build e commit dei due endpoint pubblici;
   inoltre richiede tutti e quattro gli APK Android, con hash e URL appartenenti
   alla release corrente.

Output atteso: workflow verde, `release-info.json` raggiungibile, manifest
Android con gli stessi identificativi e quattro APK con SHA-256 (universale più
tre architetture).

Il workflow verde conferma l'accettazione dell'AAB da parte dell'API Play, non
la sua propagazione al singolo tester. Versione pubblicata, versione disponibile
e versione realmente installata sono tre stati distinti e vanno registrati in
`STATUS.md`; un errore Play `unreviewed` richiede attesa, non cambio di firma o
disinstallazione.

## Linee di firma Android

Google Play App Signing e la release APK diretta sono due linee distinte. Un
dispositivo installato da Play deve continuare ad aggiornarsi da Play; uno
installato dall'APK diretto deve continuare con APK firmati dalla stessa chiave
del repository. `INSTALL_FAILED_UPDATE_INCOMPATIBLE` non va aggirato
disinstallando: la disinstallazione rimuove i dati locali. Il Galaxy S21 di test
usa Todo Test `.dev`; il package Play resta disabilitato.
Procedura e vincoli in [ANDROID_DEV_CHANNEL](ANDROID_DEV_CHANNEL.md).

## Fallimento e recovery

- Un job senza step/log può essere stato rifiutato dalle protezioni prima
  dell'assegnazione del runner. Non attribuirlo a un guasto GitHub senza leggere
  le annotazioni del check-run e la policy dell'environment (procedura sotto).
- Prima di ripetere una pipeline fallita, controllare separatamente Play, Web
  e APK diretti: il track Play può essere già aggiornato prima del deploy Web.
- Web fallisce: gli APK diretti non vengono pubblicati; Play potrebbe essere
  già stato aggiornato. Non riutilizzare una versione/build accettata da Play.
- Android fallisce dopo il web: incrementare versione/build e ripetere la
  pipeline senza riscrivere release già pubblicate.
- Non cancellare una release usata da dispositivi installati e non fare
  force-push.

### Pages: branch autorizzato e annotazioni

Prima del dispatch controllare che l'esatto branch sorgente sia ammesso:

```sh
gh api repos/gpmerola/deterministic-todo/environments/github-pages
gh api repos/gpmerola/deterministic-todo/environments/github-pages/deployment-branch-policies
```

Con `custom_branch_policies=true` la presenza di un branch `agent/*` nel
repository non implica il permesso di pubblicare: deve corrispondere a una
policy. Usare regole esatte per i branch operativi autorizzati. Conservare
le protezioni e non sostituirle con accesso indiscriminato. Lo stato corrente
e la modifica applicata sono registrati in [STATUS](../../STATUS.md).

Per un run fallito, sostituire RUN_ID e CHECK_RUN_ID con gli identificatori
restituiti da GitHub:

```sh
gh api repos/gpmerola/deterministic-todo/actions/runs/RUN_ID/jobs \
  --jq '.jobs[] | {name,conclusion,check_run_url}'
gh api repos/gpmerola/deterministic-todo/check-runs/CHECK_RUN_ID/annotations
```

`Branch ... is not allowed to deploy ... due to environment protection rules`
identifica un blocco di configurazione del repository. Ripetere il workflow
senza correggere l'autorizzazione genera soltanto altre email di fallimento.
Dopo una correzione autorizzata, riutilizzare l'artefatto verificato e non
scaduto con `gh run rerun RUN_ID --job JOB_ID` sul solo job deploy Web.
Controllare l'esito del job e l'identità HTTPS pubblica, non soltanto il dispatch.

Per una nuova pubblicazione soltanto Web usare `publish-web.yml`, conferma
`PUBBLICA` e branch autorizzato. Il workflow introdotto per il recovery della
180 conserva guardie esplicite 2.40.2/180: prima di una versione diversa queste
vanno aggiornate o sostituite con la validazione della versione canonica.
Non rilanciare l'intera release coordinata se Play ha già accettato il numero
versione: `Version code ... has already been used` segnala un duplicato,
non credenziali errate. Le email “Run failed” descrivono l'esito complessivo;
leggere quali job sono riusciti e quali sono falliti prima di agire.
