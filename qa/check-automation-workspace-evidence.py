#!/usr/bin/env python3
"""Verify captured automation edits, restoration and exact QA package provenance."""
import hashlib
import json
import math
from pathlib import Path
import plistlib
import runpy
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'qa/generated/automation-workspace'
NODE = 'F040BB79-274C-5168-9E71-0B62AA6BDD50'
KEYS = ['global', 'tracks', 'sections', 'arrangements', 'assets', 'patterns', 'portLayout', 'circleLayout']


def capture(name, revision):
    data = json.loads((OUT / (name + '.json')).read_text())
    state = data['state']
    assert state['projectID'] == 'C9FE4910-13B5-512A-AA14-39EA01D3F634'
    assert state['runtime']['bundleID'] == 'com.circlr.integrationqa'
    assert state['revision'] == revision and not state['dirty']
    assert not state['recording']['busy'] and not state['recording']['midi']
    return data


def node(project, original=False, use=0):
    if original:
        return next(n for n in project['sections'][0]['graph']['nodes'] if n['id'] == NODE)
    return project['arrangements'][0]['uses'][use]['graphEdits']['nodeOverrides'].get(NODE, {})


def lane(project, parameter='gain', original=False):
    return next((a for a in node(project, original).get('automation') or [] if a['parameter'] == parameter), None)


def ax(name):
    return (OUT / (name + '-ax.txt')).read_text()


def near(a, b):
    assert math.isclose(a, b, rel_tol=1e-12, abs_tol=1e-12), (a, b)


def main():
    before = capture('before', 14)['manifest']
    two = capture('two-points', 22)['manifest']
    points = lane(two)['points']
    assert [p['beat'] for p in points] == [4, 32]
    near(points[0]['value'], 10 ** (-6 / 20))
    assert points[1]['value'] == 1 and not node(two, use=1)
    assert two['sections'] == before['sections'] and two['tracks'] == before['tracks']
    bypass = lane(capture('bypassed', 24)['manifest'])
    assert not bypass['enabled'] and bypass['points'][0]['shape'] == 'hold'
    pan = capture('pan-fine', 28)['manifest']
    near(lane(pan, 'pan')['points'][0]['value'], -0.49)
    assert lane(pan)['enabled'] and lane(pan)['points'] == bypass['points']
    assert '입력 범위: -100.00–100.00 %' in ax('pan-invalid') and 'MCP 연결 가능 r28' in ax('pan-invalid')
    key = capture('final-gain-key', 44)['manifest']
    near(lane(key)['points'][0]['value'], 10 ** (-5.5 / 20))
    dragged = capture('orbit-drag', 45)['manifest']
    assert lane(dragged)['points'][0]['beat'] == 16 and lane(dragged)['points'][0]['value'] == 4
    assert lane(capture('orbit-undo', 46)['manifest']) == lane(key)
    all_points = capture('all-points', 47)
    assert all_points['state']['automationEditor']['displayBeats'] == 96
    assert lane(all_points['manifest'])['points'][-1]['beat'] == 96
    outside = capture('outside-key', 48)
    assert outside['state']['automationEditor']['displayBeats'] == 95.75
    assert lane(outside['manifest'])['points'][-1]['beat'] == 95.75
    shared = capture('original-point', 50)['manifest']
    assert lane(shared) == lane(all_points['manifest'])
    assert len(lane(shared, original=True)['points']) == 1 and not node(shared, use=1)
    stale = capture('stale-rejected', 51)['manifest']
    near(lane(stale)['points'][0]['value'], 0.4)
    assert '편집 대상이 변경되었습니다' in ax('stale-rejected')
    assert 'The focused UI element is 50 container Description: 오토메이션 곡선' in ax('stale-cancelled')
    deleted = capture('point-deleted', 52)['manifest']
    assert lane(deleted)['points'] == lane(stale)['points'][1:]
    assert 'MCP 연결 가능 r53' in ax('point-delete-undo')
    cleared = capture('curve-cleared', 54)['manifest']
    assert lane(cleared) is None and lane(cleared, original=True) == lane(stale, original=True)
    assert 'MCP 연결 가능 r55' in ax('curve-clear-undo')
    freeform = lane(capture('freeform-drag', 56)['manifest'])['points'][0]
    assert freeform['beat'] == 16 and 1 < freeform['value'] < 4
    undone = capture('freeform-undo', 57)['manifest']
    for key_name in KEYS:
        if key_name != 'circleLayout':
            assert undone.get(key_name) == stale.get(key_name), key_name
    assert '이번 사용에 추가된 서클입니다' in ax('added-output-original')
    assert 'MCP 연결 가능 r57' in ax('added-output-disabled')
    assert 'checkbox Description: 공유 원본 편집, Value: 0' in ax('added-output-local')
    for name, revision in [('first-restored', 41), ('final-restored', 65), ('reopened', 65)]:
        restored = capture(name, revision)['manifest']
        for key_name in KEYS:
            assert restored.get(key_name) == before.get(key_name), (name, key_name)
    source = Path.home() / 'Library/Application Support/circlr-integration-qa/fixtures/studio.circlr'
    assert hashlib.sha256((source / 'manifest.json').read_bytes()).hexdigest() == '12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d'
    for asset in before['assets']:
        for folder in [source, source.with_name('automation-workspace.circlr')]:
            assert hashlib.sha256((folder / asset['path']).read_bytes()).hexdigest() == asset['checksum']
    app = OUT / 'orbit/써클러 통합 검증.app'
    assert plistlib.loads((app / 'Contents/Info.plist').read_bytes())['CFBundleVersion'] == '34'
    sections = runpy.run_path(str(ROOT / 'qa/check-library-evidence.py'))['sections']
    compiled = sections(ROOT / '.build/integration-release/release/circlr')
    assert compiled == sections(app / 'Contents/MacOS/circlr')
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    hashes = json.loads((OUT / 'orbit/source-hashes.json').read_text())
    for name, digest in hashes.items():
        assert hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == digest
    kit = app / 'Contents/Resources/Codex'
    files = json.loads((kit / 'manifest.json').read_text())['files']
    for name, digest in files.items():
        assert hashlib.sha256((kit / name).read_bytes()).hexdigest() == digest
    assert 'Executed 307 tests, with 0 failures' in (OUT / 'swift-tests.log').read_text()
    assert 'Ran 26 tests' in (OUT / 'python-all-tests.log').read_text()
    assert 'Build complete!' in (OUT / 'orbit-release.log').read_text()
    result = dict(result='passed', scope='Automation editor, offline regression and package; no physical audio input/output',
                  revision=65, fileBackedSections=len(compiled), kitFiles=len(files), sourceFiles=len(hashes),
                  uuid=subprocess.check_output(['dwarfdump', '--uuid', str(app / 'Contents/MacOS/circlr')], text=True).strip())
    (OUT / 'verification.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(result, ensure_ascii=False))


if __name__ == '__main__':
    main()
