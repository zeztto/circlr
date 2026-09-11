#!/usr/bin/env python3
"""Verify build 47 native row navigation, edit boundaries, restoration, and package."""
import copy
import hashlib
import json
from pathlib import Path
import plistlib
import re
import runpy
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'qa/generated/step-row-navigation'
FINAL = OUT / 'final'
REVISIONS = {'before': 14, 'wide': 15, 'row-selected': 15, 'added-row': 15,
             'toggled': 16, 'undone': 17, 'final-filter': 17, 'final-added': 17,
             'final-cell': 18, 'final-undo': 19, 'sample-search': 20,
             'other-use': 21, 'mouse-label': 21, 'restored': 22, 'reopened': 22}
KEYS = ['name', 'global', 'tracks', 'sections', 'arrangements', 'assets', 'patterns', 'signal', 'portLayout', 'circleLayout']
TRACK = '7E0D9016-E91D-4325-B807-033F233E32EA'


def notes(project):
    return project['arrangements'][0]['uses'][0]['addedLanes'][0]['notes']


def normalized(project, key):
    value = copy.deepcopy(project.get(key))
    if key == 'portLayout' and value is not None:
        value.pop('revision', None)
    return value


def ax(name):
    return (OUT / (name + '-ax.txt')).read_text()


def cursor(name, pitch, step, count):
    text = ax(name)
    line = next(x for x in text.splitlines() if 'container Description: 스텝 편집기' in x)
    assert re.search(r'Value: ' + str(pitch) + r' · .+ · ' + str(step) + r'스텝 · ' + str(count) + r'행', line), (name, line)


if __name__ == '__main__':
    captures = {name: json.loads((OUT / (name + '.json')).read_text()) for name in REVISIONS}
    before = captures['before']['manifest']; wide = captures['wide']['manifest']
    assert len(notes(before)) == 3 and len(notes(wide)) == 101
    assert sorted(n['pitch'] for n in notes(wide)) == list(range(101))
    for name, value in captures.items():
        state = value['state']; project = copy.deepcopy(value['manifest'])
        assert state['projectID'] == 'D5236346-59DA-5FC4-9B92-4BEE9020A424' and state['revision'] == REVISIONS[name]
        assert state['runtime']['bundleID'] == 'com.circlr.integrationqa' and not state['dirty']
        assert state['output']['attempts'] == state['audition']['attempts'] == 0
        assert not state['recording']['busy'] and not state['recording']['midi'] and not state['playback']['playing']
        expected = copy.deepcopy(before if name in ['before', 'restored', 'reopened'] else wide)
        if name in ['toggled', 'final-cell']:
            added = [n for n in notes(project) if n['pitch'] == 127]
            assert len(added) == 1 and len(notes(project)) == 102
            assert added[0]['beat'] == (0 if name == 'toggled' else .5)
            assert abs(added[0]['length'] - .225) < 1e-8 and added[0]['velocity'] == 96
            notes(project).remove(added[0])
        if name == 'sample-search':
            next(t for t in expected['tracks'] if t['id'] == TRACK)['instrument'] = {
                'kind': 'sampler', 'program': 0, 'drums': True, 'sample': {
                    'assetID': '69276595-4C4D-50C1-B3B6-820A8AA9196B', 'rootPitch': 126, 'oneShot': True,
                    'zones': [{'pitch': 126, 'assetID': '69276595-4C4D-50C1-B3B6-820A8AA9196B'},
                              {'pitch': 125, 'assetID': '898F2114-A0C2-5A02-A285-05C27F8791F5'}]}}
        for key in KEYS:
            assert normalized(project, key) == normalized(expected, key), (name, key)
    for name, pitch, step, count in [
        ('search-return', 96, 1, 1), ('row-selected', 96, 1, 1), ('empty-escape', 96, 1, 101),
        ('home', 0, 1, 101), ('page-down', 4, 1, 101), ('page-up', 0, 1, 101), ('end', 100, 1, 101),
        ('added-row', 127, 1, 102), ('final-mode', 100, 1, 101), ('final-filter', 1, 1, 9),
        ('final-column', 1, 3, 9), ('final-added', 127, 3, 102), ('final-cell', 127, 3, 102),
        ('final-undo', 127, 3, 102), ('sample-exact', 126, 3, 1), ('other-drum', 66, 1, 3),
        ('revealed', 66, 1, 3), ('mouse-label', 69, 1, 3)]:
        cursor(name, pitch, step, count)
    for name in ['wide', 'final-mode', 'final-filter', 'final-added']:
        headers = re.findall(r'button \d+ · .+ · 행 선택', ax(name))
        assert 1 <= len(headers) <= 6, (name, len(headers))
    assert 'button 100 · E7 · 행 선택' in ax('final-mode')
    assert 'button 1 · C♯-1 · 행 선택' in ax('final-filter')
    assert '일치하는 드럼 행이 없습니다' in ax('empty') and 'text 0/101행' in ax('empty')
    assert 'no-match' in ax('empty') and 'no-match' not in ax('empty-escape')
    assert 'button Description: 선택한 드럼 행 보기' in ax('hidden-selection')
    assert 'button Description: 선택한 드럼 행 보기' not in ax('revealed')
    assert '126 · 검증 톤 1 · 행 선택' in ax('sample-exact') and 'text 1/104행' in ax('sample-exact')
    assert 'text 3/3행' in ax('other-drum') and '127 · G9 · 행 선택' not in ax('other-drum')
    for name in ['other-drum', 'revealed']:
        line = next(x for x in ax(name).splitlines() if 'text field (settable) Description: 드럼 행 검색,' in x)
        assert 'Value:' not in line
    for name in ['search-return', 'empty-escape', 'final-added', 'revealed']:
        assert re.search(r'The focused UI element is \d+ container Description: 스텝 편집기', ax(name))
    source = Path.home() / 'Library/Application Support/circlr-integration-qa/fixtures/studio.circlr'
    assert hashlib.sha256((source / 'manifest.json').read_bytes()).hexdigest() == '12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d'
    for asset in before['assets']:
        for folder in [source, source.with_name('step-row-navigation.circlr')]:
            assert hashlib.sha256((folder / asset['path']).read_bytes()).hexdigest() == asset['checksum']
    app = FINAL / '써클러 통합 검증.app'
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    assert (info['CFBundleVersion'], info['CFBundleShortVersionString'], info['CFBundleIdentifier']) == ('47', '0.20.0', 'com.circlr.integrationqa')
    sections = runpy.run_path(str(ROOT / 'qa/check-library-evidence.py'))['sections']
    compiled = sections(ROOT / '.build/integration-release/release/circlr')
    assert len(compiled) == 37 and compiled == sections(app / 'Contents/MacOS/circlr')
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    hashes = json.loads((FINAL / 'source-hashes.json').read_text()); assert len(hashes) == 5
    for name, digest in hashes.items():
        assert hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == digest
    previous = json.loads((OUT / 'source-hashes.json').read_text())
    assert {name for name in hashes if hashes[name] != previous[name]} == {'Sources/CirclrApp/StepEditor.swift'}
    kit = app / 'Contents/Resources/Codex'; manifest = json.loads((kit / 'manifest.json').read_text())
    assert len(manifest['files']) == 25
    for name, digest in manifest['files'].items():
        assert hashlib.sha256((kit / name).read_bytes()).hexdigest() == digest
    assert 'Executed 369 tests, with 0 failures' in (ROOT / '.build/step-row-navigation-tests.log').read_text()
    assert 'Ran 26 tests' in (ROOT / '.build/step-row-navigation-python.log').read_text()
    preserve = json.loads((FINAL / 'preservation.json').read_text())
    assert preserve['ownedQAProcesses'] == [] and preserve['userApp'] == ['0.19.0', '21']
    shots = sorted(OUT.glob('*.jpg')); assert len(shots) == 7
    result = dict(status='passed', revision=22, nativeSnapshots=len(captures), sourceFiles=5,
                  kitFiles=25, executableSections=37, physicalAudioAttempts=0,
                  voiceOverSpeech='not_verified', retainedStaleAXAction='source_review_only',
                  screenshots={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in shots})
    (FINAL / 'verification.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(result, ensure_ascii=False))
