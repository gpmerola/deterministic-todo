#!/usr/bin/env python3
"""Measure Android Activity launch/resume times for Todo Test only.

Close any unsaved editor first. Cold samples stop only Todo Test's process;
no data is cleared. Output contains numeric timings, never screen contents.
"""
import argparse
import json
import subprocess
import time

PACKAGE = 'app.deterministic.todo.deterministic_todo.dev'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--serial', required=True)
    args = parser.parse_args()

    def adb(*parts):
        return subprocess.check_output(
            ['adb', '-s', args.serial, *parts], text=True, timeout=40,
        )

    if adb('get-state').strip() != 'device':
        raise SystemExit('Authorized device required')
    for mode in ['cold_process', 'warm_resume']:
        for sample in range(3):
            if mode == 'cold_process':
                adb('shell', 'am', 'force-stop', PACKAGE)
            else:
                adb('shell', 'input', 'keyevent', 'KEYCODE_HOME')
            time.sleep(1)
            output = adb('shell', 'am', 'start', '-W', '-n',
                         PACKAGE + '/app.deterministic.todo.deterministic_todo.MainActivity')
            result = {'phase': 'operational_android_launch', 'mode': mode, 'sample': sample}
            for line in output.splitlines():
                if line.startswith(('TotalTime:', 'WaitTime:', 'ThisTime:')):
                    name, value = line.split(':', 1)
                    result[name] = int(value)
            print(json.dumps(result), flush=True)
            time.sleep(3)


if __name__ == '__main__':
    main()
