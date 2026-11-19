import 'dart:io' show gzip;

/// Android and tests: the platform zlib.
const bool backupGzipSupported = true;
List<int> gzipEncodeBytes(List<int> bytes) => gzip.encode(bytes);
List<int> gzipDecodeBytes(List<int> bytes) => gzip.decode(bytes);
