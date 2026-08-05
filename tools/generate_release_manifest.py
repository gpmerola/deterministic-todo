#!/usr/bin/env python3
"""Generate the public OTA manifest from verified release artifacts."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", required=True)
    parser.add_argument("--build", required=True, type=int)
    parser.add_argument("--source-commit", required=True)
    parser.add_argument("--release-base-url", required=True)
    parser.add_argument("--arm64", required=True, type=Path)
    parser.add_argument("--arm32", required=True, type=Path)
    parser.add_argument("--x86-64", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    assets = {
        "android-arm64-v8a": args.arm64,
        "android-armeabi-v7a": args.arm32,
        "android-x86_64": args.x86_64,
    }
    for path in assets.values():
        if not path.is_file() or path.stat().st_size == 0:
            raise SystemExit(f"Missing or empty APK: {path}")

    base = args.release_base_url.rstrip("/")
    platforms = {
        # Bootstrap for clients older than the ABI-aware updater.
        "android": {
            "url": "https://github.com/gpmerola/deterministic-todo-releases/"
            "releases/download/v1.0.4/DeterministicTodo-Android-universal.apk",
            "sha256": "25ecf3cc74b950d782884be0a959f41a8ef1127fa5ea8765acdba005f22a6679",
        }
    }
    names = {
        "android-arm64-v8a": "DeterministicTodo-Android-arm64-v8a.apk",
        "android-armeabi-v7a": "DeterministicTodo-Android-armeabi-v7a.apk",
        "android-x86_64": "DeterministicTodo-Android-x86_64.apk",
    }
    for platform, path in assets.items():
        platforms[platform] = {
            "url": f"{base}/{names[platform]}",
            "sha256": sha256(path),
        }

    manifest = {
        "schema_version": 1,
        "version": args.version,
        "build": args.build,
        "source_commit": args.source_commit,
        "platforms": platforms,
    }
    args.output.write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
