import tempfile
import unittest
from pathlib import Path

from build_web import fingerprint_assets


class WebAssetTest(unittest.TestCase):
    def test_changed_bundle_invalidates_both_urls_and_keeps_stable_paths(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            def build(code):
                (root / 'main.dart.js').write_text(code)
                (root / 'flutter_bootstrap.js').write_text('load("main.dart.js")')
                (root / 'index.html').write_text('<script src="flutter_bootstrap.js"></script>')
                fingerprint_assets(root)
                bootstrap = (root / 'index.html').read_text().split('"')[1]
                main = (root / bootstrap.split('?')[0]).read_text().split('"')[1]
                return bootstrap, main
            first = build('version=246; repair=true;')
            second = build('version=247; repair=true;')
            self.assertNotEqual(first[0], second[0])
            self.assertNotEqual(first[1], second[1])
            self.assertEqual(first[1].split('?')[0], second[1].split('?')[0])
            self.assertEqual((root / second[1].split('?')[0]).read_text(), 'version=247; repair=true;')
            self.assertEqual(second, build('version=247; repair=true;'))

    def test_unexpected_loader_fails_instead_of_publishing_unversioned_code(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'main.dart.js').write_text('app')
            (root / 'flutter_bootstrap.js').write_text('different loader')
            with self.assertRaises(ValueError):
                fingerprint_assets(root)
