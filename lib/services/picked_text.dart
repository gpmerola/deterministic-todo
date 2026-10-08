import 'dart:convert';
import 'dart:typed_data';

/// Text of a picked JSON file (backup or Todoist export).
///
/// Exports are written as UTF-8. Decoding bytes one per character (Latin-1)
/// turned every accented letter into two wrong ones; a leading BOM, added by
/// some editors, would also break the JSON parser.
String decodePickedText(Uint8List bytes) {
  final text = utf8.decode(bytes);
  return text.startsWith('﻿') ? text.substring(1) : text;
}
