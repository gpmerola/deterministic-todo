#!/usr/bin/env python3
"""Release benchmark on an authorized Android device, synthetic data only.

Builds a separate .dev.validation package. Never publishes the harness or
reads the operational database. Results are numeric JSON lines on stdout.
Usage: python3 tools/device_performance.py --serial SERIAL [--scenario calendar]
`calendar` runs only the week-view scroll, alternating the build 267 view and
the current one in the same process; no backup.
"""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

from todo_test_fast import read_version, signing_environment

PACKAGE = 'app.deterministic.todo.deterministic_todo.dev.validation'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--serial', required=True)
    parser.add_argument('--scenario', choices=['all', 'calendar'], default='all')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]

    def adb(*parts):
        return subprocess.check_output(
            ['adb', '-s', args.serial, *parts], text=True,
            timeout=300 if parts[0] == 'install' else 60,
        )

    if adb('get-state').strip() != 'device':
        raise SystemExit('Authorized device required')
    _, build = read_version((root / 'pubspec.yaml').read_text())
    environment = signing_environment(root)
    environment['ORG_GRADLE_PROJECT_todoValidation'] = 'true'
    outputs = root / 'build/app/outputs/flutter-apk'
    apk = outputs / 'app-arm64-v8a-dev-release.apk'
    with tempfile.TemporaryDirectory(prefix='todo-device-benchmark-') as folder:
        saved = Path(folder)
        for output in outputs.glob('*-dev-release.apk*'):
            shutil.copy2(output, saved / output.name)
        try:
            subprocess.run([
                'flutter', 'build', 'apk', '--release', '--flavor', 'dev',
                '--split-per-abi', '--target-platform=android-arm64',
                f'--build-number={build}', '--dart-define=TODO_VALIDATION=true',
                f'--dart-define=TODO_PERF_SCENARIO={args.scenario}',
                '--target=integration_test/device_performance.dart',
            ], cwd=root, env=environment, check=True)
            harness = saved / 'harness.apk'
            shutil.copy2(apk, harness)
        finally:
            # Restore operational APKs: the harness cannot become a deliverable.
            for output in outputs.glob('*-dev-release.apk*'):
                if (saved / output.name).exists():
                    shutil.copy2(saved / output.name, output)
                else:
                    output.unlink()
        adb('install', '-r', str(harness))
    adb('shell', 'am', 'force-stop', PACKAGE)
    launch = adb('shell', 'am', 'start', '-W', '-n',
                 PACKAGE + '/app.deterministic.todo.deterministic_todo.MainActivity')
    for line in launch.splitlines():
        if line.startswith(('TotalTime:', 'ThisTime:', 'WaitTime:')):
            name, value = line.split(':', 1)
            print(json.dumps({'phase': 'harness_android_launch', name: int(value)}), flush=True)
    seen = set()
    deadline = time.monotonic() + (240 if args.scenario == 'all' else 480)
    try:
        while time.monotonic() < deadline:
            pid = adb('shell', 'pidof', PACKAGE).strip()
            if pid:
                # Filter before output: no native logs or contents are printed.
                log = adb('logcat', '-d', '--pid=' + pid, '-s', 'flutter:I')
                for line in log.splitlines():
                    if 'TODO_PERF: ' not in line:
                        continue
                    record = line.split('TODO_PERF: ', 1)[1]
                    if record in seen:
                        continue
                    seen.add(record)
                    measurement = json.loads(record)
                    print(json.dumps(measurement), flush=True)
                    if measurement['phase'] == 'complete':
                        return 0 if measurement['result'] == 'PASS' else 1
            time.sleep(2)
        raise SystemExit('Benchmark deadline exceeded; no completed result')
    finally:
        adb('shell', 'am', 'force-stop', PACKAGE)


if __name__ == '__main__':
    raise SystemExit(main())
