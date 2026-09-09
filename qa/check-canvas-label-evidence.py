#!/usr/bin/env python3
"""Verify final native label geometry, edit restoration, and the exact build 44 package."""
import copy
import hashlib
import json
import math
from pathlib import Path
import plistlib
import runpy
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'qa/generated/canvas-labels'
FINAL = OUT / 'perimeter'
PROJECT_ID = '40C45549-C688-50BE-A1B8-2346E3D590EF'
REVISIONS = {'final-selected': 14, 'edge': 14, 'edge-editor': 14, 'long': 129, 'cable': 130,
             'cable-moved': 130, 'unbroken': 130, 'port': 130, 'orbit': 130,
             'orbit-selected': 130, 'time-handle': 130, 'time-moved': 131, 'restored': 133, 'reopened': 133}
KEYS = ['name', 'global', 'tracks', 'sections', 'arrangements', 'assets', 'patterns', 'signal', 'portLayout', 'circleLayout']


def capture(name, revision):
    value = json.loads((OUT / (name + '.json')).read_text())
    state = value['state']
    assert state['revision'] == revision and not state['dirty'], name
    assert state['projectID'] == PROJECT_ID and state['runtime']['bundleID'] == 'com.circlr.integrationqa'
    assert state['output']['attempts'] == state['audition']['attempts'] == 0
    assert not state['recording']['busy'] and not state['recording']['midi'] and not state['playback']['playing']
    return value


def intersects(a, b):
    return a[0] < b[0]+b[2] and a[0]+a[2] > b[0] and a[1] < b[1]+b[3] and a[1]+a[3] > b[1]


def contains(outer, inner):
    return outer[0]-1e-6 <= inner[0] and outer[1]-1e-6 <= inner[1] and inner[0]+inner[2] <= outer[0]+outer[2]+1e-6 and inner[1]+inner[3] <= outer[1]+outer[3]+1e-6


def normalized(project, key):
    value = copy.deepcopy(project.get(key))
    if key == 'portLayout' and value is not None:
        value.pop('revision', None)
    return value


def selected(state):
    return next(label for label in state['playback']['labels'] if label['selected'])


def music_node(project, prefix):
    return next(n for n in project['arrangements'][0]['uses'][0]['graphEdits']['addedNodes'] if n['id'].startswith(prefix))


if __name__ == '__main__':
    captures = {name: capture(name, revision) for name, revision in REVISIONS.items()}
    before = capture('before', 14)['manifest']
    for name in ['final-selected', 'edge', 'edge-editor', 'cable', 'unbroken', 'port', 'restored', 'reopened']:
        for key in KEYS:
            assert normalized(captures[name]['manifest'], key) == normalized(before, key), (name, key)
    for name, value in captures.items():
        state = value['state']; view = state['playback']; labels = view['labels']; ports = view['ports']
        assert view['canvasSize'] == [1024, 673]
        obstacles = [r for r in [view['editorFrame'], ports['toolsFrame'], ports['portToolsFrame']] if r]
        if ports['timeHandle']:
            x, y = ports['timeHandle']; obstacles.append([x-18, y-18, 36, 36])
        for index, label in enumerate(labels):
            rect = label['rect']
            assert contains(view['workspaceViewport'], rect), (name, 'viewport')
            for other in labels[index+1:]:
                assert not intersects(rect, other['rect']), (name, 'label collision')
            for obstacle in obstacles:
                assert not intersects(rect, obstacle), (name, 'control collision')
            for circle in view['labelCircles']:
                if circle['address'] != label['address']:
                    x, y = circle['center']; dx = x-max(rect[0], min(rect[0]+rect[2], x)); dy = y-max(rect[1], min(rect[1]+rect[3], y))
                    assert math.hypot(dx, dy) >= circle['radius']+4-1e-6, (name, 'circle collision')
            for handle in ports['handles']:
                x, y = handle['point']
                assert not contains([rect[0]-9, rect[1]-9, rect[2]+18, rect[3]+18], [x, y, 0, 0]), (name, 'port hit')
        if name not in ['edge-editor', 'cable-moved', 'restored']:
            label = selected(state)
            ax = (OUT / (name+'-ax.txt')).read_text()
            assert 'button (selected) '+label['title']+' ·' in ax, (name, 'AX title')
    edge = captures['edge']['state']; label = selected(edge)
    assert label['anchor'][0] < edge['playback']['workspaceViewport'][0] and label['rect'][2:] == [320, 66]
    assert captures['edge-editor']['state']['playback']['editorAddress'] == edge['selection']
    assert selected(captures['long']['state'])['rect'][2:] == [320, 84]
    assert selected(captures['unbroken']['state'])['rect'][2:] == [320, 84]
    assert len(music_node(captures['long']['manifest'], 'instrument:')['name']) > len(music_node(before, 'instrument:')['name'])
    assert captures['cable']['state']['layoutRevision'] == 4 and captures['cable-moved']['state']['layoutRevision'] == 5
    assert captures['cable-moved']['manifest']['portLayout'] != captures['cable']['manifest']['portLayout']
    assert captures['port']['state']['playback']['ports']['selectedPort'] is not None
    assert captures['orbit']['state']['view']['layout'] == 'orbit'
    assert captures['time-handle']['state']['playback']['ports']['timeHandle']
    assert music_node(captures['time-moved']['manifest'], 'midi:')['startBeat'] > music_node(before, 'midi:')['startBeat']
    source = Path.home() / 'Library/Application Support/circlr-integration-qa/fixtures/studio.circlr'
    assert hashlib.sha256((source / 'manifest.json').read_bytes()).hexdigest() == '12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d'
    for asset in before['assets']:
        for folder in [source, source.with_name('canvas-labels.circlr')]:
            assert hashlib.sha256((folder / asset['path']).read_bytes()).hexdigest() == asset['checksum']
    app = FINAL / '써클러 통합 검증.app'
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    assert (info['CFBundleVersion'], info['CFBundleShortVersionString'], info['CFBundleIdentifier']) == ('44', '0.20.0', 'com.circlr.integrationqa')
    sections = runpy.run_path(str(ROOT / 'qa/check-library-evidence.py'))['sections']
    compiled = sections(ROOT / '.build/integration-release/release/circlr')
    assert len(compiled) == 37 and compiled == sections(app / 'Contents/MacOS/circlr')
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    hashes = json.loads((FINAL / 'source-hashes.json').read_text()); assert len(hashes) == 5
    for name, digest in hashes.items():
        assert hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == digest
    kit = app / 'Contents/Resources/Codex'; manifest = json.loads((kit / 'manifest.json').read_text())
    assert len(manifest['files']) == 25
    for name, digest in manifest['files'].items():
        assert hashlib.sha256((kit / name).read_bytes()).hexdigest() == digest
    screenshots = {name: hashlib.sha256((OUT / (name+'.jpg')).read_bytes()).hexdigest() for name in REVISIONS if name not in ['edge-editor', 'cable-moved', 'restored']}
    result = dict(status='passed', revision=133, nativeSnapshots=len(captures), sourceFiles=5, kitFiles=25, executableSections=37,
                  physicalAudioAttempts=0, voiceOverSpeech='not_verified', screenshots=screenshots)
    (FINAL / 'verification.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(result, ensure_ascii=False))
