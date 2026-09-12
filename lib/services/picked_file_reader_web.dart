import 'dart:typed_data';

Future<String> readPickedText(Uint8List? bytes, String? path) async {
  if (bytes == null) throw const FormatException('File non leggibile');
  return String.fromCharCodes(bytes);
}
