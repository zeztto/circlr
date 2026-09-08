#!/usr/bin/env python3
"""Verify recorded MIDI edits, view continuity, restoration and final QA binary."""
import hashlib
import json
import math
from pathlib import Path
import plistlib
import runpy
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'qa/generated/midi-orbit-workspace'
FINAL = OUT / 'compact'
PROJECT = '5DDA6D8F-E6FF-545A-BB6F-FBE90F904069'
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


def same_editor(a, b):
    a, b = a['state'], b['state']
    assert a['selection'] == b['selection'] == a['playback']['editorAddress'] == b['playback']['editorAddress']
    first, second = a['playback']['editorFrame'], b['playback']['editorFrame']
    assert len(first) == len(second) == 4
    assert all(math.isclose(x, y, abs_tol=1e-6) for x, y in zip(first, second))


def main():
    before = capture(OUT, 'before', 14)
    cases = [('note-selected', 14, 66, 0, .5, 70), ('pitch-key', 16, 68, 0, .5, 70),
             ('number-chain', 20, 67, 1, 1, 85), ('resize-drag', 22, 67, 1, 2, 80),
             ('move-drag', 24, 67, 2.75, 1, 80), ('page-follow', 26, 67, 40, 1, 80),
             ('stale-rejected', 27, 68, 40, 1, 80)]
    for name, revision, pitch, beat, length, velocity in cases:
        current = notes(capture(OUT, name, revision))
        assert tuple(current[0][k] for k in ['pitch', 'beat', 'length', 'velocity']) == (pitch, beat, length, velocity)
        assert current[1:] == notes(before)[1:]
    chain = capture(FINAL, 'number-chain', 39)
    freeform = capture(FINAL, 'freeform', 39)
    kept = capture(FINAL, 'range-preserved', 39)
    for current in [chain, freeform, kept]:
        assert tuple(notes(current)[0][k] for k in ['pitch', 'beat', 'length', 'velocity']) == (68, 0, 20, 90)
        same_editor(chain, current)
    assert freeform['state']['view']['layout'] == 'freeform'
    assert kept['state']['view']['layout'] == 'orbit'
    for name in ['clipped-reselected', 'range-preserved']:
        text = ax(FINAL, name)
        assert '3–4마디 / 16' in text and 'menu button 2마디씩 보기' in text
        assert 'radio button Description: 2옥타브, Value: 1' in text
        assert '앞에서 이어짐 · 다음 범위로 이어짐' in text
        assert 'The focused UI element is' in text and 'MIDI 궤도 편집기' in text.split('The focused UI element is')[-1]
    multi = ax(FINAL, 'multi-selection')
    assert '3개 선택' in multi and 'Description: MIDI 음높이,' not in multi
    assert '입력 범위: 1–127' in ax(FINAL, 'invalid-velocity')
    assert '편집 대상이 변경되었습니다' in ax(FINAL, 'stale-rejected')
    assert 'button 선택 보기' in ax(FINAL, 'outside-selection')
    assert '1–2마디 / 16' in ax(FINAL, 'selection-return')
    dragged = capture(FINAL, 'clipped-drag', 40)
    assert notes(dragged)[0] == dict(notes(chain)[0], beat=1)
    assert notes(capture(FINAL, 'drag-undo', 41)) == notes(chain)
    rejected = capture(FINAL, 'stale-rejected', 42)
    assert notes(rejected)[0] == dict(notes(chain)[0], pitch=69)
    for folder, name, revision in [(OUT, 'first-restored', 35), (OUT, 'final-before', 35),
                                   (FINAL, 'restored', 50), (FINAL, 'reopened', 50)]:
        restored = capture(folder, name, revision)
        for key in KEYS:
            assert restored['manifest'].get(key) == before['manifest'].get(key), (name, key)
    source = Path.home() / 'Library/Application Support/circlr-integration-qa/fixtures/studio.circlr'
    assert hashlib.sha256((source / 'manifest.json').read_bytes()).hexdigest() == '12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d'
    for asset in before['manifest']['assets']:
        for folder in [source, source.with_name('midi-orbit-workspace.circlr')]:
            assert hashlib.sha256((folder / asset['path']).read_bytes()).hexdigest() == asset['checksum']
    app = FINAL / '써클러 통합 검증.app'
    assert plistlib.loads((app / 'Contents/Info.plist').read_bytes())['CFBundleVersion'] == '36'
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
    assert 'Executed 318 tests, with 0 failures' in (OUT / 'swift-tests-final.log').read_text()
    assert 'Ran 26 tests' in (OUT / 'python-tests.log').read_text()
    result = dict(result='passed', revision=50, sourceFiles=len(hashes), kitFiles=len(files),
                  fileBackedSections=len(compiled), scope='MIDI orbit UI and offline editing; no physical audio',
                  uuid=subprocess.check_output(['dwarfdump', '--uuid', str(app / 'Contents/MacOS/circlr')], text=True).strip())
    (FINAL / 'verification.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(result, ensure_ascii=False))


if __name__ == '__main__':
    main()
