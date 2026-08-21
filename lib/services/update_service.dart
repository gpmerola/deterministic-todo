import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'platform_runtime_native.dart'
    if (dart.library.js_interop) 'platform_runtime_web.dart';

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

  static const distributionChannel = String.fromEnvironment(
    'DISTRIBUTION_CHANNEL',
    defaultValue: 'direct',
  );

  static Uri cacheBustedManifest(Uri manifest, DateTime now) =>
      manifest.replace(
        queryParameters: {
          ...manifest.queryParameters,
          'check': '${now.toUtc().millisecondsSinceEpoch}',
        },
      );

  Future<AvailableUpdate?> check() async {
    final response = await _client
        .get(
          cacheBustedManifest(_manifest, DateTime.now()),
          headers: const {'Cache-Control': 'no-cache'},
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) return null;
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
    if (isAndroidPlatform) {
      final abi = await OtaUpdate().getAbi();
      platformKey = platformKeyFor(
        distributionChannel: distributionChannel,
        abi: abi,
        available: platforms.keys,
      );
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

  static String? platformKeyFor({
    required String distributionChannel,
    required String? abi,
    required Iterable<String> available,
  }) {
    final keys = available.toSet();
    final prefix = distributionChannel == 'dev' ? 'android-dev' : 'android';
    final abiKey = abi == null ? null : '$prefix-$abi';
    if (abiKey != null && keys.contains(abiKey)) return abiKey;
    return keys.contains(prefix) ? prefix : null;
  }

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
