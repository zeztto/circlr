#!/usr/bin/env python3
"""Check actual editor continuity, fixed range, undo and exact QA build provenance."""
import hashlib
import json
import math
from pathlib import Path
import plistlib
import runpy
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'qa/generated/editing-continuity'
NODE = 'F040BB79-274C-5168-9E71-0B62AA6BDD50'
KEYS = ['global', 'tracks', 'sections', 'arrangements', 'assets', 'patterns', 'portLayout', 'circleLayout']


def capture(name, revision):
    data = json.loads((OUT / (name + '.json')).read_text())
    state = data['state']
    assert state['projectID'] == 'F37977C8-9E22-5966-9F37-2ECD1C27A1E5'
    assert state['runtime']['bundleID'] == 'com.circlr.integrationqa' and state['revision'] == revision
    assert not state['dirty'] and not state['recording']['busy'] and not state['recording']['midi']
    assert not state['playback']['playing']
    return data


def points(data):
    node = data['manifest']['arrangements'][0]['uses'][0]['graphEdits']['nodeOverrides'][NODE]
    return next(a['points'] for a in node['automation'] if a['parameter'] == 'gain')


def ax(name):
    return (OUT / (name + '-ax.txt')).read_text()


def same_editor(a, b):
    sa, sb = a['state'], b['state']
    assert sa['selection'] == sb['selection']
    assert sa['playback']['editorAddress'] == sb['playback']['editorAddress'] == sa['selection']
    fa, fb = sa['playback']['editorFrame'], sb['playback']['editorFrame']
    assert len(fa) == len(fb) == 4
    assert all(math.isclose(x, y, abs_tol=1e-6) for x, y in zip(fa, fb))


def main():
    before = capture('before', 14)
    start, orbit = capture('selected-start', 15), capture('menu-orbit', 15)
    same_editor(start, orbit)
    assert start['state']['view']['layout'] == 'freeform' and orbit['state']['view']['layout'] == 'orbit'
    assert start['state']['automationEditor'] == orbit['state']['automationEditor']
    assert points(start) == points(orbit)
    assert 'Value: 64' in ax('end-click-kept') and 'MCP 연결 가능 r15' in ax('end-click-kept')
    dragged = capture('end-drag', 16)
    assert points(dragged)[0] == points(start)[0]
    assert points(dragged)[1]['id'] == 'qa-end' and points(dragged)[1]['beat'] == 56
    for name, revision in [('layout-undo', 18), ('command-freeform', 19)]:
        current = capture(name, revision)
        same_editor(start, current)
        assert points(current) == points(start) and current['state']['view']['layout'] == 'freeform'
        assert current['state']['automationEditor']['selectedPointID'] == 'qa-end'
    assert 'MCP 연결 가능 r19' in ax('layout-redo') and 'Value: 64' in ax('layout-redo')
    for name, revision, extent, last in [('range-fixed', 21, 96, 80), ('range-outside128', 22, 96, 128),
                                       ('range-layout-kept', 22, 128, 128), ('range-local-reset', 22, 64, 128)]:
        current = capture(name, revision)
        same_editor(start, current)
        assert current['state']['automationEditor']['displayBeats'] == extent
        assert points(current)[-1]['beat'] == last
    for a, b in [('step-orbit', 'step-freeform'), ('midi-freeform', 'midi-orbit-preserved'), ('audio-orbit', 'audio-freeform')]:
        first, second = capture(a, 22), capture(b, 22)
        same_editor(first, second)
        assert first['state']['view']['layout'] != second['state']['view']['layout']
        for key in KEYS:
            if key != 'circleLayout':
                assert first['manifest'].get(key) == second['manifest'].get(key), (a, key)
    assert 'radio button Description: 스텝, Value: 1' in ax('step-freeform')
    assert 'radio button Description: 궤도, Value: 1' in ax('midi-orbit-preserved')
    assert '분할 위치 초' in ax('audio-freeform')
    for name in ['restored', 'reopened']:
        current = capture(name, 32)
        for key in KEYS:
            assert current['manifest'].get(key) == before['manifest'].get(key), (name, key)
    source = Path.home() / 'Library/Application Support/circlr-integration-qa/fixtures/studio.circlr'
    assert hashlib.sha256((source / 'manifest.json').read_bytes()).hexdigest() == '12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d'
    for asset in before['manifest']['assets']:
        for folder in [source, source.with_name('editing-continuity.circlr')]:
            assert hashlib.sha256((folder / asset['path']).read_bytes()).hexdigest() == asset['checksum']
    app = OUT / '써클러 통합 검증.app'
    assert plistlib.loads((app / 'Contents/Info.plist').read_bytes())['CFBundleVersion'] == '35'
    sections = runpy.run_path(str(ROOT / 'qa/check-library-evidence.py'))['sections']
    compiled = sections(ROOT / '.build/integration-release/release/circlr')
    assert compiled == sections(app / 'Contents/MacOS/circlr')
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    hashes = json.loads((OUT / 'source-hashes.json').read_text())
    for name, digest in hashes.items():
        assert hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == digest
    kit = app / 'Contents/Resources/Codex'
    files = json.loads((kit / 'manifest.json').read_text())['files']
    for name, digest in files.items():
        assert hashlib.sha256((kit / name).read_bytes()).hexdigest() == digest
    assert 'Executed 311 tests, with 0 failures' in (OUT / 'swift-tests.log').read_text()
    assert 'Ran 26 tests' in (OUT / 'python-tests.log').read_text()
    result = dict(result='passed', revision=32, scope='Native layout continuity and automation range; no physical audio',
                  fileBackedSections=len(compiled), sourceFiles=len(hashes), kitFiles=len(files),
                  uuid=subprocess.check_output(['dwarfdump', '--uuid', str(app / 'Contents/MacOS/circlr')], text=True).strip())
    (OUT / 'verification.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(result, ensure_ascii=False))


if __name__ == '__main__':
    main()
