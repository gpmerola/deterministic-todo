"""Regression test for the public coordinated-release identity."""

from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path


class ReleaseManifestTest(unittest.TestCase):
    def test_version_build_commit_and_hashes_are_emitted(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            apks = []
            for index, name in enumerate(
                ("universal.apk", "arm64.apk", "arm32.apk", "x86.apk")
            ):
                path = root / name
                path.write_bytes(f"synthetic-apk-{index}".encode())
                apks.append(path)
            output = root / "manifest.json"

            subprocess.run(
                [
                    "python3",
                    "tools/generate_release_manifest.py",
                    "--version",
                    "9.8.7",
                    "--build",
                    "654",
                    "--source-commit",
                    "abcdef123456",
                    "--release-base-url",
                    "https://example.invalid/v9.8.7",
                    "--universal",
                    str(apks[0]),
                    "--arm64",
                    str(apks[1]),
                    "--arm32",
                    str(apks[2]),
                    "--x86-64",
                    str(apks[3]),
                    "--output",
                    str(output),
                ],
                check=True,
            )

            manifest = json.loads(output.read_text(encoding="utf-8"))
            self.assertEqual(manifest["version"], "9.8.7")
            self.assertEqual(manifest["build"], 654)
            self.assertEqual(manifest["source_commit"], "abcdef123456")
            for platform in (
                "android",
                "android-arm64-v8a",
                "android-armeabi-v7a",
                "android-x86_64",
            ):
                self.assertEqual(len(manifest["platforms"][platform]["sha256"]), 64)
                self.assertIn("/v9.8.7/", manifest["platforms"][platform]["url"])


if __name__ == "__main__":
    unittest.main()
