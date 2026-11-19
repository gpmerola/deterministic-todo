/// The browser build has no `dart:io`; cloud backups are Android only.
const bool backupGzipSupported = false;
List<int> gzipEncodeBytes(List<int> bytes) =>
    throw UnsupportedError('gzip is not available on the web');
List<int> gzipDecodeBytes(List<int> bytes) =>
    throw UnsupportedError('gzip is not available on the web');
