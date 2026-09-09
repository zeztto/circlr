#!/usr/bin/env python3
"""Verify build 48 time navigation, musical edits, restoration, and native package."""
import copy
import hashlib
import json
from pathlib import Path
import plistlib
import re
import runpy
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'qa/generated/automation-time-navigation'
FINAL = OUT / 'ruler'
CASES = {'before': (14, 64), 'end': (15, 128), 'home': (15, 64), 'outside': (15, 96),
         'moved': (16, 96), 'revealed': (16, 192), 'stable': (17, 192), 'orbit': (17, 192),
         'reset': (17, 64), 'nudge': (18, 128), 'orbit-undo': (19, 128), 'ruler-end': (19, 128),
         'ruler-linear': (19, 128), 'other-use': (19, 64), 'original': (19, 64),
         'restored': (20, 64), 'reopened': (20, 64)}
ORBIT = {'orbit', 'reset', 'nudge', 'orbit-undo', 'ruler-end'}
KEYS = ['name', 'global', 'tracks', 'sections', 'arrangements', 'assets', 'patterns', 'signal', 'portLayout', 'circleLayout']


def node(project, use=0):
    return next(n for n in project['arrangements'][0]['uses'][use]['graphEdits']['addedNodes']
                if n['id'] == 'mix:7E0D9016-E91D-4325-B807-033F233E32EA')


def normalized(project, key):
    value = copy.deepcopy(project.get(key))
    if key == 'portLayout' and value is not None:
        value.pop('revision', None)
    return value


def ax(name):
    return (OUT / (name + '-ax.txt')).read_text()


def curve(name):
    return next(line for line in ax(name).splitlines() if 'container Description: 오토메이션 곡선' in line)


if __name__ == '__main__':
    captures = {name: json.loads((OUT / (name + '.json')).read_text()) for name in CASES}
    before = captures['before']['manifest']; initial = captures['end']['manifest']
    assert node(before).get('automation') is None
    points = node(initial)['automation'][0]['points']
    assert [(p['beat'], p['value'], p['shape']) for p in points] == [(0, .5, 'linear'), (16, 1, 'linear'), (96, .75, 'linear'), (128, .25, 'linear')]
    for name, value in captures.items():
        state = value['state']; project = value['manifest']; revision, extent = CASES[name]
        assert state['projectID'] == 'C2CC080C-039A-5FC0-955C-8016666AA633' and state['revision'] == revision
        assert state['runtime']['bundleID'] == 'com.circlr.integrationqa' and not state['dirty']
        assert state['output']['attempts'] == state['audition']['attempts'] == 0
        assert not state['recording']['busy'] and not state['recording']['midi'] and not state['playback']['playing']
        assert state['automationEditor']['displayBeats'] == extent
        assert state['view']['layout'] == ('orbit' if name in ORBIT else 'freeform')
        assert state['automationEditor']['visible'] == (name not in ['before', 'reopened'])
        expected = copy.deepcopy(before if name in ['before', 'restored', 'reopened'] else initial)
        if name in ORBIT:
            expected['circleLayout'] = 'orbit'
        if name in ['moved', 'revealed', 'nudge']:
            edited = node(expected)['automation'][0]['points']
            original, target = (128, 127.75) if name == 'nudge' else (96, 192)
            next(p for p in edited if p['beat'] == original)['beat'] = target
            edited.sort(key=lambda p: p['beat'])
        for key in KEYS:
            assert normalized(project, key) == normalized(expected, key), (name, key)
        assert node(project, use=1).get('automation') is None
    for name, extent in [('final-base', 64), ('home', 64), ('inside', 64), ('outside', 96),
                         ('moved', 96), ('revealed', 192), ('undone', 192), ('stable-home', 192),
                         ('orbit-settled', 192), ('reset', 64), ('orbit-end', 128), ('nudge', 128),
                         ('ruler-end', 128), ('ruler-linear', 128), ('other-use', 64)]:
        assert f'표시 범위 0–{extent:.2f}박' in curve(name), name
    assert '마디 눈금 1, 3, 5, 7, 9, 11, 13, 15' in curve('final-base')
    assert '마디 눈금 1, 5, 9, 13, 17, 21' in curve('outside')
    for name in ['ruler-end', 'ruler-linear']:
        assert '마디 눈금 1, 5, 9, 13, 17, 21, 25, 29' in curve(name)
    assert '33마디 · 1.00박 · 128.000박 · 64.00초' in curve('ruler-end')
    assert '25마디 · 1.00박 · 96.000박 · 48.00초' in curve('ruler-selected')
    assert '32마디 · 4.75박 · 127.750박 · 63.88초' in curve('nudge')
    assert 'Value: 선택 점 4/4' in ax('ruler-end') and 'Value: 선택 점 0/0' in ax('other-use')
    assert 'button Description: 선택 오토메이션 점 보기' in ax('moved')
    assert 'button Description: 선택 오토메이션 점 보기' not in ax('revealed')
    assert 'button (disabled) Description: 다음 오토메이션 점' in ax('other-use')
    assert 'button (disabled) 점 추가' in ax('original') and '이번 사용에 추가된 서클입니다' in ax('original')
    assert 'checkbox Description: 공유 원본 편집, Value: 0' in ax('original-back')
    for name in ['home', 'outside', 'moved', 'revealed', 'undone', 'ruler-end', 'ruler-selected']:
        assert re.search(r'The focused UI element is \d+ container Description: 오토메이션 곡선', ax(name))
    source = Path.home() / 'Library/Application Support/circlr-integration-qa/fixtures/studio.circlr'
    assert hashlib.sha256((source / 'manifest.json').read_bytes()).hexdigest() == '12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d'
    for asset in before['assets']:
        for folder in [source, source.with_name('automation-time-navigation.circlr')]:
            assert hashlib.sha256((folder / asset['path']).read_bytes()).hexdigest() == asset['checksum']
    app = FINAL / '써클러 통합 검증.app'
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    assert (info['CFBundleVersion'], info['CFBundleShortVersionString'], info['CFBundleIdentifier']) == ('48', '0.20.0', 'com.circlr.integrationqa')
    sections = runpy.run_path(str(ROOT / 'qa/check-library-evidence.py'))['sections']
    compiled = sections(ROOT / '.build/integration-release/release/circlr')
    assert len(compiled) == 37 and compiled == sections(app / 'Contents/MacOS/circlr')
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    hashes = json.loads((FINAL / 'source-hashes.json').read_text()); assert len(hashes) == 5
    for name, digest in hashes.items():
        assert hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == digest
    previous = json.loads((OUT / 'final/source-hashes.json').read_text())
    assert {name for name in hashes if hashes[name] != previous[name]} == {'Sources/CirclrApp/AutomationEditor.swift'}
    kit = app / 'Contents/Resources/Codex'; manifest = json.loads((kit / 'manifest.json').read_text())
    assert len(manifest['files']) == 25
    for name, digest in manifest['files'].items():
        assert hashlib.sha256((kit / name).read_bytes()).hexdigest() == digest
    assert 'Executed 374 tests, with 0 failures' in (ROOT / '.build/automation-time-navigation-tests-clean.log').read_text()
    assert 'exited with unexpected signal code 11' in (ROOT / '.build/automation-time-navigation-tests.log').read_text()
    assert 'Ran 26 tests' in (ROOT / '.build/automation-time-navigation-python.log').read_text()
    preserve = json.loads((FINAL / 'preservation.json').read_text())
    assert preserve['ownedQAProcesses'] == [] and preserve['userApp'] == ['0.19.0', '21']
    shots = sorted(OUT.glob('*.jpg')); assert len(shots) == 6
    result = dict(status='passed', revision=20, nativeSnapshots=len(captures), sourceFiles=5,
                  kitFiles=25, executableSections=37, physicalAudioAttempts=0,
                  incrementalTestCrash='clean_build_passed_cause_not_proven',
                  voiceOverSpeech='not_verified', retainedStaleAXAction='source_review_only',
                  screenshots={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in shots})
    (FINAL / 'verification.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(result, ensure_ascii=False))
