#!/usr/bin/env python3
"""Verify build 51's captured selection operations and exact local release package."""
import copy
import hashlib
import json
from pathlib import Path
import plistlib
import re
import runpy
import subprocess
import uuid

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'qa/generated/midi-selection-tools'
FINAL = OUT / 'readable'
LANE = '055F3787-2B9D-4DD1-9752-56106F8D94F5'
KEYS = ['name', 'global', 'tracks', 'sections', 'arrangements', 'assets', 'patterns', 'signal', 'portLayout', 'circleLayout']
CASES = {'piano-pitch': (15, ['seed', 'late']), 'piano-pitch-edited': (16, ['seed', 'late']),
         'piano-start': (17, ['seed', 'chord', 'rounding']), 'piano-invert': (17, ['near']),
         'step-pitch': (17, ['seed', 'late']), 'drum-start': (17, ['seed', 'chord', 'rounding', 'late']),
         'readable-piano-pitch': (17, ['seed', 'late']), 'readable-orbit-start': (17, ['seed', 'chord', 'rounding']),
         'readable-orbit-edit': (18, ['seed', 'chord', 'rounding']), 'readable-orbit-invert': (19, ['near', 'late']),
         'readable-other-use': (19, None), 'readable-restored': (21, []), 'readable-reopened': (21, [])}


def note_id(name):
    return str(uuid.uuid5(uuid.NAMESPACE_URL, 'circlr/midi-selection-tools/' + name)).upper()


def lane(project):
    return next(l for l in project['arrangements'][0]['uses'][0]['addedLanes'] if l['id'] == LANE)


def normalized(project, key):
    value = copy.deepcopy(project.get(key))
    if key == 'portLayout' and value is not None:
        value.pop('revision', None)
    return value


def ax(name, final=False):
    return ((FINAL if final else OUT) / (name + '.ax.txt')).read_text()


if __name__ == '__main__':
    initial = json.loads((OUT / 'baseline.json').read_text())['manifest']
    prepared = json.loads((OUT / 'prepared-notes.json').read_text())
    captures = {name: json.loads((OUT / (name + '.json')).read_text()) for name in CASES}
    for name, (revision, selection) in CASES.items():
        state = captures[name]['state']; project = captures[name]['manifest']
        assert state['projectID'] == 'CA931FD5-3110-547C-BBD0-1A2FF12FB35E' and state['revision'] == revision
        assert state['runtime']['bundleID'] == 'com.circlr.integrationqa' and not state['dirty']
        assert state['output']['attempts'] == state['audition']['attempts'] == 0
        assert not state['recording']['busy'] and not state['recording']['midi'] and not state['playback']['playing']
        expected = copy.deepcopy(initial)
        if name not in ['readable-restored', 'readable-reopened']:
            lane(expected)['notes'] = copy.deepcopy(prepared)
        if name.startswith('readable-orbit') or name == 'readable-other-use':
            expected['circleLayout'] = 'orbit'
        if name == 'piano-pitch-edited':
            for note in lane(expected)['notes']:
                if note['id'] in {note_id('seed'), note_id('late')}:
                    note['beat'] += .25
        if name == 'readable-orbit-edit':
            for note in lane(expected)['notes']:
                if note['id'] in {note_id(n) for n in ['seed', 'chord', 'rounding']}:
                    note['pitch'] += 1
        for key in KEYS:
            assert normalized(project, key) == normalized(expected, key), (name, key)
        ids = {note_id(n) for n in selection} if selection is not None else {n['id'] for n in lane(initial)['notes']}
        assert set(state['selectedNoteIDs']) == ids, name
    other = captures['readable-other-use']['state']['selection']['music']
    assert other['useID'] == 'D3976E37-6DB2-52AD-8130-780692B60DC3'
    assert 'MCP 연결 가능 r17' in ax('piano-clear') and 'MIDI 노트 선택 · 0개' in ax('piano-clear')
    assert 'MCP 연결 가능 r17' in ax('piano-edit-undo')
    assert 'MIDI 노트 선택 · 4개' in ax('piano-multi-pitch') and 'MIDI 노트 선택 · 5개' in ax('piano-all')
    assert re.search(r'The focused UI element is \d+ text field .*MIDI 세기.*Value: 81p', ax('text-draft'))
    assert '(disabled) 같은 음높이 선택' in ax('empty-menu')
    assert '(disabled) 같은 시작 박 선택' in ax('menu-after-scope', True)
    assert 'MIDI 노트 선택 · 5개' in ax('step-all', True) and 'MIDI 노트 선택 · 0개' in ax('step-clear', True)
    assert '표시 음 C4 · MIDI 60' in ax('orbit-start', True)
    assert 'MCP 연결 가능 r19' in ax('orbit-undo', True)
    assert 'The focused UI element is 68 container Description: MIDI 궤도' in ax('orbit-start', True)
    for shot in FINAL.glob('*.jpg'):
        assert len(re.findall(r'menu button Description: MIDI 노트 선택 ·', ax(shot.stem, True))) == 1, shot.name
    source = Path.home() / 'Library/Application Support/circlr-integration-qa/fixtures/studio.circlr'
    assert hashlib.sha256((source / 'manifest.json').read_bytes()).hexdigest() == '12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d'
    for asset in initial['assets']:
        for folder in [source, source.with_name('midi-selection-tools.circlr')]:
            assert hashlib.sha256((folder / asset['path']).read_bytes()).hexdigest() == asset['checksum']
    app = FINAL / '써클러 통합 검증.app'; info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    assert (info['CFBundleVersion'], info['CFBundleShortVersionString'], info['CFBundleIdentifier']) == ('51', '0.20.0', 'com.circlr.integrationqa')
    sections = runpy.run_path(str(ROOT / 'qa/check-library-evidence.py'))['sections']
    compiled = sections(ROOT / '.build/integration-release/release/circlr')
    assert len(compiled) == 37 and compiled == sections(app / 'Contents/MacOS/circlr')
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    hashes = json.loads((FINAL / 'source-hashes.json').read_text()); assert len(hashes) == 7
    for name, digest in hashes.items():
        assert hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == digest
    kit = app / 'Contents/Resources/Codex'; files = json.loads((kit / 'manifest.json').read_text())['files']
    assert len(files) == 25
    for name, digest in files.items():
        assert hashlib.sha256((kit / name).read_bytes()).hexdigest() == digest
    assert 'Executed 386 tests, with 0 failures' in (ROOT / '.build/midi-selection-tools-tests.log').read_text()
    assert 'Ran 26 tests' in (ROOT / '.build/midi-selection-tools-python.log').read_text()
    preserve = json.loads((FINAL / 'preservation.json').read_text())
    assert preserve['ownedQAProcesses'] == [] and preserve['userApp'] == ['0.19.0', '21']
    assert set(preserve['heads'].values()) == {'d88ea5d8d5d87cf49c5ef06154397c36ba1019d7', '1d304eb244f60a21c3598b89d05192d3512d719d'}
    result = dict(status='passed', revision=21, nativeSnapshots=len(captures),
                  finalNativeSnapshots=sum(name.startswith('readable-') for name in captures),
                  finalAXCaptures=len(list(FINAL.glob('*.ax.txt'))), sourceFiles=len(hashes),
                  kitFiles=25, executableSections=37, physicalAudioAttempts=0,
                  voiceOverSpeech='not_verified',
                  screenshots={p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(FINAL.glob('*.jpg'))})
    (FINAL / 'verification.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({k: v for k, v in result.items() if k != 'screenshots'}, ensure_ascii=False))
