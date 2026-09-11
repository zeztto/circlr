#!/usr/bin/env python3
"""Verify the captured build 50 group gestures and exact local QA package."""
import copy
import hashlib
import json
from pathlib import Path
import plistlib
import runpy
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'qa/generated/midi-group-drag'
FINAL = OUT / 'final'
CASES = {'prepared': 24, 'piano-move': 25, 'piano-resize': 26, 'piano-boundary': 29,
         'piano-noop': 30, 'orbit-move': 31, 'orbit-resize': 32,
         'orbit-keyboard-length': 35, 'single-move': 38, 'restored': 41, 'reopened': 41}
KEYS = ['name', 'global', 'tracks', 'sections', 'arrangements', 'assets', 'patterns', 'signal', 'portLayout', 'circleLayout']
LANE = '055F3787-2B9D-4DD1-9752-56106F8D94F5'


def normalized(project, key):
    value = copy.deepcopy(project.get(key))
    if key == 'portLayout' and value is not None:
        value.pop('revision', None)
    return value


def notes(project):
    return next(l['notes'] for l in project['arrangements'][0]['uses'][0]['addedLanes'] if l['id'] == LANE)


def ax(name):
    return (FINAL / (name + '.ax.txt')).read_text()


if __name__ == '__main__':
    captures = {name: json.loads((FINAL / (name + '.json')).read_text()) for name in CASES}
    initial = json.loads((OUT / 'baseline.json').read_text())['manifest']
    baseline = captures['prepared']['manifest']
    selected = set(captures['prepared']['state']['selectedNoteIDs'])
    assert len(selected) == 3 and len(notes(baseline)) == 4
    for name, revision in CASES.items():
        state = captures[name]['state']; project = captures[name]['manifest']
        assert state['projectID'] == 'A7944C14-2ED3-5278-8FBD-99A6BD043A3B' and state['revision'] == revision
        assert state['runtime']['bundleID'] == 'com.circlr.integrationqa' and not state['dirty']
        assert state['output']['attempts'] == state['audition']['attempts'] == 0
        assert not state['recording']['busy'] and not state['recording']['midi'] and not state['playback']['playing']
        expected = copy.deepcopy(initial if name in ['restored', 'reopened'] else baseline)
        if name.startswith('orbit-'):
            expected['circleLayout'] = 'orbit'
        time = {'piano-move': 1, 'piano-resize': 1, 'orbit-move': .5, 'orbit-resize': .5}.get(name, 0)
        length = .25 if name in ['piano-resize', 'orbit-resize', 'orbit-keyboard-length'] else 0
        pitch = 2 if time else 0
        for note in notes(expected):
            if note['id'] in selected:
                if name == 'piano-boundary':
                    note['beat'] -= .13
                else:
                    note['beat'] += time
                note['pitch'] += pitch; note['length'] += length
            elif name == 'single-move':
                note['beat'] += 1; note['pitch'] += 1
        for key in KEYS:
            assert normalized(project, key) == normalized(expected, key), (name, key)
        if name not in ['single-move', 'restored', 'reopened']:
            assert set(state['selectedNoteIDs']) == selected, name
        if name == 'single-move':
            assert set(state['selectedNoteIDs']) == {n['id'] for n in notes(baseline)} - selected
        if name not in ['restored', 'reopened']:
            assert state['view']['zoom'] == captures['prepared']['state']['view']['zoom']
    for name, revision in {'piano-resize-undo': 27, 'piano-move-undo': 28,
            'piano-boundary-undo': 30, 'piano-noop': 30, 'orbit-resize-undo': 33,
            'orbit-move-undo': 34, 'orbit-minimum-noop': 34,
            'orbit-keyboard-undo': 36, 'layout-undo': 37, 'single-undo': 39}.items():
        assert f'MCP 연결 가능 r{revision}\n' in ax(name), name
    assert 'E4 · 1박 · 길이 0.75박' in ax('piano-boundary')
    assert '99999999' not in ax('piano-boundary')
    assert 'G4 · 2.13박 · 길이 0.25박' in ax('orbit-minimum-noop')
    assert 'A4 ·' not in ax('orbit-move') and '3개 선택' in ax('orbit-move')
    assert '피아노 롤' in ax('layout-undo') and '1개 선택' in ax('single-move')
    for name in ['prepared', 'orbit-prepared']:
        assert '선택 노트를 함께 드래그\n끝 손잡이로 길이 조절' in ax(name)
    source = Path.home() / 'Library/Application Support/circlr-integration-qa/fixtures/studio.circlr'
    assert hashlib.sha256((source / 'manifest.json').read_bytes()).hexdigest() == '12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d'
    for asset in initial['assets']:
        for folder in [source, source.with_name('midi-group-drag.circlr')]:
            assert hashlib.sha256((folder / asset['path']).read_bytes()).hexdigest() == asset['checksum']
    app = FINAL / '써클러 통합 검증.app'
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    assert (info['CFBundleVersion'], info['CFBundleShortVersionString'], info['CFBundleIdentifier']) == ('50', '0.20.0', 'com.circlr.integrationqa')
    sections = runpy.run_path(str(ROOT / 'qa/check-library-evidence.py'))['sections']
    compiled = sections(ROOT / '.build/integration-release/release/circlr')
    assert len(compiled) == 37 and compiled == sections(app / 'Contents/MacOS/circlr')
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    hashes = json.loads((FINAL / 'source-hashes.json').read_text()); assert len(hashes) == 10
    for name, digest in hashes.items():
        assert hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == digest
    kit = app / 'Contents/Resources/Codex'; files = json.loads((kit / 'manifest.json').read_text())['files']
    assert len(files) == 25
    for name, digest in files.items():
        assert hashlib.sha256((kit / name).read_bytes()).hexdigest() == digest
    assert 'Executed 382 tests, with 0 failures' in (ROOT / '.build/midi-group-drag-tests.log').read_text()
    assert 'Ran 26 tests' in (ROOT / '.build/midi-group-drag-python.log').read_text()
    preserve = json.loads((FINAL / 'preservation.json').read_text())
    assert preserve['ownedQAProcesses'] == [] and preserve['userApp'] == ['0.19.0', '21']
    assert set(preserve['heads'].values()) == {'d88ea5d8d5d87cf49c5ef06154397c36ba1019d7', '1d304eb244f60a21c3598b89d05192d3512d719d'}
    result = dict(status='passed', revision=41, finalNativeSnapshots=len(captures),
                  finalAXCaptures=len(list(FINAL.glob('*.ax.txt'))), sourceFiles=len(hashes),
                  kitFiles=25, executableSections=37, physicalAudioAttempts=0,
                  midGestureExternalChanges='source_review_only', voiceOverSpeech='not_verified',
                  screenshots={p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(FINAL.glob('*.jpg'))})
    (FINAL / 'verification.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({k: v for k, v in result.items() if k != 'screenshots'}, ensure_ascii=False))
