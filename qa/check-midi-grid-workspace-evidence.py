#!/usr/bin/env python3
"""Check recorded step/piano edits, native focus, restoration and final build provenance."""
import hashlib
import json
from pathlib import Path
import plistlib
import runpy
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'qa/generated/midi-grid-workspace'
FOCUSED, FINAL = OUT / 'focused', OUT / 'headers'
PROJECT = '2288FBF7-9BA4-5C8B-A750-6370E99FC2F4'
LANE = '055F3787-2B9D-4DD1-9752-56106F8D94F5'
KEYS = ['global', 'tracks', 'sections', 'arrangements', 'assets', 'patterns', 'portLayout', 'circleLayout']


def capture(folder, name, revision):
    data = json.loads((folder / (name + '.json')).read_text())
    state = data['state']
    assert state['projectID'] == PROJECT and state['revision'] == revision
    assert state['runtime']['bundleID'] == 'com.circlr.integrationqa'
    assert not state['dirty'] and not state['recording']['busy'] and not state['recording']['midi']
    assert not state['playback']['playing']
    return data


def notes(data):
    lanes = data['manifest']['arrangements'][0]['uses'][0]['addedLanes']
    return next(lane['notes'] for lane in lanes if lane['id'] == LANE)


def ax(folder, name):
    return (folder / (name + '-ax.txt')).read_text()


def main():
    before = capture(OUT, 'before', 14)
    chain = capture(FOCUSED, 'number-chain', 20)
    assert notes(chain)[0] == dict(notes(before)[0], pitch=65, beat=41, length=1.25, velocity=88)
    off = capture(FOCUSED, 'step-toggle-off', 21)
    assert notes(off) == notes(chain)[1:]
    entered = notes(capture(FOCUSED, 'step-input', 23))
    assert entered[:3] == notes(chain) and len(entered) == 4
    assert tuple(entered[-1][k] for k in ['pitch', 'beat', 'length', 'velocity']) == (65, 41.25, .225, 96)
    assert notes(capture(FOCUSED, 'piano-before', 24)) == notes(chain)
    for folder, name, revision, pitch, beat, length, velocity in [
        (FOCUSED, 'piano-drag', 25, 66, 39, 1.25, 88),
        (FOCUSED, 'piano-resize', 26, 66, 39, 1.75, 88),
        (FINAL, 'number-chain', 35, 66, 41, 1.25, 88),
        (FINAL, 'piano-drag', 36, 67, 39, 1.25, 88),
        (FINAL, 'piano-resize', 37, 67, 39, 1.75, 88),
        (FINAL, 'pitch-follow', 41, 37, 41, 1.25, 88),
        (FINAL, 'invalid-tab', 42, 37, 41, 2, 88),
        (FINAL, 'orbit-key-undo', 45, 38, 41, 2, 88)]:
        data = capture(folder, name, revision)
        assert tuple(notes(data)[0][k] for k in ['pitch', 'beat', 'length', 'velocity']) == (pitch, beat, length, velocity)
        assert notes(data)[1:] == notes(before)[1:]
    for name in ['step-state', 'step-state-kept']:
        text = ax(FOCUSED, name)
        assert 'radio button Description: 드럼, Value: 1' in text
        assert 'Description: 스텝 페이지, Help: Return으로 적용 · Esc로 취소, Value: 3' in text
        assert '36 · C2 · 33스텝' in text and '스텝 번호 33–48' in text
    assert ax(FINAL, 'step-header').count('스텝 번호 1–16') == 1
    assert '스텝 번호 161–176' in ax(FINAL, 'number-chain')
    assert '입력 범위: 1–127' in ax(FINAL, 'invalid-tab')
    assert 'Description: MIDI 세기' in ax(FINAL, 'invalid-tab').split('The focused UI element is')[-1]
    assert '편집 대상이 변경되었습니다' in ax(FINAL, 'stale-rejected')
    assert 'Value: 1.25' in ax(FINAL, 'resize-undo') and 'MCP 연결 가능 r38' in ax(FINAL, 'resize-undo')
    assert 'Value: 41' in ax(FINAL, 'move-undo') and 'MCP 연결 가능 r39' in ax(FINAL, 'move-undo')
    for folder, name, focus in [(FOCUSED, 'number-chain', '스텝 편집기'), (FINAL, 'number-chain', '스텝 편집기'),
                                (FINAL, 'piano-pinned', '피아노 롤'), (FINAL, 'pitch-follow', '피아노 롤'),
                                (FINAL, 'orbit-key', 'MIDI 궤도 편집기')]:
        assert focus in ax(folder, name).split('The focused UI element is')[-1]
    for folder, name, revision in [(OUT, 'first-restored', 16), (FOCUSED, 'before', 16),
                                   (FOCUSED, 'restored', 32), (FINAL, 'before', 32),
                                   (FINAL, 'restored', 53), (FINAL, 'reopened', 53)]:
        current = capture(folder, name, revision)
        for key in KEYS:
            assert current['manifest'].get(key) == before['manifest'].get(key), (name, key)
    source = Path.home() / 'Library/Application Support/circlr-integration-qa/fixtures/studio.circlr'
    assert hashlib.sha256((source / 'manifest.json').read_bytes()).hexdigest() == '12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d'
    for asset in before['manifest']['assets']:
        for folder in [source, source.with_name('midi-grid-workspace.circlr')]:
            assert hashlib.sha256((folder / asset['path']).read_bytes()).hexdigest() == asset['checksum']
    app = FINAL / '써클러 통합 검증.app'
    assert plistlib.loads((app / 'Contents/Info.plist').read_bytes())['CFBundleVersion'] == '37'
    sections = runpy.run_path(str(ROOT / 'qa/check-library-evidence.py'))['sections']
    compiled = sections(ROOT / '.build/integration-release/release/circlr')
    assert compiled == sections(app / 'Contents/MacOS/circlr')
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    hashes = json.loads((FINAL / 'source-hashes.json').read_text())
    for name, digest in hashes.items():
        assert hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == digest
    kit = app / 'Contents/Resources/Codex'
    files = json.loads((kit / 'manifest.json').read_text())['files']
    for name, digest in files.items():
        assert hashlib.sha256((kit / name).read_bytes()).hexdigest() == digest
    assert 'Executed 319 tests, with 0 failures' in (OUT / 'swift-tests-headers.log').read_text()
    assert 'Ran 26 tests' in (OUT / 'python-tests.log').read_text()
    screenshots = {}
    for name in ['step-header', 'piano-pinned', 'piano-drag', 'pitch-follow', 'orbit-shared']:
        path = FINAL / (name + '.jpg')
        raw = path.read_bytes()
        assert raw[:3] == b'\xff\xd8\xff'
        metadata = subprocess.check_output(['sips', '-g', 'pixelWidth', '-g', 'pixelHeight', str(path)], text=True)
        size = [int(re.search(label + r': (\d+)', metadata)[1]) for label in ['pixelWidth', 'pixelHeight']]
        screenshots[name] = dict(size=size, sha256=hashlib.sha256(raw).hexdigest())
    result = dict(result='passed', revision=53, sourceFiles=len(hashes), kitFiles=len(files),
                  fileBackedSections=len(compiled), screenshots=screenshots,
                  scope='Native MIDI grid editing and offline tests; no physical audio',
                  uuid=subprocess.check_output(['dwarfdump', '--uuid', str(app / 'Contents/MacOS/circlr')], text=True).strip())
    (FINAL / 'verification.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({k: v for k, v in result.items() if k != 'screenshots'}, ensure_ascii=False))


if __name__ == '__main__':
    main()
