# Sicurezza

## Segnalare una vulnerabilità

Non aprire una issue pubblica per vulnerabilità, credenziali esposte o problemi che possano consentire accesso ai dati. Usa invece la funzione **Report a vulnerability** nella scheda Security del repository.

Indica versione, piattaforma, impatto e passaggi minimi per riprodurre il problema, evitando di includere titoli, note, token, backup o database reali.

## Modello di sicurezza

- SQLite locale è la fonte di verità dell'interfaccia.
- Supabase usa esclusivamente una chiave client pubblicabile e Row Level Security per separare gli utenti.
- `service_role`, refresh token, password, database, export personali e keystore Android non devono entrare nel repository o nei log.
- Gli APK ufficiali sono firmati con una chiave stabile conservata nei GitHub Actions Secrets e verificati tramite SHA-256 nel manifest pubblico.
- Google Calendar è un export esplicito e unidirezionale; non controlla né modifica implicitamente le attività.

## Fork e installazioni indipendenti

Un fork deve configurare un proprio progetto Supabase, applicare le migrazioni e usare una propria chiave di firma Android. Non fare affidamento sul backend o sugli artefatti di release del manutentore per dati personali.
