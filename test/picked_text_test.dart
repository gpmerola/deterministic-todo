import 'dart:convert';
import 'dart:typed_data';

import 'package:deterministic_todo/services/picked_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('un backup esportato in UTF-8 conserva le lettere accentate', () {
    final exported = jsonEncode({'title': 'Perché città più ✨'});
    final read = decodePickedText(Uint8List.fromList(utf8.encode(exported)));
    expect(jsonDecode(read), {'title': 'Perché città più ✨'});
  });

  test('il BOM iniziale non rompe il JSON', () {
    final bytes = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode('{}')]);
    expect(jsonDecode(decodePickedText(bytes)), isEmpty);
  });

  test('un file non UTF-8 viene rifiutato invece di essere alterato', () {
    expect(
      () => decodePickedText(Uint8List.fromList([0x7B, 0xE8, 0x7D])),
      throwsFormatException,
    );
  });
}
