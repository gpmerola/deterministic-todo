import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AvailableUpdate {
  const AvailableUpdate({
    required this.version,
    required this.url,
    this.sha256,
  });

  final String version;
  final Uri url;
  final String? sha256;
}

class UpdateService {
  UpdateService({http.Client? client, Uri? manifest})
    : _client = client ?? http.Client(),
      _manifest = manifest ?? manifestUri;

  static final manifestUri = Uri.parse(
    'https://github.com/gpmerola/deterministic-todo-releases/'
    'releases/latest/download/manifest.json',
  );

  final http.Client _client;
  final Uri _manifest;

  Future<AvailableUpdate?> check() async {
    final response = await _client
        .get(_manifest)
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != HttpStatus.ok) return null;
    final root = jsonDecode(response.body);
    if (root is! Map<String, Object?> || root['schema_version'] != 1) {
      return null;
    }
    final remoteVersion = root['version'];
    final platforms = root['platforms'];
    if (remoteVersion is! String || platforms is! Map<String, Object?>) {
      return null;
    }
    String? platformKey;
    if (Platform.isMacOS) {
      platformKey = 'macos';
    } else if (Platform.isWindows) {
      platformKey = 'windows';
    } else if (Platform.isAndroid) {
      final abi = await OtaUpdate().getAbi();
      final abiKey = abi == null ? null : 'android-$abi';
      platformKey = abiKey != null && platforms.containsKey(abiKey)
          ? abiKey
          : 'android';
    }
    if (platformKey == null) return null;
    final platform = platforms[platformKey];
    if (platform is! Map<String, Object?> || platform['url'] is! String) {
      return null;
    }
    final current = await PackageInfo.fromPlatform();
    if (!isNewerVersion(remoteVersion, current.version)) return null;
    return AvailableUpdate(
      version: remoteVersion,
      url: Uri.parse(platform['url']! as String),
      sha256: platform['sha256'] as String?,
    );
  }

  static bool isNewerVersion(String candidate, String installed) =>
      _compareVersions(candidate, installed) > 0;

  static int _compareVersions(String left, String right) {
    final a = left.split('.').map((value) => int.tryParse(value) ?? 0).toList();
    final b = right
        .split('.')
        .map((value) => int.tryParse(value) ?? 0)
        .toList();
    for (var index = 0; index < 3; index++) {
      final difference =
          (index < a.length ? a[index] : 0) - (index < b.length ? b[index] : 0);
      if (difference != 0) return difference;
    }
    return 0;
  }
}
