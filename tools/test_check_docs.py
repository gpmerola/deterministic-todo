import importlib.util
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("check_docs.py")
SPEC = importlib.util.spec_from_file_location("check_docs", MODULE_PATH)
assert SPEC and SPEC.loader
check_docs = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(check_docs)


class CheckDocsTest(unittest.TestCase):
    def test_ignores_remote_and_anchor_links(self):
        document = check_docs.ROOT / "docs" / "README.md"
        self.assertIsNone(check_docs.local_target(document, "https://example.com/a"))
        self.assertIsNone(check_docs.local_target(document, "#section"))

    def test_resolves_relative_link_and_fragment(self):
        document = check_docs.ROOT / "docs" / "README.md"
        self.assertEqual(
            check_docs.ROOT / "README.md",
            check_docs.local_target(document, "../README.md#sviluppo"),
        )


if __name__ == "__main__":
    unittest.main()
