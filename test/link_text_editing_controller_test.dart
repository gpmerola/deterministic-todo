import 'package:deterministic_todo/ui/link_text_editing_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('nasconde URL Markdown e li conserva al salvataggio', () {
    final controller = LinkTextEditingController.fromMarkdown(
      'Leggi [Paper1](https://example.com/paper) oggi',
    );

    expect(controller.text, 'Leggi Paper1 oggi');
    expect(controller.text, isNot(contains('https://')));
    expect(
      controller.toMarkdown(),
      'Leggi [Paper1](https://example.com/paper) oggi',
    );
  });

  test('aggiunge e rimuove un link dal testo selezionato', () {
    final controller = LinkTextEditingController.fromMarkdown('Apri ricerca');
    controller.selection = const TextSelection(baseOffset: 5, extentOffset: 12);

    expect(controller.addLink('https://example.com'), isTrue);
    expect(controller.toMarkdown(), 'Apri [ricerca](https://example.com)');
    expect(controller.removeSelectedLink(), isTrue);
    expect(controller.toMarkdown(), 'Apri ricerca');
  });

  test('rimuove direttamente un link importato dalla descrizione', () {
    final controller = LinkTextEditingController.fromMarkdown(
      '[Paper](https://example.com/paper)',
    );

    controller.removeLink(controller.links.single);

    expect(controller.text, 'Paper');
    expect(controller.links, isEmpty);
    expect(controller.toMarkdown(), 'Paper');
  });

  test('riconosce automaticamente URL completi e www', () {
    final controller = LinkTextEditingController.fromMarkdown(
      'Console https://play.google.com/console e www.example.com.',
    );

    expect(controller.links, hasLength(2));
    expect(controller.links.last.url, 'https://www.example.com');
    expect(
      controller.toMarkdown(),
      'Console [play.google.com › console](https://play.google.com/console) '
      'e [example.com](https://www.example.com).',
    );
  });

  test('sostituisce contenuto remoto conservando link leggibili', () {
    final controller = LinkTextEditingController.fromMarkdown('Prima');
    controller.replaceMarkdown(
      'Apri [documento](https://example.com/documento)',
    );

    expect(controller.text, 'Apri documento');
    expect(
      controller.toMarkdown(),
      'Apri [documento](https://example.com/documento)',
    );
    controller.dispose();
  });
}
