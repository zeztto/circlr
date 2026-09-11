import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('package_app', Path(__file__).resolve().parents[1] / 'scripts/package-app.py')
package_app = importlib.util.module_from_spec(spec)
spec.loader.exec_module(package_app)


class DemoPackagingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.project = self.root / 'f0r-h3r.circlr'
        self.project.mkdir()
        (self.project / 'sample.wav').write_bytes(b'test media')
        self.write_project('sample.wav')

    def write_project(self, asset_path):
        (self.project / 'manifest.json').write_text(json.dumps({'assets': [{'path': asset_path}]}))
        self.inventory()

    def inventory(self):
        files = {p.relative_to(self.root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
                 for p in self.project.rglob('*') if p.is_file()}
        (self.root / 'manifest.json').write_text(json.dumps({
            'project': 'f0r-h3r.circlr', 'provenance': 'unit test fixture',
            'notices': ['fixture'], 'files': files}))

    def test_complete_portable_inventory(self):
        self.assertEqual(package_app.validate_demo(self.root)['project'], 'f0r-h3r.circlr')

    def test_tampered_media_rejected(self):
        (self.project / 'sample.wav').write_bytes(b'changed')
        with self.assertRaisesRegex(ValueError, 'checksum mismatch'):
            package_app.validate_demo(self.root)

    def test_missing_declared_asset_rejected(self):
        self.write_project('missing.wav')
        with self.assertRaisesRegex(ValueError, 'Missing or external'):
            package_app.validate_demo(self.root)

    def test_external_asset_rejected(self):
        self.write_project('../manifest.json')
        with self.assertRaisesRegex(ValueError, 'Missing or external'):
            package_app.validate_demo(self.root)

    def test_unlisted_file_rejected(self):
        (self.project / 'unlisted.wav').write_bytes(b'extra')
        with self.assertRaisesRegex(ValueError, 'inventory differs'):
            package_app.validate_demo(self.root)

    def test_symlink_rejected(self):
        (self.project / 'alias.wav').symlink_to(self.project / 'sample.wav')
        with self.assertRaisesRegex(ValueError, 'symlinks'):
            package_app.validate_demo(self.root)


if __name__ == '__main__':
    unittest.main()
