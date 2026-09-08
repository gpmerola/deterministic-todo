#!/usr/bin/env python3
"""Fail a release when generated clients exceed explicit size budgets."""

import argparse
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--max-apk-mib", type=float, default=25.0)
    parser.add_argument("apk", nargs="+")
    args = parser.parse_args()
    limit = int(args.max_apk_mib * 1024 * 1024)
    failed = []
    for raw in args.apk:
        path = Path(raw)
        size = path.stat().st_size
        print(f"{path.name}: {size / 1024 / 1024:.2f} MiB")
        if size > limit:
            failed.append(path.name)
    if failed:
        parser.error(
            f"budget {args.max_apk_mib:.1f} MiB superato: {', '.join(failed)}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
