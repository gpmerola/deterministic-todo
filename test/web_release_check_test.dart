import 'package:deterministic_todo/services/update_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final url = Uri.parse('https://example.invalid/release-info.json');
  Map<String, Object?> info(String version, int build) => {
    'schema_version': 1,
    'version': version,
    'build': build,
    'source_commit': '0' * 40,
  };

  test('a Web tab proposes a reload only for a newer deployment', () {
    AvailableUpdate? check(Object? root, {int? build = 281}) =>
        UpdateService.newerWebRelease(
          root,
          installedVersion: '2.101.0',
          installedBuild: build,
          url: url,
        );
    expect(check(info('2.102.0', 282))?.build, 282);
    expect(check(info('2.102.0', 282))?.url, url);
    expect(check(info('2.101.0', 281)), isNull);
    expect(check(info('2.100.0', 280)), isNull);
    // A local or unidentified bundle never nags.
    expect(check(info('2.102.0', 282), build: null), isNull);
    expect(
      check({'schema_version': 2, 'version': '9.0.0', 'build': 900}),
      isNull,
    );
    expect(check('not json'), isNull);
  });
}
