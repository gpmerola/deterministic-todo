#!/usr/bin/env python3
"""Synthetic notification check in isolated Todo Validation; no calendar access.

Usage: python3 tools/urgent_visit_smoke.py --serial SERIAL
Posts one generic urgent notification. Leaves it visible for visual review.
Existing APK deliverables are restored; never publishes the harness.
"""
import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
from todo_test_fast import read_version, signing_environment


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--serial', required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    package = 'app.deterministic.todo.deterministic_todo.dev.validation'

    def adb(*parts):
        return subprocess.check_output(['adb', '-s', args.serial, *parts], text=True, timeout=300 if parts[0] == 'install' else 60)

    if adb('get-state').strip() != 'device':
        raise SystemExit('Authorized device required')
    _, build = read_version((root / 'pubspec.yaml').read_text())
    environment = signing_environment(root)
    environment['ORG_GRADLE_PROJECT_todoValidation'] = 'true'
    outputs = root / 'build/app/outputs/flutter-apk'
    apk = outputs / 'app-arm64-v8a-dev-release.apk'
    with tempfile.TemporaryDirectory(prefix='urgent-visit-smoke-') as folder:
        saved = Path(folder)
        for output in outputs.glob('*-dev-release.apk*'):
            shutil.copy2(output, saved / output.name)
        try:
            subprocess.run(['flutter', 'build', 'apk', '--release', '--flavor', 'dev',
                            '--split-per-abi', '--target-platform=android-arm64',
                            f'--build-number={build}',
                            '--target=integration_test/agenda_urgent_visit_smoke.dart'],
                           cwd=root, env=environment, check=True)
            harness = saved / 'harness.apk'
            shutil.copy2(apk, harness)
        finally:
            for output in outputs.glob('*-dev-release.apk*'):
                if (saved / output.name).exists():
                    shutil.copy2(saved / output.name, output)
                else:
                    output.unlink()
        adb('install', '-r', str(harness))
    if int(adb('shell', 'getprop', 'ro.build.version.sdk').strip()) >= 33:
        adb('shell', 'pm', 'grant', package, 'android.permission.POST_NOTIFICATIONS')
    adb('shell', 'am', 'force-stop', package)
    adb('shell', 'am', 'start', '-W', '-n', package + '/app.deterministic.todo.deterministic_todo.MainActivity')
    for _ in range(30):
        pid = adb('shell', 'pidof', package).strip()
        if pid:
            log = adb('logcat', '-d', '--pid=' + pid, '-s', 'flutter:I')
            for line in log.splitlines():
                if 'AGENDA_URGENT_SMOKE:' in line:
                    result = line.split('AGENDA_URGENT_SMOKE:')[-1].strip()
                    print('Urgent visit native smoke: ' + result)
                    return 0 if result == 'PASS' else 1
        time.sleep(1)
    raise SystemExit('No smoke result within deadline')


if __name__ == '__main__':
    raise SystemExit(main())
