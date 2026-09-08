#!/usr/bin/env python3
"""Check build 42 native MIDI timing, restoration and final package evidence."""
import copy
import hashlib
import json
from pathlib import Path
import plistlib
import runpy
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'qa/generated/midi-placement'
FINAL = OUT / 'guarded'
KEYS = ['name', 'global', 'tracks', 'sections', 'arrangements', 'assets', 'patterns', 'signal', 'portLayout', 'circleLayout']


def normalized(project, key):
    value = copy.deepcopy(project.get(key))
    if key == 'portLayout' and value is not None:
        value.pop('revision', None)
    return value


def capture(name, revision):
    value = json.loads((OUT / (name + '.json')).read_text())
    state = value['state']
    assert state['revision'] == revision and not state['dirty']
    assert state['runtime']['bundleID'] == 'com.circlr.integrationqa'
    assert state['projectID'] == '586E904D-0A3D-5BCF-9B3B-2F4193A8C566'
    assert state['output']['attempts'] == 0 and not state['recording']['busy'] and not state['recording']['midi']
    return value


if __name__ == '__main__':
    before = capture('before', 14)['manifest']
    for name, revision in [('preview-unchanged', 14), ('batch-undo', 16), ('single-undo', 18), ('guarded-before', 18), ('guarded-undo', 20), ('restored', 22), ('reopened', 22)]:
        restored = capture(name, revision)['manifest']
        for key in KEYS:
            assert normalized(restored, key) == normalized(before, key), (name, key)
    old_tracks = {t['id'] for t in before['tracks']}
    for name, revision in [('batch', 15), ('guarded-batch', 19), ('single', 17)]:
        captured = capture(name, revision)
        project = captured['manifest']
        count = 1 if name == 'single' else 2
        assert len(project['tracks']) == len(old_tracks) + count
        assert project['sections'] == before['sections'] and project['assets'] == before['assets']
        assert project['arrangements'][0]['uses'][1] == before['arrangements'][0]['uses'][1]
        use = project['arrangements'][0]['uses'][0]
        assert use.get('barsOverride', 16) == (16 if count == 1 else 18)
        lanes = [l for l in use['addedLanes'] if l['trackID'] not in old_tracks]
        assert len(lanes) == count
        for lane in lanes:
            assert [n['beat'] for n in lane['notes']] == ([0.5, 2.25, 60] if count == 1 else [8.75, 10.5, 68.25])
            assert [n['length'] for n in lane['notes']] == [0.75, 1, 1]
            assert [n['velocity'] for n in lane['notes']] == [81, 105, 91]
        assert (captured['state']['playback']['editorAddress'] is not None) == (count == 1)
        for identifier, position in before['signal']['layout']['positions'].items():
            assert project['signal']['layout']['positions'][identifier] == position
    stale = capture('guarded-stale', 21)['manifest']
    for key in KEYS[1:]:
        assert normalized(stale, key) == normalized(before, key), key
    assert 'button (disabled) 2개 서클 가져오기' in (OUT / 'overflow-ax.txt').read_text()
    assert '끝 위치 70.25박' in (OUT / 'guarded-preview-ax.txt').read_text()
    stale_ax = (OUT / 'guarded-stale-ax.txt').read_text()
    assert '프로젝트가 변경됐습니다. 취소하고 파일을 다시 선택하세요.' in stale_ax
    assert 'button (disabled) 2개 서클 가져오기' in stale_ax
    source = Path.home() / 'Library/Application Support/circlr-integration-qa/fixtures/studio.circlr'
    assert hashlib.sha256((source / 'manifest.json').read_bytes()).hexdigest() == '12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d'
    for asset in before['assets']:
        for folder in [source, source.with_name('midi-placement.circlr')]:
            assert hashlib.sha256((folder / asset['path']).read_bytes()).hexdigest() == asset['checksum']
    app = FINAL / '써클러 통합 검증.app'
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    assert (info['CFBundleVersion'], info['CFBundleShortVersionString'], info['CFBundleIdentifier']) == ('42', '0.20.0', 'com.circlr.integrationqa')
    sections = runpy.run_path(str(ROOT / 'qa/check-library-evidence.py'))['sections']
    compiled = sections(ROOT / '.build/integration-release/release/circlr')
    assert len(compiled) == 37 and compiled == sections(app / 'Contents/MacOS/circlr')
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    for name, digest in json.loads((FINAL / 'source-hashes.json').read_text()).items():
        assert hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == digest
    kit = app / 'Contents/Resources/Codex'
    manifest = json.loads((kit / 'manifest.json').read_text())
    assert len(manifest['files']) == 25
    for name, digest in manifest['files'].items():
        assert hashlib.sha256((kit / name).read_bytes()).hexdigest() == digest
    screenshots = {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in OUT.glob('*.jpg')}
    assert len(screenshots) == 6
    result = dict(status='passed', revision=22, sourceFiles=6, kitFiles=25, executableSections=37, screenshots=screenshots)
    (FINAL / 'verification.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(result, ensure_ascii=False))
