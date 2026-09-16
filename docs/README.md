# Mappa della documentazione

Questo indice instrada verso la fonte autorevole senza duplicarne lo stato.

## Orientamento

- [README del prodotto](../README.md): scopo, uso e sviluppo essenziale.
- [Stato corrente](../STATUS.md): versione distribuita, verifiche e limiti.
- [Prossime attività](../TODO_NEXT.md): checklist operativa ordinata per priorità.
- [Handoff tecnico](HANDOFF.md): contesto necessario per riprendere il lavoro.
- [Changelog](../CHANGELOG.md): comportamento distribuito per versione.

## Architettura

- [Architettura applicativa](ARCHITETTURA.md): dominio Todo, persistenza,
  sincronizzazione, confini e invarianti.
- [Run tracker e Bip U](architecture/RUN_TRACKER_BIP_U.md): architettura del
  modulo Android Movimento e roadmap Amazfit.

Gli hotspot noti sono `lib/main.dart`, `lib/data/sync/sync_service.dart` e
`android/runtracker/.../RunTrackerActivity.java`. La loro dimensione è debito
tecnico registrato, non autorizzazione a dividerli durante un fix non correlato.
Ogni estrazione futura deve preservare test e comportamento pubblico.

## Operazioni

- [Release coordinata](operations/RELEASE.md)
- [Google Play](operations/GOOGLE_PLAY.md)
- [ADB Wi-Fi/Tailscale e diagnostica Movimento](operations/ADB_WIFI.md)
- [Web](operations/WEB.md)
- [Backup e recovery](operations/BACKUP_RECOVERY.md)
- [Bip U su Samsung](operations/BIP_U_SAMSUNG.md)
- [Performance e aggiornamenti Android](ANDROID_PERFORMANCE_E_AGGIORNAMENTI.md)

## Evidenze

- [Baseline diagnostica Web/Android 8 agosto 2026](diagnostics/2026-08-08-web-android.md)

I report datati sono evidenze immutabili, non fonti dello stato corrente. Se un
fatto cambia, aggiornare `STATUS.md`, `TODO_NEXT.md` o il runbook pertinente e
lasciare il report storico invariato.
