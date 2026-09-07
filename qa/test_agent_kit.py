import hashlib
import importlib.util
import json
import plistlib
from pathlib import Path
import re
import shutil
import sys
import tempfile
import tomllib
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
KIT = ROOT / 'Resources/Codex'
spec = importlib.util.spec_from_file_location('circlr_install', KIT / 'install.py')
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class KitTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='circlr-kit-test-')
        self.addCleanup(self.tmp.cleanup)
        self.project = Path(self.tmp.name) / 'Artist project 한글'
        self.project.mkdir()

    def run_install(self, **kwargs):
        return installer.install(KIT, self.project, sys.executable, **kwargs)

    def test_manifest_references_and_roles(self):
        manifest = installer.load_kit(KIT)
        self.assertEqual(manifest['version'], plistlib.loads((ROOT/'Resources/Info.plist').read_bytes())['CFBundleShortVersionString'])
        skill = KIT / 'skills/circlr-studio'
        for p in skill.rglob('*.md'):
            for link in re.findall(r'\]\(([^)]+)\)', p.read_text()):
                if '://' not in link:
                    self.assertTrue((p.parent / link).is_file(), (p, link))
        roles = json.loads((KIT / 'roles.json').read_text())
        self.assertEqual(len(roles), 8)
        self.assertEqual(len(set(r['id'] for r in roles)), 8)
        self.assertEqual((skill / 'scripts/mcp_server.py').read_bytes(), (ROOT / 'mcp/server.py').read_bytes())

    def test_dry_run_install_idempotence_and_agent_isolation(self):
        self.assertTrue(self.run_install(dry_run=True)['changedFiles'])
        self.assertEqual(list(self.project.iterdir()), [])
        result = self.run_install()
        self.assertEqual(len(result['agents']), 8)
        self.assertEqual(self.run_install()['changedFiles'], [])
        cfg = tomllib.loads((self.project / '.codex/config.toml').read_text())
        self.assertEqual(list(cfg), ['mcp_servers'])
        for p in (self.project / '.codex/agents').glob('*.toml'):
            agent = tomllib.loads(p.read_text())
            self.assertNotIn('model', agent)
            self.assertNotIn('model_reasoning_effort', agent)
            self.assertEqual(agent['sandbox_mode'], 'read-only')
            self.assertEqual(agent['mcp_servers']['circlr']['args'][-1], '--read-only')
            self.assertTrue(Path(agent['mcp_servers']['circlr']['args'][0]).is_file())
            self.assertNotIn('__SKILL_PATH__', agent['developer_instructions'])

    def test_existing_unrelated_config_preserved(self):
        (self.project / '.codex').mkdir()
        original = '# artist choice\nmodel_reasoning_effort = "low"\n[agents]\nenabled = false\n'
        (self.project / '.codex/config.toml').write_text(original)
        self.run_install()
        self.assertTrue((self.project / '.codex/config.toml').read_text().startswith(original))
        self.assertFalse(tomllib.loads((self.project / '.codex/config.toml').read_text())['agents']['enabled'])

    def test_user_edits_are_not_overwritten(self):
        self.run_install()
        p = self.project / '.agents/skills/circlr-studio/SKILL.md'
        p.write_text(p.read_text() + '\nArtist local change\n')
        before = p.read_bytes()
        with self.assertRaisesRegex(ValueError, 'Locally modified'):
            self.run_install()
        self.assertEqual(p.read_bytes(), before)
        self.assertFalse((self.project / '.circlr-agent-install.lock').exists())

    def test_unmanaged_skill_or_mcp_conflict_changes_nothing(self):
        p = self.project / '.codex/config.toml'
        p.parent.mkdir()
        p.write_text('[mcp_servers.circlr]\ncommand = "custom-server"\n')
        with self.assertRaisesRegex(ValueError, 'Existing mcp_servers'):
            self.run_install()
        self.assertFalse((self.project / '.agents').exists())
        p.unlink()
        skill = self.project / '.agents/skills/circlr-studio/SKILL.md'
        skill.parent.mkdir(parents=True)
        skill.write_text('User-owned skill')
        with self.assertRaisesRegex(ValueError, 'Unmanaged file conflict'):
            self.run_install()
        self.assertFalse(p.exists())
        self.assertEqual(skill.read_text(), 'User-owned skill')

    def test_symlink_escape_is_rejected(self):
        outside = Path(self.tmp.name) / 'outside'
        outside.mkdir()
        (self.project / '.agents').symlink_to(outside, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, 'symlink'):
            self.run_install()
        self.assertEqual(list(outside.iterdir()), [])

    def test_tampered_kit_rejected(self):
        copy = Path(self.tmp.name) / 'kit'
        shutil.copytree(KIT, copy)
        (copy / 'skills/circlr-studio/SKILL.md').write_text('corrupted')
        with self.assertRaisesRegex(ValueError, 'integrity mismatch'):
            installer.install(copy, self.project, sys.executable)
        self.assertEqual(list(self.project.iterdir()), [])

    def test_failed_install_rolls_back_files(self):
        original_replace = installer.replace_file
        count = 0
        def flaky(path, data):
            nonlocal count
            count += 1
            if count == 4:
                raise OSError('injected filesystem failure')
            return original_replace(path, data)
        with patch.object(installer, 'replace_file', side_effect=flaky):
            with self.assertRaisesRegex(OSError, 'injected'):
                self.run_install()
        self.assertEqual([p for p in self.project.rglob('*') if p.is_file()], [])
        self.assertTrue(self.run_install()['changedFiles'])

    def test_managed_upgrade_and_update_failure_restore(self):
        self.run_install()
        before = {str(p.relative_to(self.project)): p.read_bytes() for p in self.project.rglob('*') if p.is_file()}
        copy = Path(self.tmp.name) / 'new-kit'
        shutil.copytree(KIT, copy)
        source = copy / 'skills/circlr-studio/references/roles/producer.md'
        source.write_text(source.read_text() + '\nVersioned guidance.\n')
        manifest = json.loads((copy / 'manifest.json').read_text())
        manifest['version'] = '0.12.1'
        manifest['files'][str(source.relative_to(copy))] = hashlib.sha256(source.read_bytes()).hexdigest()
        (copy / 'manifest.json').write_text(json.dumps(manifest))
        original_replace = installer.replace_file
        failed = False
        def fail_state(path, data):
            nonlocal failed
            if path.name == 'circlr-agent-kit.json' and not failed:
                failed = True
                raise OSError('state write failure')
            return original_replace(path, data)
        with patch.object(installer, 'replace_file', side_effect=fail_state):
            with self.assertRaises(OSError):
                installer.install(copy, self.project, sys.executable)
        after = {str(p.relative_to(self.project)): p.read_bytes() for p in self.project.rglob('*') if p.is_file()}
        self.assertEqual(before, after)
        self.assertEqual(installer.install(copy, self.project, sys.executable)['version'], '0.12.1')
        self.assertIn('Versioned guidance.', (self.project / '.agents/skills/circlr-studio/references/roles/producer.md').read_text())


if __name__ == '__main__':
    unittest.main()
