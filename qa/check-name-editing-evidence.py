#!/usr/bin/env python3
"""Check name drafts, native commit/Undo/save evidence, restoration, and build 45."""
import copy
import hashlib
import json
from pathlib import Path
import plistlib
import runpy
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'qa/generated/name-editing'
FINAL = OUT / 'guard'
PROJECT_ID = '17463B94-AEE0-561D-9498-911B1C04D649'
INSTRUMENT = 'instrument:7E0D9016-E91D-4325-B807-033F233E32EA'
GROUP = '5B2E59F8-3337-5ABA-A844-4DCD09A2FFB6'
UNICODE = '여름밤 · 真夜中 / f0r h3r 🎹'
REVISIONS = {'final-before': 16, 'final-draft': 16, 'final-committed': 17,
             'final-unicode-draft': 18, 'final-unicode-saved': 19,
             'final-empty-save-blocked': 19, 'final-tab': 20, 'final-blur': 22,
             'final-conflict-rejected': 24, 'final-target-switched': 25,
             'final-group-committed': 25, 'final-group-undone': 26,
             'final-sound-readonly': 26, 'final-unicode-reopened': 26,
             'final-restored': 27, 'final-reopened': 27, 'guard-before': 27,
             'guard-draft': 27, 'guard-saved': 28, 'guard-restored': 29, 'guard-reopened': 29}
KEYS = ['name', 'global', 'tracks', 'sections', 'arrangements', 'assets', 'patterns', 'signal', 'portLayout', 'circleLayout']


def load(name):
    return json.loads((OUT / (name + '.json')).read_text())


def ax(name):
    return (OUT / (name + '-ax.txt')).read_text()


def node(project):
    return next(n for n in project['arrangements'][0]['uses'][0]['graphEdits']['addedNodes'] if n['id'] == INSTRUMENT)


def group(project):
    return next(g for g in project['arrangements'][0]['uses'][0]['graphEdits']['layout']['groups'] if g['id'] == GROUP)


def normalized(project, key):
    value = copy.deepcopy(project.get(key))
    if key == 'portLayout' and value is not None:
        value.pop('revision', None)
    return value


if __name__ == '__main__':
    before = load('before')['manifest']
    captures = {name: load(name) for name in REVISIONS}
    names = {name: '통합 키보드' for name in REVISIONS}
    names.update({'final-committed': 'Midnight Keyboard 45', 'final-tab': 'Tab commit',
                  'final-blur': 'Blur commit', 'final-conflict-rejected': 'Agent title'})
    for name in ['final-unicode-saved', 'final-target-switched', 'final-group-committed',
                 'final-group-undone', 'final-sound-readonly', 'final-unicode-reopened', 'guard-saved']:
        names[name] = UNICODE
    for name, value in captures.items():
        s = value['state']
        assert s['projectID'] == PROJECT_ID and s['revision'] == REVISIONS[name] and not s['dirty'], name
        assert s['runtime']['bundleID'] == 'com.circlr.integrationqa' and s['runtime']['version'] == '0.20.0'
        assert s['output']['attempts'] == s['audition']['attempts'] == 0
        assert not s['recording']['busy'] and not s['recording']['midi'] and not s['playback']['playing']
        if 'manifest' not in value:
            assert name == 'final-empty-save-blocked'
            continue
        project = copy.deepcopy(value['manifest'])
        assert node(project)['name'] == names[name], name
        assert group(project)['name'] == ('Routing Group' if name == 'final-group-committed' else '신스 그룹'), name
        node(project)['name'] = node(before)['name']
        group(project)['name'] = group(before)['name']
        for key in KEYS:
            assert normalized(project, key) == normalized(before, key), (name, key)
    assert 'Value: Midnight Keyboard 45' in ax('final-draft') and 'r16' in ax('final-draft')
    assert 'Value: 통합 키보드' in ax('final-undone') and 'r18' in ax('final-undone')
    for name in ['final-committed', 'final-cancelled', 'final-conflict-cancelled', 'guard-restored']:
        assert 'The focused UI element is 25 container 앨범 서클 캔버스' in ax(name), name
    for name in ['final-unicode-saved', 'final-cancelled', 'final-unicode-reopened', 'guard-saved']:
        assert 'Value: ' + UNICODE in ax(name), name
    for name in ['final-empty-save-blocked', 'guard-invalid-saveas']:
        assert 'Description: 서클 이름, Help: 이름을 입력하세요' in ax(name)
    assert 'Value: Local draft' in ax('final-conflict-rejected') and '편집 대상이나 이름이 변경되었습니다.' in ax('final-conflict-rejected')
    assert 'Value: Agent title' in ax('final-conflict-cancelled')
    assert 'Value: 통합 키보드 출력' in ax('final-target-switched')
    assert 'Value: Routing Group' in ax('final-group-committed')
    assert 'Value: 신스 그룹' in ax('final-group-undone')
    assert 'text 앨범 사운드' in ax('final-sound-readonly') and 'Description: 서클 이름,' not in ax('final-sound-readonly')

    source = Path.home() / 'Library/Application Support/circlr-integration-qa/fixtures/studio.circlr'
    assert hashlib.sha256((source / 'manifest.json').read_bytes()).hexdigest() == '12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d'
    for asset in before['assets']:
        for folder in [source, source.with_name('name-editing.circlr')]:
            assert hashlib.sha256((folder / asset['path']).read_bytes()).hexdigest() == asset['checksum']
    app = FINAL / '써클러 통합 검증.app'
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    assert (info['CFBundleVersion'], info['CFBundleShortVersionString'], info['CFBundleIdentifier']) == ('45', '0.20.0', 'com.circlr.integrationqa')
    sections = runpy.run_path(str(ROOT / 'qa/check-library-evidence.py'))['sections']
    compiled = sections(ROOT / '.build/integration-release/release/circlr')
    assert len(compiled) == 37 and compiled == sections(app / 'Contents/MacOS/circlr')
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    hashes = json.loads((FINAL / 'source-hashes.json').read_text()); assert len(hashes) == 9
    for name, digest in hashes.items():
        assert hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == digest
    previous = json.loads((OUT / 'save/source-hashes.json').read_text())
    assert {name for name in hashes if hashes[name] != previous[name]} == {'Sources/CirclrApp/CommittedNameField.swift'}
    kit = app / 'Contents/Resources/Codex'; manifest = json.loads((kit / 'manifest.json').read_text())
    assert len(manifest['files']) == 25
    for name, digest in manifest['files'].items():
        assert hashlib.sha256((kit / name).read_bytes()).hexdigest() == digest
    assert 'Executed 363 tests, with 0 failures' in (ROOT / '.build/name-editing-tests-guard.log').read_text()
    assert 'Ran 26 tests' in (ROOT / '.build/name-editing-python.log').read_text()
    shots = sorted(OUT.glob('final-*.jpg')) + sorted(OUT.glob('guard-*.jpg'))
    assert len(shots) == 8
    result = dict(status='passed', revision=29, nativeSnapshots=len(captures), sourceFiles=9,
                  kitFiles=25, executableSections=37, physicalAudioAttempts=0,
                  physicalIME='not_verified', recordingRejection='source_review_only',
                  screenshots={p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in shots})
    (FINAL / 'verification.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(result, ensure_ascii=False))
