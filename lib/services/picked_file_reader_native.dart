import 'dart:io';
import 'dart:typed_data';

Future<String> readPickedText(Uint8List? bytes, String? path) async {
  if (bytes != null) return String.fromCharCodes(bytes);
  if (path == null) throw const FormatException('File non leggibile');
  return File(path).readAsString();
}
