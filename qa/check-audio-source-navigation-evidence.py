#!/usr/bin/env python3
"""Verify the captured build 49 audio navigation and its exact local QA package."""
import copy
import hashlib
import json
from pathlib import Path
import plistlib
import re
import runpy
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'qa/generated/audio-source-navigation'
FINAL = OUT / 'readable'
CASES = {'readable-baseline': 18, 'readable-trimmed': 20, 'readable-keyboard-trim': 21,
         'readable-navigation': 23, 'readable-drag': 24, 'readable-restored': 27,
         'readable-other-use': 27, 'restored': 27, 'reopened': 27}
KEYS = ['name', 'global', 'tracks', 'sections', 'arrangements', 'assets', 'patterns', 'signal', 'portLayout', 'circleLayout']
LANE = '7F32786A-C5A8-5B33-BEA3-0D5D029F3C14'


def normalized(project, key):
    value = copy.deepcopy(project.get(key))
    if key == 'portLayout' and value is not None:
        value.pop('revision', None)
    return value


def ax(name):
    return (FINAL / (name + '.ax.txt')).read_text()


def times(name):
    return tuple(map(float, re.search(r'원본 표시 ([\d.]+)부터 ([\d.]+)초 · 선택 ([\d.]+)부터 ([\d.]+)초 · 분할 ([\d.]+)초', ax(name)).groups()))


if __name__ == '__main__':
    captures = {name: json.loads((OUT / (name + '.json')).read_text()) for name in CASES}
    initial = json.loads((OUT / 'baseline.json').read_text())['manifest']
    baseline = captures['readable-baseline']['manifest']
    for name, revision in CASES.items():
        state = captures[name]['state']; project = captures[name]['manifest']
        assert state['projectID'] == '541EA22B-D5A7-56B2-AA80-C7341F4A463E' and state['revision'] == revision
        assert state['runtime']['bundleID'] == 'com.circlr.integrationqa' and not state['dirty']
        assert state['output']['attempts'] == state['audition']['attempts'] == 0
        assert not state['recording']['busy'] and not state['recording']['midi'] and not state['playback']['playing']
        expected = copy.deepcopy(initial if name in ['restored', 'reopened'] else baseline)
        if name in ['readable-trimmed', 'readable-keyboard-trim', 'readable-navigation', 'readable-drag']:
            lane = copy.deepcopy(next(l for l in baseline['sections'][0]['lanes'] if l['id'] == LANE))
            start = {'readable-keyboard-trim': 8.01, 'readable-drag': 8.511421990645559}.get(name, 8)
            lane['audio'][0]['sourceStart'] = start; lane['audio'][0]['duration'] = 16 - start
            expected['arrangements'][0]['uses'][0]['laneOverrides'][LANE] = lane
        if name == 'readable-other-use':
            expected['arrangements'][0]['uses'][1]['graphEdits']['layout']['groups'][0]['collapsed'] = False
        for key in KEYS:
            assert normalized(project, key) == normalized(expected, key), (name, key)
        if name not in ['restored', 'reopened']:
            assert state['view']['zoom'] == captures['readable-baseline']['state']['view']['zoom']
    expected_ranges = {'initial': (0, 32), 'wheel-down': (0, 32), 'zoom': (12, 20),
        'page-next': (16, 24), 'end': (24, 32), 'home': (0, 8),
        'reveal-button': (12, 20), 'reveal-key': (12, 20), 'page-previous': (8, 16),
        'fit': (7.36, 16.64), 'trim-pan': (11, 15.64), 'trim-reveal': (7.68, 12.32),
        'cursor-hidden': (7.68, 12.32), 'keyboard-trim': (12.68, 17.32),
        'trim-undo': (12.68, 17.32), 'orbit-preserved': (12.68, 17.32),
        'trim-drag': (7.36, 16.64), 'drag-undo': (7.36, 16.64),
        'end-undo': (7.36, 16.64), 'start-undo': (7.36, 16.64),
        'other-use': (0, 32), 'other-use-zoom': (8, 24), 'first-use-return': (0, 32),
        'original-scope': (0, 32), 'local-scope': (0, 32)}
    for name, expected in expected_ranges.items():
        assert times(name)[:2] == expected, (name, times(name))
    assert abs(times('wheel-up')[1] - times('wheel-up')[0] - 16) < .002
    assert abs(times('orbit-wheel')[1] - times('orbit-wheel')[0] - 2.32) < .002
    assert abs(times('minimum-zoom')[1] - times('minimum-zoom')[0] - .01) < .0001
    assert '오디오 궤도 편집기' in ax('minimum-zoom') and '오디오 파형 편집기' in ax('layout-undo')
    for name in ['draft-keys', 'draft-wheel']:
        assert re.search(r'The focused UI element is \d+ text field .*오디오 볼륨 dB.*Value: -6ㄹ', ax(name))
    assert times('draft-keys')[:2] == times('minimum-zoom')[:2]
    assert 'button Description: 커서 보기' in ax('cursor-hidden')
    assert times('keyboard-trim')[2:] == (8.01, 16, 6.99)
    assert times('trim-undo')[2:4] == times('drag-undo')[2:4] == (8, 16)
    assert times('start-undo')[2:4] == (0, 32)
    source = Path.home() / 'Library/Application Support/circlr-integration-qa/fixtures/studio.circlr'
    assert hashlib.sha256((source / 'manifest.json').read_bytes()).hexdigest() == '12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d'
    for asset in initial['assets']:
        for folder in [source, source.with_name('audio-source-navigation.circlr')]:
            assert hashlib.sha256((folder / asset['path']).read_bytes()).hexdigest() == asset['checksum']
    app = FINAL / '써클러 통합 검증.app'
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    assert (info['CFBundleVersion'], info['CFBundleShortVersionString'], info['CFBundleIdentifier']) == ('49', '0.20.0', 'com.circlr.integrationqa')
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
    assert 'Executed 377 tests, with 0 failures' in (ROOT / '.build/audio-source-navigation-tests.log').read_text()
    assert 'Ran 26 tests' in (ROOT / '.build/audio-source-navigation-python.log').read_text()
    preserve = json.loads((FINAL / 'preservation.json').read_text())
    assert preserve['ownedQAProcesses'] == [] and preserve['userApp'] == ['0.19.0', '21']
    shots = sorted(FINAL.glob('*.jpg'))
    result = dict(status='passed', revision=27, finalNativeSnapshots=len(captures), finalAXCaptures=len(list(FINAL.glob('*.ax.txt'))),
                  sourceFiles=len(hashes), kitFiles=25, executableSections=37, physicalAudioAttempts=0,
                  shiftWheel='source_review_only', voiceOverSpeech='not_verified',
                  screenshots={p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in shots})
    (FINAL / 'verification.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(result, ensure_ascii=False))
