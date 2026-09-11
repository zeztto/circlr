#!/usr/bin/env python3
"""Create an exclusive bounce-return QA copy or package prebuilt build122/123 binaries.

Reuses the five-helper deny package contract; never starts an app or audio device.
"""
import argparse
import importlib.util
import json
from pathlib import Path
import plistlib
import re
import shutil
import uuid

spec = importlib.util.spec_from_file_location('bounce_return_package', Path(__file__).with_name('prepare-step-target-qa.py'))
p = importlib.util.module_from_spec(spec)
spec.loader.exec_module(p)
p.OUT = p.ROOT / 'qa/generated/bounce-return'
p.SOURCE = p.ROOT / 'qa/generated/production-flow/current122/bounced.json'
p.FIXTURE = Path.home() / 'Library/Application Support/circlr-integration-qa/fixtures/bounce-return.circlr'
p.PROJECT_ID = str(uuid.uuid5(uuid.NAMESPACE_URL, 'circlr-integration-qa/bounce-return')).upper()
ROOT, OUT, SOURCE, FIXTURE, PROJECT_ID = p.ROOT, p.OUT, p.SOURCE, p.FIXTURE, p.PROJECT_ID
HELPERS, digest, run, exclusive, assets = p.HELPERS, p.digest, p.run, p.exclusive, p.assets


def seed():
    assert not OUT.exists() and not FIXTURE.exists(), 'Preserve earlier evidence'
    record = json.loads(SOURCE.read_text()); project = record['manifest']
    assert project['musicRevision'] == 22 and len(project['assets']) == 3
    source_fixture = Path.home() / 'Library/Application Support/circlr-integration-qa/fixtures/production-flow.circlr'
    archive = SOURCE.parent / 'bounced-asset.wav'
    assert digest(archive) == '9387feb5f7b38cb5a3569cf2d6bbca106f09646a953a6d84a440d9fea1aadb1e'
    original = json.loads(json.dumps(project))
    project.update(id=PROJECT_ID, name='바운스 원본 복귀 검증')
    assert dict(project, id=original['id'], name=original['name']) == original
    baseline = OUT / 'baseline'; baseline.mkdir(parents=True); FIXTURE.mkdir()
    for asset in project['assets']:
        path = Path(asset['path']); assert not path.is_absolute() and '..' not in path.parts
        source = archive if asset['id'] == '9C1F0FA8-CBC6-4940-B32E-6B975DBDB47E' else source_fixture / path
        assert digest(source) == asset['checksum']
        destination = FIXTURE / path; destination.parent.mkdir(parents=True, exist_ok=True)
        with destination.open('xb') as handle: handle.write(source.read_bytes())
    exclusive(FIXTURE / 'manifest.json', project)
    exclusive(baseline / 'fixture-initial.json', project)
    exclusive(baseline / 'scenario.json', dict(projectID=PROJECT_ID, fixture=str(FIXTURE), source=str(SOURCE),
        sourceSHA256=digest(SOURCE), initialRevision=22,
        arrangementID='95B906AF-5A06-43F0-BF79-8EDB26A8973F', useID='C958E497-716C-5DA2-B597-B55375AE2A90',
        nodeID='AEE0A3F7-7BB2-4EC7-8CEA-13F0634B87EE', outputNodeID='output:7E0D9016-E91D-4325-B807-033F233E32EA',
        assets=project['assets'], archivedAssetSHA256=digest(archive), physicalAudioAttempts=0,
        scope='Completed bounce snapshot plus exact archived PCM; identity/name only changed'))
    print(json.dumps(dict(fixture=str(FIXTURE), projectID=PROJECT_ID, revision=22)))

def package(candidate, binary_dir, info_path):
    directory = OUT / candidate
    assert not directory.exists(), 'Preserve previous candidate'
    before = (FIXTURE / 'manifest.json').read_bytes()
    assert json.loads(before)['id'] == PROJECT_ID
    for asset in json.loads(before)['assets']:
        assert digest(FIXTURE / asset['path']) == asset['checksum']
    source_before = digest(SOURCE)
    scenario = json.loads((OUT / 'baseline/scenario.json').read_text())
    assert source_before == scenario['sourceSHA256'], 'Authored source changed since seed'
    binary_dir = binary_dir.resolve()
    names = ['circlr'] + HELPERS
    hashes = {name: digest(binary_dir / name) for name in names}
    info = plistlib.loads(info_path.read_bytes())
    assert info['CFBundleVersion'] in ['122', '123'] and info['CFBundleShortVersionString'] == '0.20.0'
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
    assert digest(SOURCE) == source_before
    assert all(digest(binary_dir / name) == checksum for name, checksum in hashes.items())
    print(directory / 'package.json')


def conflict_seed():
    directory = OUT / 'conflict-baseline'
    fixture = FIXTURE.with_name('bounce-return-conflict.circlr')
    assert not directory.exists() and not fixture.exists()
    project = json.loads((OUT / 'baseline/fixture-initial.json').read_text())
    project.update(id=str(uuid.uuid5(uuid.NAMESPACE_URL, 'circlr-integration-qa/bounce-return-conflict')).upper(), name='바운스 원본 복귀 충돌 검증')
    scenario = json.loads((OUT / 'baseline/scenario.json').read_text())
    graph = project['arrangements'][0]['uses'][0]['graphEdits']
    node = next(n for n in graph['addedNodes'] if n['id'] == scenario['nodeID'])
    edge = node['bounce']['replacedInputs'][0]
    assert all(e['id'] != edge['id'] for e in graph['addedEdges'])
    graph['addedEdges'].append(dict(edge))
    directory.mkdir(); fixture.mkdir()
    for asset in project['assets']:
        path = Path(asset['path']); source = FIXTURE / path
        assert digest(source) == asset['checksum']
        target = fixture / path; target.parent.mkdir(parents=True, exist_ok=True)
        with target.open('xb') as handle: handle.write(source.read_bytes())
    exclusive(fixture / 'manifest.json', project)
    exclusive(directory / 'fixture-initial.json', project)
    scenario.update(projectID=project['id'], fixture=str(fixture), conflictAddedEdge=edge,
        scope='Main bounce seed plus exactly one saved mix-to-output edge; restore must reject changed inputs')
    exclusive(directory / 'scenario.json', scenario)
    print(json.dumps(dict(fixture=str(fixture), projectID=project['id'], revision=project['musicRevision'])))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--candidate'); parser.add_argument('--binary-dir', type=Path)
    parser.add_argument('--info-plist', type=Path)
    parser.add_argument('--conflict', action='store_true', help='Seed exclusive changed-output conflict copy after main seed')
    args = parser.parse_args()
    if args.conflict:
        assert args.candidate is None and args.binary_dir is None and args.info_plist is None
        conflict_seed()
    elif args.candidate:
        assert re.fullmatch('[a-z0-9-]{1,32}', args.candidate) and args.candidate != 'baseline'
        assert args.binary_dir is not None and args.info_plist is not None
        assert plistlib.loads(args.info_plist.read_bytes())['CFBundleVersion'] in ['122', '123']
        package(args.candidate, args.binary_dir, args.info_plist)
    else:
        assert args.binary_dir is None and args.info_plist is None
        seed()
