#!/usr/bin/env python3
"""Create an exclusive authored console preferences fixture or package prebuilt UI-only QA binaries.

Seed: python3 qa/prepare-console-preferences-qa.py
Package: python3 qa/prepare-console-preferences-qa.py --candidate final120 --binary-dir PATH --info-plist PATH
Never launches the application or an audio helper.
"""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import uuid

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'qa/generated/console-preferences'
SOURCE = Path.home() / 'Library/Application Support/circlr-integration-qa/fixtures/studio.circlr'
FIXTURE = SOURCE.with_name('console-preferences.circlr')
PROJECT_ID = str(uuid.uuid5(uuid.NAMESPACE_URL, 'circlr-integration-qa/console-preferences')).upper()
NODE = 'instrument:7E0D9016-E91D-4325-B807-033F233E32EA'
HELPERS = ['circlr-output-worker', 'circlr-au-effect-worker', 'circlr-au-instrument-worker',
           'circlr-output-device-catalog', 'circlr-audition-worker']


# Reuse audited asset/file/process helpers without changing the synth QA namespace.
import importlib.util
_spec = importlib.util.spec_from_file_location('console_shared_helpers', Path(__file__).with_name('prepare-synth-workspace-qa.py'))
_shared = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_shared)
digest, exclusive, run, assets = _shared.digest, _shared.exclusive, _shared.run, _shared.assets


def seed():
    assert not OUT.exists() and not FIXTURE.exists(), 'Preserve previous evidence and fixture'
    raw = (SOURCE / 'manifest.json').read_bytes()
    project = json.loads(raw)
    assets(project, SOURCE)
    assert project['tracks'][0]['instrument']['synth']['engineVersion'] == 3
    original_tracks = json.loads(json.dumps(project['tracks']))
    arrangement = project['arrangements'][0]
    use = arrangement['uses'][0]
    node = next(n for n in use['graphEdits']['addedNodes'] if n['id'] == NODE)
    track_id = node['content']['instrument']['trackID']
    assert any(t['id'] == track_id for t in project['tracks'])
    project.update(id=PROJECT_ID, name='콘솔 설정 유지 검증')
    view = project['hierarchyView']
    view['selection'] = dict(music=dict(arrangementID=arrangement['id'], useID=use['id'], nodeID=NODE))
    view['settingsOpen'] = False
    view.pop('workspace', None); view.pop('editor', None)
    assert project['tracks'] == original_tracks
    baseline = OUT / 'baseline'
    baseline.mkdir(parents=True); FIXTURE.mkdir()
    for asset in project['assets']:
        destination = FIXTURE / asset['path']
        destination.parent.mkdir(parents=True, exist_ok=True)
        with destination.open('xb') as handle:
            handle.write((SOURCE / asset['path']).read_bytes())
    exclusive(FIXTURE / 'manifest.json', project)
    exclusive(baseline / 'fixture-initial.json', project)
    exclusive(baseline / 'scenario.json', dict(projectID=PROJECT_ID, fixture=str(FIXTURE), source=str(SOURCE),
        sourceSHA256=hashlib.sha256(raw).hexdigest(), initialRevision=project['musicRevision'],
        arrangementID=arrangement['id'], useID=use['id'], nodeID=NODE, trackID=track_id,
        assets=project['assets'], firstTrack=original_tracks[0], physicalAudioAttempts=0,
        scope='Authored studio copy; musical content and all tracks preserved; synth node selected'))
    assets(project, FIXTURE)
    assert (SOURCE / 'manifest.json').read_bytes() == raw
    print(json.dumps(dict(fixture=str(FIXTURE), projectID=PROJECT_ID, nodeID=NODE), ensure_ascii=False))


def package(candidate, binary_dir, info_path):
    directory = OUT / candidate
    assert not directory.exists(), 'Preserve previous candidate'
    before = (FIXTURE / 'manifest.json').read_bytes()
    assert json.loads(before)['id'] == PROJECT_ID
    assets(json.loads(before), FIXTURE)
    source_before = digest(SOURCE / 'manifest.json')
    scenario = json.loads((OUT / 'baseline/scenario.json').read_text())
    assert source_before == scenario['sourceSHA256'], 'Authored source changed since seed'
    binary_dir = binary_dir.resolve()
    names = ['circlr'] + HELPERS
    hashes = {name: digest(binary_dir / name) for name in names}
    info = plistlib.loads(info_path.read_bytes())
    assert info['CFBundleVersion'] in ['120'] and info['CFBundleShortVersionString'] == '0.20.0'
    source_uuid = run(['dwarfdump', '--uuid', str(binary_dir / 'circlr')]).split()[1]
    app = directory / '써클러 통합 검증.app'
    macos = app / 'Contents/MacOS'; macos.mkdir(parents=True)
    shutil.copy2(binary_dir / 'circlr', macos / 'circlr')
    assert digest(macos / 'circlr') == hashes['circlr']
    info.update(CFBundleIdentifier='com.circlr.integrationqa', CFBundleDisplayName='써클러 통합 검증', CFBundleName='써클러 통합 검증')
    info.pop('CFBundleDocumentTypes', None)
    (app / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
    resources = app / 'Contents/Resources'; resources.mkdir()
    for name in ['AppIcon.icns', 'Assets.car']:
        shutil.copy2(ROOT / 'Resources' / name, resources / name)
    shutil.copytree(ROOT / 'Resources/Codex', resources / 'Codex', ignore=shutil.ignore_patterns('__pycache__', '*.pyc'))
    manifest = json.loads((resources / 'Codex/manifest.json').read_text())
    assert manifest['version'] == info['CFBundleShortVersionString']
    for name, checksum in manifest['files'].items():
        assert digest(resources / 'Codex' / name) == checksum
    stub = directory / 'deny-audio.c'
    with stub.open('x') as handle:
        handle.write('int main(void){return 78;}\n')
    stub_binary = directory / 'deny-audio'
    run(['xcrun', 'clang', '-Os', str(stub), '-o', str(stub_binary)])
    # No production audio executable is installed in the QA bundle.
    for name in HELPERS:
        shutil.copy2(stub_binary, macos / name)
        run(['codesign', '--force', '--sign', '-', str(macos / name)])
    run(['codesign', '--force', '--deep', '--sign', '-', str(app)])
    run(['codesign', '--verify', '--deep', '--strict', str(app)])
    packaged_uuid = run(['dwarfdump', '--uuid', str(macos / 'circlr')]).split()[1]
    assert packaged_uuid == source_uuid
    packaged_helpers = {name: digest(macos / name) for name in HELPERS}
    assert all(packaged_helpers[name] != hashes[name] for name in HELPERS)
    exclusive(directory / 'qa-injection.json', dict(qaOnlyMock=True, candidate=candidate,
        denyAllAudioHelpers=True, helperExit=78, productionHelperSHA256={n: hashes[n] for n in HELPERS},
        packagedHelperSHA256=packaged_helpers, stubSourceSHA256=digest(stub),
        strictSignatureVerified=True, scope='All five helpers are authored exit78 C stubs; no native audio'))
    exclusive(directory / 'package.json', dict(app=str(app), fixture=str(FIXTURE), projectID=PROJECT_ID,
        build=info['CFBundleVersion'], sourceSHA256=source_before, sourceBinarySHA256=hashes,
        sourceBinaryUUID=source_uuid, packagedMainUUID=packaged_uuid, packagedMainSHA256=digest(macos / 'circlr'),
        binaryDirectory=str(binary_dir), infoSource=str(info_path.resolve()), codexManifestSHA256=digest(resources / 'Codex/manifest.json')))
    assert (FIXTURE / 'manifest.json').read_bytes() == before
    assert digest(SOURCE / 'manifest.json') == source_before
    assert all(digest(binary_dir / name) == checksum for name, checksum in hashes.items())
    print(directory / 'package.json')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--candidate'); parser.add_argument('--binary-dir', type=Path)
    parser.add_argument('--info-plist', type=Path)
    args = parser.parse_args()
    if args.candidate:
        assert re.fullmatch('[a-z0-9-]{1,32}', args.candidate) and args.candidate != 'baseline'
        assert args.binary_dir is not None and args.info_plist is not None, 'Explicit prebuilt binary and Info.plist required'
        package(args.candidate, args.binary_dir, args.info_plist)
    else:
        assert args.binary_dir is None and args.info_plist is None
        seed()
