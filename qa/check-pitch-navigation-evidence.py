#!/usr/bin/env python3
"""Verify native pitch navigation, unchanged music, restoration, and build 46."""
import copy
import hashlib
import json
from pathlib import Path
import plistlib
import re
import runpy
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'qa/generated/pitch-navigation'
FINAL = OUT / 'pinned'
REVISIONS = {'before': 14, 'first-click': 15, 'first-keyboard': 15,
             'compact-before': 15, 'compact-click': 15, 'compact-keyboard': 15,
             'compact-selected': 15, 'compact-edited': 16, 'compact-next': 17,
             'compact-empty': 18, 'compact-other-use': 19,
             'pinned-selected': 19, 'pinned-next': 19, 'restored': 20, 'reopened': 20}
WINDOWS = {'compact-click': 50, 'compact-drag': 71, 'compact-semitone': 72,
           'compact-octave': 60, 'compact-low': 0, 'compact-high': 104,
           'compact-accessibility': 60, 'compact-selected': 60,
           'compact-one-octave': 72, 'compact-reveal': 66, 'compact-next': 24,
           'compact-empty': 24, 'compact-other-use': 63,
           'pinned-selected': 60, 'pinned-next': 24, 'pinned-fit': 63}
KEYS = ['name', 'global', 'tracks', 'sections', 'arrangements', 'assets', 'patterns', 'signal', 'portLayout', 'circleLayout']


def notes(project):
    return project['arrangements'][0]['uses'][0]['addedLanes'][0]['notes']


def normalized(project, key):
    value = copy.deepcopy(project.get(key))
    if key == 'portLayout' and value is not None:
        value.pop('revision', None)
    return value


def ax(name):
    return (OUT / (name+'-ax.txt')).read_text()


if __name__ == '__main__':
    captures = {name: json.loads((OUT / (name+'.json')).read_text()) for name in REVISIONS}
    before = captures['before']['manifest']; wide = captures['first-click']['manifest']
    assert len(notes(before)) == 3 and len(notes(wide)) == 17
    assert min(n['pitch'] for n in notes(wide)) == 0 and max(n['pitch'] for n in notes(wide)) == 127
    for name, value in captures.items():
        state = value['state']; project = value['manifest']
        assert state['projectID'] == '32E6C19C-BA3A-5769-8879-29A3D3C6F1F2' and state['revision'] == REVISIONS[name]
        assert state['runtime']['bundleID'] == 'com.circlr.integrationqa' and not state['dirty']
        assert state['output']['attempts'] == state['audition']['attempts'] == 0
        assert not state['recording']['busy'] and not state['recording']['midi'] and not state['playback']['playing']
        expected = copy.deepcopy(before if name in ['before','restored','reopened'] else wide)
        if name == 'compact-edited':
            next(n for n in notes(expected) if n['id'] == 'BA8C30C3-3F0E-482A-A108-7A9C829C96AE')['pitch'] = 67
        elif name == 'compact-empty':
            notes(expected).clear()
        for key in KEYS:
            assert normalized(project, key) == normalized(expected, key), (name, key)
    for name, low in WINDOWS.items():
        line = next(line for line in ax(name).splitlines() if 'slider (settable, integer) Description: MIDI 전체 음역 탐색,' in line)
        assert re.search(r'Value: '+str(low)+r',', line), (name, line)
    for name in ['compact-return', 'first-return']:
        assert re.search(r'The focused UI element is \d+ container Description: MIDI 궤도 편집기', ax(name))
    assert '표시 음 F♯4 · MIDI 66' in ax('compact-selected') and '표시 음 G4 · MIDI 67' in ax('compact-edited')
    assert '표시 음 F♯4 · MIDI 66' in ax('compact-undone')
    assert '12개 반음' in ax('compact-one-octave') and '24개 반음' in ax('compact-selected')
    assert '전체 연주 0개 음높이' in ax('compact-empty')
    assert 'button (disabled) Description: 다음 MIDI 노트,' in ax('compact-empty')
    assert '전체 연주 3개 음높이' in ax('compact-other-use')
    for name in ['pinned-selected', 'pinned-next']:
        text = ax(name)
        for item in ['radio button Description: 궤도,', 'button Description: 이전 MIDI 노트,', 'button Description: 다음 MIDI 노트,', 'button 바운스']:
            assert item in text, (name, item)
    source = Path.home() / 'Library/Application Support/circlr-integration-qa/fixtures/studio.circlr'
    assert hashlib.sha256((source / 'manifest.json').read_bytes()).hexdigest() == '12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d'
    for asset in before['assets']:
        for folder in [source, source.with_name('pitch-navigation.circlr')]:
            assert hashlib.sha256((folder / asset['path']).read_bytes()).hexdigest() == asset['checksum']
    app = FINAL / '써클러 통합 검증.app'
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    assert (info['CFBundleVersion'], info['CFBundleShortVersionString'], info['CFBundleIdentifier']) == ('46','0.20.0','com.circlr.integrationqa')
    sections = runpy.run_path(str(ROOT / 'qa/check-library-evidence.py'))['sections']
    compiled = sections(ROOT / '.build/integration-release/release/circlr')
    assert len(compiled) == 37 and compiled == sections(app / 'Contents/MacOS/circlr')
    subprocess.run(['codesign','--verify','--deep','--strict',str(app)], check=True)
    hashes = json.loads((FINAL / 'source-hashes.json').read_text()); assert len(hashes) == 5
    for name, digest in hashes.items():
        assert hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == digest
    previous = json.loads((OUT / 'compact/source-hashes.json').read_text())
    assert {name for name in hashes if hashes[name] != previous[name]} == {'Sources/CirclrApp/MIDIOrbitWorkspace.swift'}
    kit = app / 'Contents/Resources/Codex'; manifest = json.loads((kit / 'manifest.json').read_text())
    assert len(manifest['files']) == 25
    for name, digest in manifest['files'].items():
        assert hashlib.sha256((kit / name).read_bytes()).hexdigest() == digest
    assert 'Executed 366 tests, with 0 failures' in (ROOT / '.build/pitch-navigation-tests-final.log').read_text()
    shots = sorted(OUT.glob('*.jpg')); assert len(shots) == 8
    result = dict(status='passed', revision=20, nativeSnapshots=len(captures), sourceFiles=5,
                  kitFiles=25, executableSections=37, physicalAudioAttempts=0,
                  hoverOnly='not_verified', voiceOverSpeech='not_verified',
                  screenshots={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in shots})
    (FINAL / 'verification.json').write_text(json.dumps(result, ensure_ascii=False, indent=2)+'\n')
    print(json.dumps(result, ensure_ascii=False))
