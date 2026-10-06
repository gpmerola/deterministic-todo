#!/usr/bin/env python3
"""Run the native Agenda smoke harness only on an authorized emulator.

Builds a temporary test entrypoint in Todo Test on the emulator. The normal
phone installation is untouched. Existing APK deliverables are restored after building the harness.
"""
import argparse
from pathlib import Path
import subprocess
import shutil
import tempfile
import time
from todo_test_fast import DEV_BUILD_OFFSET, read_version, signing_environment


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--serial', default='emulator-5554')
    args = parser.parse_args()
    if not args.serial.startswith('emulator-'):
        raise SystemExit('Only an emulator is allowed')
    root = Path(__file__).resolve().parents[1]
    def adb(*parts):
        return subprocess.check_output(['adb', '-s', args.serial, *parts], text=True, timeout=60)
    if adb('shell', 'getprop', 'ro.kernel.qemu').strip() != '1':
        raise SystemExit('Emulator identity not verified')
    package = 'app.deterministic.todo.deterministic_todo.dev'
    _, build = read_version((root / 'pubspec.yaml').read_text())
    apk = root / 'build/app/outputs/flutter-apk/app-arm64-v8a-dev-release.apk'
    # Preserve normal deliverables; never leave a test entrypoint as an OTA APK.
    with tempfile.TemporaryDirectory(prefix='agenda-smoke-') as folder:
        saved = Path(folder)
        outputs = list(apk.parent.glob('*-dev-release.apk*'))
        for output in outputs:
            shutil.copy2(output, saved / output.name)
        try:
            subprocess.run(['flutter', 'build', 'apk', '--release', '--flavor', 'dev',
                            '--split-per-abi', f'--build-number={DEV_BUILD_OFFSET + build}',
                            '--target=integration_test/agenda_provider_smoke.dart'],
                           cwd=root, env=signing_environment(root), check=True)
            harness = saved / 'harness.apk'
            shutil.copy2(apk, harness)
        finally:
            for output in apk.parent.glob('*-dev-release.apk*'):
                if (saved / output.name).exists():
                    shutil.copy2(saved / output.name, output)
                else:
                    output.unlink()
        adb('install', '-r', str(harness))
    adb('shell', 'pm', 'grant', package, 'android.permission.READ_CALENDAR')
    adb('shell', 'pm', 'grant', package, 'android.permission.WRITE_CALENDAR')
    adb('shell', 'am', 'force-stop', package)
    # Read only the new harness process and fixed result marker, never general logs.
    adb('shell', 'am', 'start', '-W', '-n', package + '/app.deterministic.todo.deterministic_todo.MainActivity')
    for _ in range(30):
        pid = adb('shell', 'pidof', package).strip()
        if pid:
            log = adb('logcat', '-d', '--pid=' + pid, '-s', 'flutter:I')
            for line in log.splitlines():
                if 'AGENDA_PROVIDER_SMOKE:' in line:
                    result = line.split('AGENDA_PROVIDER_SMOKE:')[-1].strip()
                    print('Agenda native provider smoke: ' + result)
                    return 0 if result == 'PASS' else 1
        time.sleep(1)
    raise SystemExit('No native smoke result within 30 seconds')

if __name__ == '__main__':
    raise SystemExit(main())
