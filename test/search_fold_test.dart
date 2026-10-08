import 'package:deterministic_todo/data/local/database.dart';
import 'package:deterministic_todo/data/task_repository.dart';
import 'package:deterministic_todo/domain/agenda.dart';
import 'package:deterministic_todo/domain/text_fold.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('foldAccents removes accents and keeps case', () {
    expect(foldAccents('Attività è PERCHÉ'), 'Attivita e PERCHE');
    expect(foldAccents('plain ascii'), 'plain ascii');
    expect(foldForSearch('Città Università'), 'citta universita');
    expect(foldAccents('Ñandú Çà'), 'Nandu Ca');
  });

  test('every SQL fold maps one character to one ASCII letter', () {
    for (final entry in accentFolds.entries) {
      expect(entry.key.length, 1);
      expect(RegExp(r'^[A-Za-z]$').hasMatch(entry.value), isTrue);
    }
    expect(sqlFoldAccents('x'), contains("replace(x, 'à', 'a')"));
  });

  group('task search ignores accents', () {
    late AppDatabase db;
    late TaskRepository repository;
    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repository = TaskRepository(db, deviceId: 'test-device');
    });
    tearDown(() => db.close());

    Future<List<String>> search(String text) async => [
      for (final task in await repository.watchSearch(text: text).first)
        task.title,
    ];

    test('query without accents finds accented titles and notes', () async {
      await repository.create('Rivedere attività del lunedì');
      await repository.create('Chiamare', notes: 'Perché serve il modulo');
      await repository.create('Altro');
      expect(await search('attivita'), ['Rivedere attività del lunedì']);
      expect(await search('LUNEDI'), ['Rivedere attività del lunedì']);
      expect(await search('perche'), ['Chiamare']);
    });

    test('accented query finds plain titles', () async {
      await repository.create('Citta metropolitana');
      expect(await search('città'), ['Citta metropolitana']);
    });

    test('project names match without accents', () async {
      final project = await repository.createProject('Università');
      await repository.create('Lezione', projectId: project);
      expect(await search('universita'), ['Lezione']);
    });

    test('wildcards stay literal', () async {
      await repository.create('100% fatto');
      await repository.create('1000 fatto');
      expect(await search('100%'), ['100% fatto']);
    });
  });

  test('Agenda word filters ignore accents', () {
    const filter = AgendaFilter(hiddenWords: ['perche']);
    AgendaSourceEvent event(String title) => AgendaSourceEvent(
      instanceId: '1',
      calendarId: 'c',
      title: title,
      start: DateTime(2026, 10, 5, 9),
      end: DateTime(2026, 10, 5, 10),
      allDay: false,
    );
    expect(filter.hides(event('Perché sì')), isTrue);
    expect(filter.hides(event('Altro')), isFalse);
  });
}
