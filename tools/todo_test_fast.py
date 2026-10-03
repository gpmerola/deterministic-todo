#!/usr/bin/env python3
"""Build and deliver Todo Test by the fastest safe available route."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile


PACKAGE = "app.deterministic.todo.deterministic_todo.dev"
RELEASE_REPOSITORY = "gpmerola/deterministic-todo-releases"
RELEASE_TAG = "todo-test-latest"
DEV_BUILD_OFFSET = 2000


def read_version(pubspec: str) -> tuple[str, int]:
    match = re.search(r"^version:\s*([^+\s]+)\+(\d+)\s*$", pubspec, re.MULTILINE)
    if match is None:
        raise ValueError("pubspec version missing or invalid")
    return match.group(1), int(match.group(2))


def choose_device(adb_output: str, preferred: str | None = None) -> str | None:
    devices = []
    for line in adb_output.splitlines()[1:]:
        fields = line.split()
        if len(fields) >= 2 and fields[1] == "device":
            devices.append(fields[0])
    if preferred and preferred in devices:
        return preferred
    # Prefer USB over a duplicate TCP transport of the same physical phone.
    return next((serial for serial in devices if ":" not in serial), devices[0] if devices else None)


def make_manifest(version: str, build: int, commit: str, asset: str, digest: str) -> dict:
    url = (
        f"https://github.com/{RELEASE_REPOSITORY}/releases/download/"
        f"{RELEASE_TAG}/{asset}"
    )
    platform = {"url": url, "sha256": digest}
    return {
        "schema_version": 1,
        "version": version,
        "build": build,
        "android_version_code": DEV_BUILD_OFFSET + build,
        "source_commit": commit,
        "channel": "dev",
        "platforms": {
            "android-dev": platform,
            "android-dev-arm64-v8a": platform,
        },
    }


def run(command: list[str], *, cwd: Path, env: dict[str, str] | None = None,
        capture: bool = False) -> str:
    result = subprocess.run(
        command, cwd=cwd, env=env, check=True,
        text=True, capture_output=capture,
    )
    return result.stdout if capture else ""


def signing_environment(root: Path) -> dict[str, str]:
    key_dir = root / "private_release_keys"
    password_file = key_dir / "android-keystore-password.txt"
    keystore = key_dir / "deterministic-todo-release.jks"
    if not password_file.is_file() or not keystore.is_file():
        raise RuntimeError("private Android signing material is unavailable")
    password = password_file.read_text(encoding="utf-8").strip()
    if not password:
        raise RuntimeError("Android signing password is empty")
    environment = os.environ.copy()
    environment.update({
        "JAVA_HOME": environment.get(
            "TODO_TEST_JAVA_HOME",
            "/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home",
        ),
        "ANDROID_KEYSTORE_PATH": str(keystore),
        "ANDROID_KEYSTORE_PASSWORD": password,
        "ANDROID_KEY_ALIAS": "deterministic-todo",
        "ANDROID_KEY_PASSWORD": password,
    })
    return environment


def build(root: Path, version: str, build_number: int) -> Path:
    print(f"Building Todo Test {version}, versionCode {DEV_BUILD_OFFSET + build_number}…")
    run([
        "flutter", "build", "apk", "--release", "--flavor", "dev",
        "--target-platform", "android-arm64",
        "--build-number", str(DEV_BUILD_OFFSET + build_number),
        "--dart-define=DISTRIBUTION_CHANNEL=dev",
        "--dart-define-from-file=supabase/config.json",
    ], cwd=root, env=signing_environment(root))
    apk = root / "build/app/outputs/flutter-apk/app-dev-release.apk"
    if not apk.is_file() or apk.stat().st_size == 0:
        raise RuntimeError("Todo Test APK was not produced")
    return apk


def verify_apk(root: Path, apk: Path, expected_code: int) -> None:
    analyzer = Path(
        "/opt/homebrew/share/android-commandlinetools/cmdline-tools/latest/bin/apkanalyzer"
    )
    if not analyzer.is_file():
        raise RuntimeError("apkanalyzer is required to verify the APK")
    environment = signing_environment(root)
    application_id = run(
        [str(analyzer), "manifest", "application-id", str(apk)],
        cwd=root, env=environment, capture=True,
    ).strip()
    version_code = run(
        [str(analyzer), "manifest", "version-code", str(apk)],
        cwd=root, env=environment, capture=True,
    ).strip()
    if application_id != PACKAGE or version_code != str(expected_code):
        raise RuntimeError(
            f"APK identity mismatch: package={application_id}, versionCode={version_code}"
        )


def adb_device(root: Path) -> str | None:
    if shutil.which("adb") is None:
        return None
    output = run(["adb", "devices"], cwd=root, capture=True)
    return choose_device(output, os.environ.get("TODO_TEST_ADB_SERIAL"))


def install_adb(root: Path, apk: Path, serial: str) -> None:
    print(f"ADB device {serial}: installing in place…")
    run(["adb", "-s", serial, "install", "-r", str(apk)], cwd=root)
    installed = run([
        "adb", "-s", serial, "shell", "dumpsys", "package", PACKAGE,
    ], cwd=root, capture=True)
    if "versionName=" not in installed:
        raise RuntimeError("Todo Test package was not found after installation")
    run([
        "adb", "-s", serial, "shell", "monkey", "-p", PACKAGE,
        "-c", "android.intent.category.LAUNCHER", "1",
    ], cwd=root)
    print("Todo Test installed and opened; app data was preserved.")


def publish_remote(root: Path, apk: Path, version: str, build_number: int) -> None:
    if shutil.which("gh") is None:
        raise RuntimeError("GitHub CLI is required when no ADB device is connected")
    run(["gh", "auth", "status"], cwd=root)
    commit = run(["git", "rev-parse", "HEAD"], cwd=root, capture=True).strip()
    asset_name = f"TodoTest-{version}-{build_number}-Android-arm64-v8a.apk"
    with tempfile.TemporaryDirectory(prefix="todo-test-fast-") as directory:
        staging = Path(directory)
        staged_apk = staging / asset_name
        shutil.copy2(apk, staged_apk)
        digest = hashlib.sha256(staged_apk.read_bytes()).hexdigest()
        manifest = make_manifest(version, build_number, commit, asset_name, digest)
        manifest_path = staging / "manifest.json"
        manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
        exists = subprocess.run(
            ["gh", "release", "view", RELEASE_TAG, "--repo", RELEASE_REPOSITORY],
            cwd=root, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        ).returncode == 0
        if exists:
            # Publish the APK first so the manifest can never point to a missing asset.
            run([
                "gh", "release", "upload", RELEASE_TAG, str(staged_apk),
                "--repo", RELEASE_REPOSITORY, "--clobber",
            ], cwd=root)
            run([
                "gh", "release", "upload", RELEASE_TAG, str(manifest_path),
                "--repo", RELEASE_REPOSITORY, "--clobber",
            ], cwd=root)
            run([
                "gh", "release", "edit", RELEASE_TAG, "--repo", RELEASE_REPOSITORY,
                "--title", f"Todo Test {version} build {build_number}", "--prerelease",
            ], cwd=root)
        else:
            run([
                "gh", "release", "create", RELEASE_TAG, str(staged_apk),
                str(manifest_path), "--repo", RELEASE_REPOSITORY,
                "--title", f"Todo Test {version} build {build_number}",
                "--notes", "Rolling arm64 development channel. Not the Google Play build.",
                "--prerelease",
            ], cwd=root)
        public_assets = json.loads(run([
            "gh", "release", "view", RELEASE_TAG, "--repo", RELEASE_REPOSITORY,
            "--json", "assets",
        ], cwd=root, capture=True))["assets"]
        digest_by_name = {item["name"]: item.get("digest") for item in public_assets}
        if digest_by_name.get(asset_name) != f"sha256:{digest}":
            raise RuntimeError("published APK digest does not match the local APK")
    print("Todo Test published; use Check updates on the disconnected phone.")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--mode", choices=("auto", "adb", "remote", "build"), default="auto"
    )
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    version, build_number = read_version((root / "pubspec.yaml").read_text(encoding="utf-8"))
    serial = adb_device(root) if args.mode != "remote" else None
    if args.mode == "adb" and serial is None:
        raise RuntimeError("ADB mode requested but no authorized device is connected")
    apk = build(root, version, build_number)
    verify_apk(root, apk, DEV_BUILD_OFFSET + build_number)
    if args.mode == "build":
        print(f"Todo Test APK verified locally: {apk}")
        return 0
    if serial is not None:
        install_adb(root, apk, serial)
    else:
        publish_remote(root, apk, version, build_number)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, ValueError, subprocess.CalledProcessError) as error:
        print(f"Todo Test delivery failed: {error}", file=sys.stderr)
        raise SystemExit(1)
