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
- [Agenda unificata](architecture/AGENDA.md): calendari di sistema Android
  in sola lettura, duplicati, link riunioni, privacy.
- [Movimento archiviato](archive/MOVIMENTO.md): cosa resta del modulo Android
  (solo passi), cosa è archiviato nel tag `archive/movimento-completo-b189` e
  come ripristinarlo. Documenti storici GPS/Amazfit in `archive/`.

L'hotspot noto è `lib/data/sync/sync_service.dart`; dalla build 189 viste,
ricerca, composer e aggiornamenti sono stati estratti da `lib/main.dart`
([struttura della shell](architecture/TODO_PLANNING_MODEL.md#struttura-della-shell)). La sua dimensione è debito
tecnico registrato, non autorizzazione a dividerlo durante un fix non correlato.
Ogni estrazione futura deve preservare test e comportamento pubblico.

## Operazioni

- [Release coordinata](operations/RELEASE.md)
- [Google Play](operations/GOOGLE_PLAY.md)
- [ADB Wi-Fi/Tailscale e diagnostica Movimento](operations/ADB_WIFI.md)
- [Web](operations/WEB.md)
- [Backup e recovery](operations/BACKUP_RECOVERY.md)
- [Performance e aggiornamenti Android](ANDROID_PERFORMANCE_E_AGGIORNAMENTI.md)

## Evidenze

- [Baseline diagnostica Web/Android 8 agosto 2026](diagnostics/2026-08-08-web-android.md)

I report datati sono evidenze immutabili, non fonti dello stato corrente. Se un
fatto cambia, aggiornare `STATUS.md`, `TODO_NEXT.md` o il runbook pertinente e
lasciare il report storico invariato.
