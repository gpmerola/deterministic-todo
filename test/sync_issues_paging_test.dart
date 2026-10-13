import 'package:deterministic_todo/data/local/database.dart';
import 'package:deterministic_todo/data/sync/sync_service.dart';
import 'package:deterministic_todo/data/task_repository.dart';
import 'package:deterministic_todo/ui/sync_issues_view.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  testWidgets('issue pages stay bounded and can return after queue drains', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final client = (await tester.runAsync(
      () async => SupabaseClient(
        'https://synthetic.invalid',
        'synthetic-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      ),
    ))!;
    final service = SyncService(db, client);
    for (var i = 0; i < 51; i++) {
      await db
          .into(db.outboxEntries)
          .insert(
            OutboxEntriesCompanion.insert(
              operationId: 'op-$i',
              entityId: 'synthetic-$i',
              operation: 'upsert',
              payload: '{}',
              createdAt: i,
            ),
          );
    }
    await tester.pumpWidget(
      MaterialApp(
        home: SyncIssuesView(
          repository: TaskRepository(db, deviceId: 'synthetic'),
          service: service,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Successivi'), 500);
    expect(find.text('Pagina 1'), findsOneWidget);
    await tester.tap(find.text('Successivi'));
    await tester.pumpAndSettle();
    expect(find.text('Pagina 2'), findsOneWidget);
    expect(find.text('Elemento da sincronizzare'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Successivi'))
          .onPressed,
      isNull,
    );
    await db.delete(db.outboxEntries).go();
    await tester.pumpAndSettle();
    expect(find.text('Nessun altro elemento'), findsOneWidget);
    await tester.tap(find.text('Precedenti'));
    await tester.pumpAndSettle();
    expect(find.text('Nessuna modifica in attesa'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await service.dispose();
      await client.dispose();
      await db.close();
    });
  });
}
