import 'package:deterministic_todo/domain/agenda.dart';
import 'package:deterministic_todo/ui/views/agenda_week_block.dart';
import 'package:deterministic_todo/ui/views/agenda_word_wrap.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The painted week block (build 268) must show what the widget version
/// showed: same whole-word lines, start time from 30 px, span from 90 px.
void main() {
  const base = TextStyle(fontSize: 14);
  AgendaWeekBlockPainter painter(String title, {DateTime? start}) =>
      AgendaWeekBlockPainter(
        start: start ?? DateTime(2026, 10, 13, 9),
        end: (start ?? DateTime(2026, 10, 13, 9)).add(
          const Duration(minutes: 45),
        ),
        title: title,
        background: Colors.blue,
        border: const BorderSide(),
        textColor: Colors.white,
        baseStyle: base,
        textScaler: TextScaler.noScaling,
        textDirection: TextDirection.ltr,
      );

  // Padding 2 + 1 horizontally: content width = block width - 3.
  List<String> expected(String title, double blockWidth) {
    final width = blockWidth - 3;
    final style = base.merge(
      TextStyle(
        color: Colors.white,
        fontSize: width >= 90 ? 11 : 9.5,
        height: 1.15,
        fontWeight: FontWeight.w600,
      ),
    );
    return wrapWords(title, style, width, TextScaler.noScaling);
  }

  test('title lines equal the whole-word wrap at every width', () {
    const titles = [
      'Synthetic event 11',
      'Riunione di reparto con il direttore',
      'Visita',
      'a b c d e f g h',
      'Pranzo – team',
    ];
    for (final title in titles) {
      for (var width = 40.0; width <= 240; width += 7) {
        final lines = painter(title).debugText(Size(width, 20));
        final wrapped = expected(title, width);
        expect(lines.length, wrapped.length, reason: '$title @ $width');
        for (var i = 0; i < lines.length; i++) {
          final word = wrapped[i];
          if (lines[i].endsWith('…')) {
            // Only a single word wider than the line is cut.
            expect(word.contains(' '), isFalse, reason: '$title @ $width');
            expect(
              word.startsWith(lines[i].substring(0, lines[i].length - 1)),
              isTrue,
            );
          } else {
            expect(lines[i], word, reason: '$title @ $width');
          }
        }
      }
    }
  });

  test('a word wider than the line ends with an ellipsis', () {
    final lines = painter('Psichiatria').debugText(const Size(40, 20));
    expect(lines.single, endsWith('…'));
    expect(lines.single.length, lessThan('Psichiatria'.length + 1));
  });

  test('right-to-left text and unusual spacing keep the per-line wrap', () {
    for (final title in ['ביקור רופא שיניים', 'Due  spazi', 'A\tB']) {
      expect(painter(title).debugText(const Size(60, 20)), expected(title, 60));
    }
  });

  test('start time from 30 px high, whole span from 90 px wide', () {
    expect(painter('Visita').debugText(const Size(80, 29)), ['Visita']);
    expect(painter('Visita').debugText(const Size(80, 36)), [
      '9:00',
      'Visita',
    ]);
    expect(painter('Visita').debugText(const Size(120, 36)), [
      '9:00–9:45',
      'Visita',
    ]);
  });

  testWidgets('tap opens, long press acts, semantics name the event', (
    tester,
  ) async {
    final opened = <String>[];
    final pressed = <String>[];
    final entry = AgendaEntry(
      instanceId: 'synthetic',
      calendarIds: const ['c'],
      title: 'Evento sintetico',
      start: DateTime(2026, 10, 13, 9),
      end: DateTime(2026, 10, 13, 10),
      allDay: false,
    );
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 60,
            height: 48,
            child: AgendaWeekEventBlock(
              entry: entry,
              color: Colors.green,
              onOpen: (e) async => opened.add(e.instanceId),
              onLongPress: (e) async => pressed.add(e.instanceId),
            ),
          ),
        ),
      ),
    );
    expect(
      find.bySemanticsLabel('9:00–10:00, Evento sintetico'),
      findsOneWidget,
    );
    expect(
      tester.getSemantics(find.byType(AgendaWeekEventBlock)),
      matchesSemantics(
        label: '9:00–10:00, Evento sintetico',
        isButton: true,
        hasTapAction: true,
        hasLongPressAction: true,
      ),
    );
    await tester.tap(find.byType(AgendaWeekEventBlock));
    await tester.longPress(find.byType(AgendaWeekEventBlock));
    expect(opened, ['synthetic']);
    expect(pressed, ['synthetic']);
    semantics.dispose();
  });
}
