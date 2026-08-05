part of '../main.dart';

class SyncAccountCard extends StatefulWidget {
  const SyncAccountCard({this.client, this.syncService, super.key});

  final SupabaseClient? client;
  final SyncService? syncService;

  @override
  State<SyncAccountCard> createState() => _SyncAccountCardState();
}

class _SyncAccountCardState extends State<SyncAccountCard> {
  final email = TextEditingController();
  final password = TextEditingController();
  StreamSubscription<AuthState>? authSubscription;
  bool busy = false;
  String? message;

  @override
  void initState() {
    super.initState();
    authSubscription = widget.client?.auth.onAuthStateChange.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    authSubscription?.cancel();
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final client = widget.client;
    if (client == null || busy) return;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await client.auth.signInWithPassword(
        email: email.text.trim(),
        password: password.text,
      );
      await widget.syncService?.sync();
      message = 'Collegamento permanente attivo.';
      password.clear();
    } on AuthException catch (error) {
      message = error.message;
    } on Object {
      message = 'Collegamento non riuscito. Controlla la connessione.';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final client = widget.client;
    if (client == null) {
      return const ListTile(
        leading: Icon(Icons.cloud_off_outlined),
        title: Text('Sincronizzazione non configurata'),
        subtitle: Text(
          'Servono Project URL e chiave pubblica Supabase nella build.',
        ),
      );
    }
    final user = client.auth.currentUser;
    if (user != null) {
      final service = widget.syncService;
      return StreamBuilder<SyncSnapshot>(
        stream: service?.snapshots,
        initialData: service?.latest,
        builder: (context, snapshot) {
          final sync = snapshot.data;
          return ListTile(
            leading: Icon(
              sync?.phase == SyncPhase.error
                  ? Icons.sync_problem_outlined
                  : Icons.cloud_done_outlined,
            ),
            title: Text(_syncLabel(sync)),
            trailing: PopupMenuButton<String>(
              tooltip: 'Gestisci collegamento',
              onSelected: (value) async {
                if (value == 'sync') await service?.sync();
                if (value == 'disconnect') await client.auth.signOut();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'sync', child: Text('Sincronizza ora')),
                PopupMenuItem(
                  value: 'disconnect',
                  child: Text('Scollega questo dispositivo'),
                ),
              ],
            ),
          );
        },
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Collega i dispositivi una sola volta',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Usa lo stesso account personale su ogni dispositivo. '
              'Non sarà richiesto un accesso quotidiano.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: password,
              obscureText: true,
              autofillHints: const [AutofillHints.password],
              decoration: const InputDecoration(labelText: 'Password'),
            ),
            if (message != null) ...[const SizedBox(height: 8), Text(message!)],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                FilledButton(
                  onPressed: busy ? null : _connect,
                  child: Text(busy ? 'Collego…' : 'Collega'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _syncLabel(SyncSnapshot? snapshot) => switch (snapshot?.phase) {
    SyncPhase.syncing => 'Sincronizzazione (${snapshot!.pending})…',
    SyncPhase.current =>
      snapshot!.lastSuccess == null
          ? 'Sincronizzato'
          : 'Sincronizzato · ${DateFormat('HH:mm').format(snapshot.lastSuccess!.toLocal())}',
    SyncPhase.error =>
      snapshot?.error == null
          ? 'Errore di sincronizzazione'
          : 'Errore · ${snapshot!.error}',
    SyncPhase.offline => 'Offline',
    SyncPhase.disabled || null => 'Collegato',
  };
}
