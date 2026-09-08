#!/usr/bin/env python3
"""Package a versioned QA app and copy only the authored integration fixture's declared assets."""
from pathlib import Path
import argparse
import hashlib
import re
import json
import plistlib
import shutil
import subprocess
import uuid

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'qa/generated/import'
APP = OUT / '써클러 통합 검증.app'
SOURCE = Path.home() / 'Library/Application Support/circlr-integration-qa/fixtures/studio.circlr'
FIXTURE = SOURCE.with_name('import.circlr')


def main():
    global OUT, APP
    parser = argparse.ArgumentParser()
    parser.add_argument('--candidate')
    args = parser.parse_args()
    if args.candidate:
        assert re.fullmatch('[a-z0-9-]{1,32}', args.candidate)
        OUT = OUT / args.candidate
        APP = OUT / '써클러 통합 검증.app'
        current = json.loads((FIXTURE / 'manifest.json').read_text())
        assert current['id'] == str(uuid.uuid5(uuid.NAMESPACE_URL, 'circlr-integration-qa/import')).upper()
    assert not APP.exists(), 'Preserve previous QA app'
    assert args.candidate or not FIXTURE.exists(), 'Preserve previous QA project'
    raw = (SOURCE / 'manifest.json').read_bytes()
    project = json.loads(raw)
    assert project['id'] == 'B29AF867-91DE-55DB-9958-EC7EFCF0ADDF'
    assert len(project['tracks']) == 3 and len(project['assets']) == 2
    for asset in project['assets']:
        path = Path(asset['path'])
        assert asset['name'].startswith('검증 톤 ') and not path.is_absolute() and '..' not in path.parts
        assert (SOURCE / path).is_file()
        assert hashlib.sha256((SOURCE / path).read_bytes()).hexdigest() == asset['checksum']
    info = plistlib.loads((ROOT / 'Resources/Info.plist').read_bytes())
    assert info['CFBundleShortVersionString'] == '0.20.0' and info['CFBundleVersion'] == '26'
    info.update(CFBundleIdentifier='com.circlr.integrationqa', CFBundleDisplayName='써클러 통합 검증', CFBundleName='써클러 통합 검증')
    info.pop('CFBundleDocumentTypes', None)
    (APP / 'Contents/MacOS').mkdir(parents=True)
    shutil.copy2(ROOT / '.build/integration-release/release/circlr', APP / 'Contents/MacOS/circlr')
    (APP / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
    resources = APP / 'Contents/Resources'
    resources.mkdir()
    for name in ['AppIcon.icns', 'Assets.car']:
        shutil.copy2(ROOT / 'Resources' / name, resources / name)
    shutil.copytree(ROOT / 'Resources/Codex', resources / 'Codex', ignore=shutil.ignore_patterns('__pycache__', '*.pyc'))
    manifest = json.loads((resources / 'Codex/manifest.json').read_text())
    assert manifest['version'] == info['CFBundleShortVersionString']
    for name, digest in manifest['files'].items():
        assert hashlib.sha256((resources / 'Codex' / name).read_bytes()).hexdigest() == digest
    subprocess.run(['codesign', '--force', '--deep', '--sign', '-', str(APP)], check=True)
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(APP)], check=True)
    if not args.candidate:
        FIXTURE.mkdir()
        for asset in project['assets']:
            target = FIXTURE / asset['path']; target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(SOURCE / asset['path'], target)
        project['id'] = str(uuid.uuid5(uuid.NAMESPACE_URL, 'circlr-integration-qa/import')).upper()
        (FIXTURE / 'manifest.json').write_text(json.dumps(project, ensure_ascii=False, indent=2) + '\n')
    assert (SOURCE / 'manifest.json').read_bytes() == raw
    project['id'] = str(uuid.uuid5(uuid.NAMESPACE_URL, 'circlr-integration-qa/import')).upper()
    result = dict(app=str(APP), fixture=str(FIXTURE), projectID=project['id'], build='26',
                  sourceSHA256=hashlib.sha256(raw).hexdigest(),
                  uuid=subprocess.check_output(['dwarfdump', '--uuid', str(APP / 'Contents/MacOS/circlr')], text=True).strip())
    (OUT / 'package.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(result, ensure_ascii=False))


if __name__ == '__main__':
    main()
