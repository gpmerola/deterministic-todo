import 'dart:async';

import 'package:deterministic_todo/data/local/database.dart';
import 'package:deterministic_todo/data/task_repository.dart';
import 'package:deterministic_todo/main.dart';
import 'package:deterministic_todo/services/app_runtime.dart';
import 'package:deterministic_todo/ui/views/upcoming_view.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  testWidgets('late remote client attaches without resetting navigation', (
    tester,
  ) async {
    const channel = MethodChannel(
      'dev.fluttercommunity.plus/connectivity_status',
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) async => null,
    );
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repo = TaskRepository(db, deviceId: 'synthetic');
    final remote = Completer<SupabaseClient?>();
    final client = (await tester.runAsync(
      () async => SupabaseClient(
        'http://127.0.0.1:1',
        'synthetic-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      ),
    ))!;
    final runtime = AppRuntime(
      openLocal: () async => repo,
      openRemote: () => remote.future,
      beforeSyncStart: (service) => service.pause(),
    );
    await tester.pumpWidget(
      BootstrapApp(runtime: runtime, enablePlatformServices: false),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Prossime'));
    await tester.pumpAndSettle();
    final state = tester.state(find.byType(TaskShell));
    remote.complete(client);
    await tester.pumpAndSettle();
    final shell = tester.widget<TaskShell>(find.byType(TaskShell));
    expect(shell.syncClient, same(client));
    expect(shell.syncService, isNotNull);
    expect(identical(state, tester.state(find.byType(TaskShell))), isTrue);
    expect(find.byType(UpcomingTaskList), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await client.dispose();
      await db.close();
    });
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      null,
    );
  });

  testWidgets(
    'local tasks and navigation work while remote startup is stalled',
    (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final repo = TaskRepository(db, deviceId: 'synthetic');
      await repo.create('Synthetic local task');
      final remote = Completer<SupabaseClient?>();
      final runtime = AppRuntime(
        openLocal: () async => repo,
        openRemote: () => remote.future,
      );
      await tester.pumpWidget(
        BootstrapApp(runtime: runtime, enablePlatformServices: false),
      );
      await tester.pumpAndSettle();
      expect(find.text('Synthetic local task'), findsOneWidget);
      await tester.tap(find.text('Prossime'));
      await tester.pumpAndSettle();
      final shell = tester.state(find.byType(TaskShell));
      remote.complete(null);
      await tester.pumpAndSettle();
      expect(identical(shell, tester.state(find.byType(TaskShell))), isTrue);
      expect(find.text('Synthetic local task'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.runAsync(db.close);
    },
  );

  testWidgets('remote failure is recoverable without losing the local shell', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repo = TaskRepository(db, deviceId: 'synthetic');
    await repo.create('Synthetic offline task');
    var attempts = 0;
    final runtime = AppRuntime(
      openLocal: () async => repo,
      openRemote: () async {
        if (++attempts == 1) throw StateError('synthetic failure');
        return null;
      },
    );
    await tester.pumpWidget(
      BootstrapApp(runtime: runtime, enablePlatformServices: false),
    );
    await tester.pumpAndSettle();
    expect(find.text('Synthetic offline task'), findsOneWidget);
    expect(find.text('Riprova'), findsOneWidget);
    final shell = tester.state(find.byType(TaskShell));
    await tester.tap(find.text('Riprova'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.text('Riprova'), findsNothing);
    expect(identical(shell, tester.state(find.byType(TaskShell))), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.runAsync(db.close);
  });
}
