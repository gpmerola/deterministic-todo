import 'dart:async';

import 'package:deterministic_todo/data/local/database.dart';
import 'package:deterministic_todo/data/task_repository.dart';
import 'package:deterministic_todo/ui/search.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _Repository extends Mock implements TaskRepository {}

void main() {
  testWidgets('text/filter changes hide old rows; errors retry independently', (
    tester,
  ) async {
    final repo = _Repository();
    final reads = <StreamController<List<Task>>>[];
    when(
      () => repo.watchSearch(
        text: any(named: 'text'),
        projectOnly: any(named: 'projectOnly'),
        onDate: any(named: 'onDate'),
        undated: any(named: 'undated'),
        recurring: any(named: 'recurring'),
        highPriority: any(named: 'highPriority'),
      ),
    ).thenAnswer((_) {
      final stream = StreamController<List<Task>>();
      reads.add(stream);
      return stream.stream;
    });
    final delegate = TaskSearchDelegate(
      repo,
      onNavigate: (_) {},
      onCreate: (_) async {},
      tileBuilder: (task) => Text(task.title),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                showSearch<void>(context: context, delegate: delegate),
            child: const Text('Apri'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Apri'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final row = Task(
      id: 'fixture',
      itemKind: 'task',
      priority: 0,
      logicalVersion: 0,
      title: 'Synthetic old result',
      status: 'scheduled',
      position: 0,
      createdAt: 0,
      updatedAt: 0,
      deviceId: 'synthetic',
    );
    reads.last.add([row]);
    await tester.pump();
    expect(find.text(row.title), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'new');
    await tester.pump();
    expect(find.text(row.title), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    // A rapid second query must ignore a late result from the first.
    final previousIndex = reads.length - 1;
    await tester.enterText(find.byType(TextField), 'newer');
    await tester.pump();
    reads[previousIndex].add([row]);
    await tester.pump();
    expect(find.text(row.title), findsNothing);
    reads.last.add([row]);
    await tester.pump();
    await tester.tap(find.text('Senza data'));
    await tester.pump();
    expect(find.text(row.title), findsNothing);
    reads.last.addError(StateError('private error must not be displayed'));
    await tester.pump();
    expect(find.text('Ricerca attività non riuscita.'), findsOneWidget);
    expect(find.text('Nessuna attività trovata.'), findsNothing);
    expect(find.textContaining('private error'), findsNothing);
    final beforeRetry = reads.length;
    await tester.tap(find.text('Riprova'));
    await tester.pump();
    expect(reads.length, beforeRetry + 1);
    reads.last.add([]);
    await tester.pumpAndSettle();
    expect(find.text('Nessuna attività trovata.'), findsOneWidget);
    expect(find.text('Riprova'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    delegate.dispose();
    for (final read in reads) {
      unawaited(read.close());
    }
  });
}
