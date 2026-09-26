import tempfile
import unittest
from pathlib import Path

from check_release_budgets import main


class ReleaseBudgetTest(unittest.TestCase):
    def test_script_source_keeps_the_android_budget_explicit(self):
        source = Path(__file__).with_name("check_release_budgets.py").read_text()
        self.assertIn("default=25.0", source)
        self.assertIn("path.stat().st_size", source)


if __name__ == "__main__":
    unittest.main()
