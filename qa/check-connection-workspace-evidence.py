#!/usr/bin/env python3
"""Verify build 41's local native artifacts; not a portable CI UI test."""
import copy
import hashlib
import json
from pathlib import Path
import plistlib
import re
import runpy
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'qa/generated/connection-workspace'
FINAL = OUT / 'top'
PROJECT = 'D6270D46-4C41-50D0-9E94-E0A3C973A7DD'
INSTRUMENT = 'instrument:7E0D9016-E91D-4325-B807-033F233E32EA'
BUS7 = '378FC235-1EBA-5211-A3EA-A28E899BD4A3'
BUS8 = 'FC594C57-9A4D-5CE5-8515-4BDEC427C117'
KEYS = ['global', 'tracks', 'sections', 'arrangements', 'assets', 'patterns', 'portLayout', 'circleLayout', 'signal']


def capture(name, revision):
    data = json.loads((OUT / (name + '.json')).read_text())
    state = data['state']
    assert state['projectID'] == PROJECT and state['revision'] == revision, name
    assert state['runtime']['bundleID'] == 'com.circlr.integrationqa'
    assert not state['dirty'] and not state['recording']['busy'] and not state['recording']['midi']
    assert not state['playback'].get('playing', False) and state['output']['attempts'] == 0
    return data


def normalized(manifest, key):
    data = copy.deepcopy(manifest.get(key))
    if key == 'portLayout' and data is not None:
        # Layout epochs advance on Undo to invalidate gestures; bindings/placements must restore.
        data.pop('revision', None)
    return data


def edges(data):
    return data['manifest']['arrangements'][0]['uses'][0]['graphEdits']['addedEdges']


def ax(name):
    return (OUT / (name + '-ax.txt')).read_text()


def main():
    before = capture('before', 14)
    unselected = capture('unselected', 14)
    assert edges(unselected) == edges(before)
    seven = capture('connected-seven', 15)
    new7 = next(e for e in edges(seven) if e['from'] == INSTRUMENT and e['to'] == BUS7)
    eight = capture('connected-eight', 16)
    assert any(e['from'] == INSTRUMENT and e['to'] == BUS8 for e in edges(eight))
    disconnected = capture('disconnected-midi', 17)
    incoming = capture('connected-midi-input', 18)
    assert len(edges(disconnected)) + 1 == len(edges(incoming)) == len(edges(eight))
    assert any(e['signal'] == 'midi' and e['to'] == INSTRUMENT and e['from'].startswith('midi:') for e in edges(incoming))
    reconnected = capture('reconnected', 19)
    moved = capture('moved-position', 19)
    new = next(e for e in edges(reconnected) if e['id'] == new7['id'])
    assert new['to'] == 'F040BB79-274C-5168-9E71-0B62AA6BDD50' and new['gain'] == new7['gain']
    for key in KEYS:
        if key != 'portLayout':
            assert reconnected['manifest'].get(key) == moved['manifest'].get(key), key
    assert moved['manifest']['portLayout']['revision'] == reconnected['manifest']['portLayout']['revision'] + 1
    empty = capture('empty-results', 19)
    assert empty['manifest'] == moved['manifest']
    for name, revision in [('compact-restored', 24), ('compact-reopened', 24), ('named-before', 24),
                           ('named-restored', 26), ('fixed-restored', 28), ('clipped-restored', 32),
                           ('sized-restored', 36), ('top-before', 36), ('top-restored', 40), ('top-reopened', 40)]:
        restored = capture(name, revision)
        for key in KEYS:
            assert normalized(restored['manifest'], key) == normalized(before['manifest'], key), (name, key)
    group = capture('top-group-connected', 37)
    no_selection = capture('top-unselected', 37)
    for key in KEYS:
        assert group['manifest'].get(key) == no_selection['manifest'].get(key), key
    assert any(e['from'] == 'FC5544DC-54E1-5CBB-80C3-514C5087D9C1' and e['to'] == BUS7 for e in edges(group))
    connected = capture('top-connected', 38)
    final8 = next(e for e in edges(connected) if e['from'] == INSTRUMENT and e['to'] == BUS8)
    placement = next(c['placement'] for c in connected['manifest']['portLayout']['connections'] if c['id']['edgeID'] == final8['id'])
    assert placement == {'from': 3, 'to': 7}
    assert len(edges(connected)) == len(edges(before)) + 2
    for key in ['global', 'tracks', 'sections', 'assets', 'patterns', 'signal']:
        assert connected['manifest'].get(key) == before['manifest'].get(key), key
    assert connected['manifest']['arrangements'][0]['uses'][1] == before['manifest']['arrangements'][0]['uses'][1]
    expanded = capture('top-expanded', 38)
    assert expanded['state']['playback']['editorFrame'][3] > connected['state']['playback']['editorFrame'][3]
    assert expanded['manifest'] == connected['manifest']
    assert '연결 9개' in ax('compact-current-output-settled')
    assert '연결 2개' in ax('compact-current-input') and 'Value: IN MIDI 연주' in ax('compact-current-input')
    assert '연결 2개' in ax('top-group-filtered') and 'Value: 현재 포트' in ax('top-group-filtered')
    assert '검색 결과가 없습니다' in ax('top-empty') and 'button (disabled) 연결' in ax('top-empty')
    assert '상속한 MIDI 리듬' in ax('top-scrolled') and '접힌 그룹 내부' not in ax('top-scrolled')
    for name in ['top-group', 'top-group-filtered', 'top-scrolled', 'top-empty', 'top-expanded']:
        assert 'Description: 시작 위치,' in ax(name) and 'Description: 대상 위치,' in ax(name), name
    assert '내부 서클·포트 검색' in ax('compact-group-management').split('The focused UI element is')[-1]
    assert '대상 이름 검색' in ax('compact-group-returned').split('The focused UI element is')[-1]
    source = Path.home() / 'Library/Application Support/circlr-integration-qa/fixtures/studio.circlr'
    assert hashlib.sha256((source / 'manifest.json').read_bytes()).hexdigest() == '12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d'
    for asset in before['manifest']['assets']:
        for folder in [source, source.with_name('connection-workspace.circlr')]:
            assert hashlib.sha256((folder / asset['path']).read_bytes()).hexdigest() == asset['checksum']
    app = FINAL / '써클러 통합 검증.app'
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    assert (info['CFBundleVersion'], info['CFBundleShortVersionString'], info['CFBundleIdentifier']) == ('41', '0.20.0', 'com.circlr.integrationqa')
    sections = runpy.run_path(str(ROOT / 'qa/check-library-evidence.py'))['sections']
    compiled = sections(ROOT / '.build/integration-release/release/circlr')
    assert len(compiled) == 37 and compiled == sections(app / 'Contents/MacOS/circlr')
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    hashes = json.loads((FINAL / 'source-hashes.json').read_text())
    assert len(hashes) == 4
    for name, digest in hashes.items():
        assert hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == digest, name
    kit = app / 'Contents/Resources/Codex'
    files = json.loads((kit / 'manifest.json').read_text())['files']
    assert len(files) == 25
    for name, digest in files.items():
        assert hashlib.sha256((kit / name).read_bytes()).hexdigest() == digest
    assert 'Executed 330 tests, with 0 failures' in (OUT / 'swift-tests-final.log').read_text()
    python_log = (OUT / 'python-tests.log').read_text()
    assert 'Ran 26 tests' in python_log and '\nOK\n' in python_log
    screenshots = {}
    for path in sorted(OUT.glob('top-*.jpg')):
        raw = path.read_bytes()
        assert raw[:3] == b'\xff\xd8\xff'
        metadata = subprocess.check_output(['sips', '-g', 'pixelWidth', '-g', 'pixelHeight', str(path)], text=True)
        size = [int(re.search(label + r': (\d+)', metadata)[1]) for label in ['pixelWidth', 'pixelHeight']]
        assert size == [1019, 768], path.name
        screenshots[path.name] = dict(size=size, sha256=hashlib.sha256(raw).hexdigest())
    assert len(screenshots) == 7
    result = dict(result='passed', restoredRevision=40, restoredLayoutRevision=20, sourceFiles=len(hashes), kitFiles=len(files),
                  fileBackedSections=len(compiled), screenshots=screenshots,
                  scope='Native connection input/filter/navigation and restoration. Compact candidate covers reconnect/MIDI/position Undo; final top candidate covers group/music connections and control visibility. No device playback/capture.',
                  uuid=subprocess.check_output(['dwarfdump', '--uuid', str(app / 'Contents/MacOS/circlr')], text=True).strip())
    (FINAL / 'verification.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({k: v for k, v in result.items() if k != 'screenshots'}, ensure_ascii=False))


if __name__ == '__main__':
    main()
