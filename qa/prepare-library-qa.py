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
import struct
import uuid

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'qa/generated/library-editing'
APP = OUT / '써클러 통합 검증.app'
SOURCE = Path.home() / 'Library/Application Support/circlr-integration-qa/fixtures/studio.circlr'
FIXTURE = SOURCE.with_name('library-editing.circlr')



def prepare_samples(out, project):
    samples=out/'samples'
    if samples.exists():
        hashes=json.loads((out/'source-hashes.json').read_text())
        assert len(hashes)==6
        for name,digest in hashes.items():
            assert hashlib.sha256((samples/name).read_bytes()).hexdigest()==digest
        return
    samples.mkdir(parents=True)
    for index,asset in enumerate(project['assets']):
        name='Drums/검증 킥.wav' if index==0 else 'Textures/Nordic pad.wav'
        data=(SOURCE/asset['path']).read_bytes()
        assert hashlib.sha256(data).hexdigest()==asset['checksum']
        target=samples/name;target.parent.mkdir(exist_ok=True);target.write_bytes(data)
    (samples/'broken.wav').write_bytes(b'Invalid audio file for QA')
    body=bytes([0,0x90,60,96,0x83,0x60,0x80,60,0,0,0x90,64,96,0x83,0x60,0x80,64,0,0,0xff,0x2f,0])
    (samples/'Citypop keys.mid').write_bytes(b'MThd'+struct.pack('>IHHH',6,0,1,480)+b'MTrk'+struct.pack('>I',len(body))+body)
    (samples/'.hidden.wav').write_bytes(b'hidden fixture')
    (samples/'notes.txt').write_text('Authored QA sources only. No purchased samples.')
    hashes={str(path.relative_to(samples)):hashlib.sha256(path.read_bytes()).hexdigest() for path in samples.rglob('*') if path.is_file()}
    (out/'source-hashes.json').write_text(json.dumps(hashes,ensure_ascii=False,indent=2)+'\n')


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
        assert current['id'] == str(uuid.uuid5(uuid.NAMESPACE_URL, 'circlr-integration-qa/library-editing')).upper()
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
    assert info['CFBundleShortVersionString'] == '0.20.0' and info['CFBundleVersion'] == '31'
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
        project['id'] = str(uuid.uuid5(uuid.NAMESPACE_URL, 'circlr-integration-qa/library-editing')).upper()
        (FIXTURE / 'manifest.json').write_text(json.dumps(project, ensure_ascii=False, indent=2) + '\n')
    if not args.candidate: prepare_samples(OUT, project)
    assert (SOURCE / 'manifest.json').read_bytes() == raw
    project['id'] = str(uuid.uuid5(uuid.NAMESPACE_URL, 'circlr-integration-qa/library-editing')).upper()
    result = dict(app=str(APP), fixture=str(FIXTURE), projectID=project['id'], build='31',
                  sourceSHA256=hashlib.sha256(raw).hexdigest(),
                  uuid=subprocess.check_output(['dwarfdump', '--uuid', str(APP / 'Contents/MacOS/circlr')], text=True).strip())
    (OUT / 'package.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(result, ensure_ascii=False))


if __name__ == '__main__':
    main()
