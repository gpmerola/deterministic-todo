# Movimento archiviato

Dalla build 190 (3 ottobre 2026) Android conserva soltanto il **conteggio
quotidiano dei passi del telefono**. Su richiesta dell'utente il resto del modulo
Movimento è stato archiviato, non cancellato: era incompleto, poco usato e
teneva attivi lavori in background.

## Dove si trova il codice

Il modulo completo, così com'era nella build 189 (2.42.0), è conservato in:

- tag `archive/movimento-completo-b189`;
- branch omonimo `archive/movimento-completo-b189`.

Tag e branch hanno lo stesso nome: nei comandi git usare
`refs/tags/archive/movimento-completo-b189`. Per consultare o recuperare un file:

```sh
git show refs/tags/archive/movimento-completo-b189:android/runtracker/src/main/java/app/deterministic/todo/runtracker/RunRecordingService.java
git checkout refs/tags/archive/movimento-completo-b189 -- <percorso>
```

## Cosa è stato archiviato

| Funzione | File principali | Costo eliminato |
|---|---|---|
| Sessioni GPS camminata/corsa, export GPX, calibrazione falcata | `RunRecordingService`, `RunTrackerActivity`, `GpsTrackFilter`, `GpxExporter`, `StrideCalibrator` | servizio in primo piano con GPS |
| Amazfit Bip U (BLE, autenticazione Huami, import storico) | `BipU*`, `HuamiAuthProtocol`, `SecureAuthKeyStore` | scansione e connessione BLE ogni 3 ore e a ogni aggiornamento dell'anello |
| Health Connect e confronto Google Fit | `HealthConnectGateway.kt`, `MovementComparisonWorker`, `HealthPermissionRationaleActivity` | dipendenza Health Connect e coroutine Kotlin |
| Audit passivo e timeline | `PassiveMovementAudit*`, `PassiveEpisodeAnalyzer`, `ActivityClassifier` | worker orario, riconoscimento attività continuo |
| Diagnostica intensiva | `IntensiveDiagnostic*` | GPS a 1 s e sensori in un servizio in primo piano |
| Export su Drive | `DriveTestExportManager`, `DiagnosticDriveWorker`, `RollingDiagnosticBundle` | upload ogni 3 ore e a ogni avvio |
| Distanza e calorie stimate, profilo peso/falcata | `LocalDailyMovementModel`, `MovementEstimate`, `MovementProfile` | nessuno a runtime; rimosso per semplicità |
| Scheda **Movimento** Flutter | `movement_view.dart`, `movement_profile_dialog.dart` | polling del canale nativo ogni secondo |

Documentazione storica spostata qui: [autonomia](MOVEMENT_AUTONOMY.md),
[diagnostica intensiva](MOVEMENT_INTENSIVE_DIAGNOSTICS.md),
[run tracker e Bip U](RUN_TRACKER_BIP_U.md),
[Bip U su Samsung](BIP_U_SAMSUNG.md),
[manutenzione 19 agosto](2026-08-19-movement-maintenance.md).

Dipendenze rimosse dal modulo `runtracker`: `health.connect`,
`play-services-location`, `kotlinx-coroutines-android`, `androidx.activity` e il
plugin Kotlin. Permessi rimossi dall'app: posizione, servizio in primo piano
(anche di tipo posizione), Bluetooth e notifiche; Health Connect dal modulo.

## Cosa resta

- `LocalStepRecording` + `LocalStepRecordingWorker`: abbonamento Recording API
  senza account e import idempotente dei minuti completi, al massimo una volta
  al minuto in primo piano e ogni 3 ore in background.
- `PhoneDailyMovementGateway`: totale del giorno civile solo dal telefono. I
  campioni Bip U già salvati non sono più sommati.
- Obiettivo giornaliero (`movement_profile/daily_step_goal`), anello nell'AppBar
  e pannello che si apre toccandolo, con stato della raccolta e permesso.

## Dati sul dispositivo

Il database `run_tracker.sqlite` mantiene lo schema 5 e **tutti i dati**:
sessioni, punti GPS, campioni Bip U, stime giornaliere. Solo le tabelle dei passi
continuano a essere scritte. Anche le preferenze e la chiave Bip U nel Keystore
restano; nessun dato viene cancellato o inviato altrove.

Al primo avvio della build 190, `MovementArchiveCleanup` annulla una sola volta i
lavori WorkManager delle classi archiviate e l'iscrizione al riconoscimento
attività. Il servizio intensivo, se attivo, si ferma con l'aggiornamento e non
viene più riavviato. L'import dei passi non viene mai annullato (test
`MovementArchiveCleanupTest`).

## Ripristino

Per riattivare una funzione, recuperare dal tag i file elencati sopra, insieme a
dipendenze, permessi e voci del manifest. Ricollegare i metodi del canale
`app.deterministic.todo/run_tracker` e aggiornare
`MovementArchiveCleanup.ARCHIVED_WORKERS`, altrimenti il worker ripristinato
verrebbe annullato.
