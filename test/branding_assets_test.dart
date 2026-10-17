import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Chrome, PWA e Apple dichiarano tutte le icone di marca', () {
    final html = File('web/index.html').readAsStringSync();
    for (final asset in const [
      'favicon-v3.svg',
      'favicon-32.png',
      'favicon.png',
      'apple-touch-icon.png',
    ]) {
      expect(html, contains(asset));
      expect(File('web/$asset').existsSync(), isTrue);
    }

    final manifest = File('web/manifest.json').readAsStringSync();
    expect(manifest, contains('Icon-192.png'));
    expect(manifest, contains('Icon-512.png'));
    expect(manifest, contains('Icon-maskable-192.png'));
    expect(manifest, contains('Icon-maskable-512.png'));

    expect(
      File('web/icons/Icon-192.png').readAsBytesSync(),
      orderedEquals(File('web/icons/Icon-maskable-192.png').readAsBytesSync()),
    );
    expect(
      File('web/icons/Icon-512.png').readAsBytesSync(),
      orderedEquals(File('web/icons/Icon-maskable-512.png').readAsBytesSync()),
    );
    expect(
      File('web/favicon-v3.svg').readAsStringSync(),
      contains('<rect width="512" height="512"'),
    );
  });
}
