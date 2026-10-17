import unittest

import subprocess

from todo_test_fast import choose_device, deliver, make_manifest, read_version


class TodoTestFastTest(unittest.TestCase):
    def test_reads_pubspec_version_and_dev_code_is_separate(self):
        self.assertEqual(read_version("name: x\nversion: 2.26.7+130\n"), ("2.26.7", 130))

    def test_prefers_usb_and_honours_explicit_serial(self):
        devices = "List of devices attached\n100.1.2.3:5555\tdevice\nUSB123\tdevice\n"
        self.assertEqual(choose_device(devices), "USB123")
        self.assertEqual(choose_device(devices, "100.1.2.3:5555"), "100.1.2.3:5555")

    def test_manifest_has_only_dev_platforms_and_declares_version_code(self):
        result = make_manifest("2.26.7", 130, "abc", "todo.apk", "0" * 64)
        self.assertEqual(result["android_version_code"], 2130)
        self.assertEqual(set(result["platforms"]), {"android-dev", "android-dev-arm64-v8a"})

    def test_auto_mode_publishes_when_adb_install_fails(self):
        calls = []

        def failing_install(serial):
            calls.append(("install", serial))
            raise subprocess.CalledProcessError(1, ["adb", "install"])

        deliver("auto", "phone:5555", failing_install, lambda: calls.append(("publish",)))
        self.assertEqual(calls, [("install", "phone:5555"), ("publish",)])

    def test_adb_mode_does_not_fall_back_to_publishing(self):
        def failing_install(serial):
            raise subprocess.CalledProcessError(1, ["adb", "install"])

        with self.assertRaises(subprocess.CalledProcessError):
            deliver("adb", "phone:5555", failing_install, lambda: self.fail("published"))

    def test_successful_install_does_not_publish(self):
        deliver("auto", "phone:5555", lambda serial: None, lambda: self.fail("published"))


if __name__ == "__main__":
    unittest.main()
