#!/usr/bin/env python3
"""Build Web with embedded identity and fingerprinted executable URLs."""

import hashlib
import re
import subprocess
from pathlib import Path


def fingerprint_assets(directory: Path) -> None:
    # Rewrite dependencies before hashing their parent. Stable paths with a
    # content query also let an older cached index load after a deployment;
    # removing old hashed filenames would otherwise turn that into a 404.
    for name, parent in [
        ('main.dart.js', 'flutter_bootstrap.js'),
        ('flutter_bootstrap.js', 'index.html'),
    ]:
        data = (directory / name).read_bytes()
        digest = hashlib.sha256(data).hexdigest()
        target = f'{name}?v={digest}'
        path = directory / parent
        original = path.read_text(encoding='utf-8')
        if name not in original:
            raise ValueError(f'{parent} does not reference {name}')
        path.write_text(original.replace(name, target), encoding='utf-8')


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    match = re.search(r'^version: ([^+\s]+)\+(\d+)$',
                      (root / 'pubspec.yaml').read_text(), re.MULTILINE)
    if match is None:
        raise ValueError('Invalid pubspec version')
    version, build = match.groups()
    subprocess.run([
        'flutter', 'build', 'web', '--release', '--no-pub',
        '--no-wasm-dry-run', '--base-href', '/deterministic-todo/',
        '--dart-define-from-file=supabase/config.json',
        f'--dart-define=TODO_VERSION={version}',
        f'--dart-define=TODO_BUILD={build}',
    ], cwd=root, check=True)
    fingerprint_assets(root / 'build/web')


if __name__ == '__main__':
    main()
