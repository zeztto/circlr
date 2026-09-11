#!/usr/bin/env python3
"""Package only the isolated integration app and copy the authored port fixture once."""
from pathlib import Path
import hashlib
import json
import plistlib
import shutil
import subprocess
import uuid

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'qa/generated/integration'
APP = OUT / '써클러 통합 검증.app'
SOURCE = Path.home() / 'Library/Application Support/circlr-ports-qa/fixtures/ports-group.circlr'
FIXTURE = Path.home() / 'Library/Application Support/circlr-integration-qa/fixtures/studio.circlr'


def main():
    assert not APP.exists() and not FIXTURE.exists(), 'Preserve existing QA app and fixture'
    source_bytes = (SOURCE / 'manifest.json').read_bytes()
    project = json.loads(source_bytes)
    assert project['id'] == 'BF831627-C7A8-5D65-B8EA-433DC8B0B9FF'
    assert len(project['assets']) == 2 and all(a['name'].startswith('검증 톤 ') for a in project['assets'])
    for asset in project['assets']:
        path = Path(asset['path'])
        assert not path.is_absolute() and '..' not in path.parts and (SOURCE / path).is_file()
    binary = ROOT / '.build/integration-release/release/circlr'
    assert binary.is_file()
    OUT.mkdir(parents=True, exist_ok=True)
    (APP / 'Contents/MacOS').mkdir(parents=True)
    resources = APP / 'Contents/Resources'
    resources.mkdir()
    shutil.copy2(binary, APP / 'Contents/MacOS/circlr')
    info = plistlib.loads((ROOT / 'Resources/Info.plist').read_bytes())
    info.update(CFBundleIdentifier='com.circlr.integrationqa', CFBundleDisplayName='써클러 통합 검증', CFBundleName='써클러 통합 검증')
    info.pop('CFBundleDocumentTypes', None)
    (APP / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
    for name in ['AppIcon.icns', 'Assets.car']:
        shutil.copy2(ROOT / 'Resources' / name, resources / name)
    shutil.copytree(ROOT / 'Resources/Codex', resources / 'Codex', ignore=shutil.ignore_patterns('__pycache__', '*.pyc'))
    manifest = json.loads((resources / 'Codex/manifest.json').read_text())
    assert manifest['version'] == info['CFBundleShortVersionString']
    for name, digest in manifest['files'].items():
        assert hashlib.sha256((resources / 'Codex' / name).read_bytes()).hexdigest() == digest
    assert (resources / 'Codex/skills/circlr-studio/scripts/mcp_server.py').read_bytes() == (ROOT / 'mcp/server.py').read_bytes()
    subprocess.run(['codesign', '--force', '--deep', '--sign', '-', str(APP)], check=True)
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(APP)], check=True)
    FIXTURE.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(SOURCE, FIXTURE)
    project.update(id=str(uuid.uuid5(uuid.NAMESPACE_URL, 'circlr-integration-qa/studio')).upper(), name='통합 편집 검증', musicRevision=1)
    project['portLayout']['revision'] = 0
    (FIXTURE / 'manifest.json').write_text(json.dumps(project, ensure_ascii=False, indent=2) + '\n')
    assert (SOURCE / 'manifest.json').read_bytes() == source_bytes
    result = {'app': str(APP), 'fixture': str(FIXTURE), 'projectID': project['id'],
              'version': info['CFBundleShortVersionString'], 'build': info['CFBundleVersion'],
              'sourceManifestSHA256': hashlib.sha256(source_bytes).hexdigest(), 'kitFiles': len(manifest['files']),
              'uuid': subprocess.check_output(['dwarfdump', '--uuid', str(APP / 'Contents/MacOS/circlr')], text=True).strip()}
    (OUT / 'package.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(result, ensure_ascii=False))


if __name__ == '__main__':
    main()
