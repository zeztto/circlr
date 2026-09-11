#!/usr/bin/env python3
"""Check build 39's recorded native evidence, restoration and package provenance.

Requires the local authored-fixture run. This is not a portable CI UI test.
"""
import hashlib
import json
import math
from pathlib import Path
import plistlib
import re
import runpy
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'qa/generated/editor-shell'
FINAL = OUT / 'reviewed'
PROJECT = '4256ADCF-8FDE-5470-9E33-4F5DC174AD16'
LANE = '7F32786A-C5A8-5B33-BEA3-0D5D029F3C14'
NODE = 'DDB48BA6-04EC-5F78-8AB1-7CC61F46EAC7'
KEYS = ['global', 'tracks', 'sections', 'arrangements', 'assets', 'patterns', 'portLayout', 'circleLayout']


def capture(name, revision):
    data = json.loads((OUT / (name + '.json')).read_text())
    state = data['state']
    assert state['projectID'] == PROJECT and state['revision'] == revision, name
    assert state['runtime']['bundleID'] == 'com.circlr.integrationqa'
    assert not state['dirty'] and not state['recording']['busy'] and not state['recording']['midi']
    assert not state['playback'].get('playing', False) and state['output']['attempts'] == 0
    return data


def use(data):
    return data['manifest']['arrangements'][0]['uses'][0]


def ax(name):
    return (OUT / (name + '-ax.txt')).read_text()


def main():
    before = capture('before', 14)
    piano = capture('final-number-chain', 19)
    step = capture('final-step-returned', 21)
    orbit = capture('final-orbit-returned', 21)
    audio = capture('final-audio-number-chain', 27)
    automation = capture('final-automation-selected', 28)
    closed = capture('final-console-closed', 28)
    reviewed_piano = capture('reviewed-number-chain', 45)
    reviewed_audio = capture('reviewed-audio-number-chain', 51)
    reviewed_edits = capture('reviewed-after-edits', 52)
    for data in [piano, step, orbit, reviewed_piano]:
        notes = use(data)['addedLanes'][0]['notes']
        original = use(before)['addedLanes'][0]['notes']
        assert notes[1:] == original[1:]
        assert notes[0] == dict(original[0], pitch=67, beat=1, length=1, velocity=90)
    # Mode/layout switches and the arrow-edit/Undo preserve the edited music.
    for key in ['global', 'tracks', 'sections', 'arrangements', 'assets', 'patterns']:
        assert piano['manifest'].get(key) == step['manifest'].get(key) == orbit['manifest'].get(key)
    for data in [audio, reviewed_audio]:
        clip = use(data)['laneOverrides'][LANE]['audio'][0]
        assert (clip['sourceStart'], clip['duration'], clip['fadeIn'], clip['fadeOut'], clip['sourceBPM']) == (1, 7, .1, .2, 100)
        assert math.isclose(clip['gain'], 10 ** (-3 / 20), abs_tol=1e-12)
        assert use(data)['addedLanes'] == use(piano)['addedLanes']
    for data in [automation, reviewed_edits]:
        lane = use(data)['graphEdits']['nodeOverrides'][NODE]['automation'][0]
        assert lane['enabled'] and lane['parameter'] == 'gain' and len(lane['points']) == 1
        point = lane['points'][0]
        assert (point['beat'], point['value'], point['shape']) == (0, 1, 'linear')
    for data in [piano, step, orbit, audio, automation, reviewed_piano, reviewed_audio, reviewed_edits]:
        frame = data['state']['playback']['editorFrame']
        reference = piano['state']['playback']['editorFrame']
        assert len(frame) == len(reference) == 4
        assert all(math.isclose(a, b, abs_tol=1e-8, rel_tol=0) for a, b in zip(frame, reference))
        for key in ['global', 'tracks', 'sections', 'assets', 'patterns']:
            assert data['manifest'].get(key) == before['manifest'].get(key), key
        assert data['manifest']['arrangements'][0]['uses'][1] == before['manifest']['arrangements'][0]['uses'][1]
    small = piano['state']['playback']['editorFrame']
    expanded = closed['state']['playback']['editorFrame']
    assert expanded[:3] == small[:3] and expanded[3] > small[3]
    for name, revision in [('first-restored', 15), ('final-before', 15), ('compact-restored', 41),
                           ('reviewed-before', 41), ('final-restored', 64), ('final-reopened', 64)]:
        data = capture(name, revision)
        for key in KEYS:
            assert data['manifest'].get(key) == before['manifest'].get(key), (name, key)
    for name, mode in [('final-settings', '설정'), ('final-connections', '연결'),
                       ('final-orbit-returned', 'MIDI'), ('final-audio-returned', '오디오'),
                       ('final-automation-selected', '오토메이션'), ('reviewed-settings', '설정'),
                       ('reviewed-connections', '연결'), ('reviewed-returned', 'MIDI'),
                       ('reviewed-automation-selected', '오토메이션'), ('reviewed-group-returned', '편집')]:
        assert '(selected) Description: 작업 전환 · ' + mode + ',' in ax(name), name
    for name in ['final-number-chain', 'final-orbit-returned', 'final-audio-number-chain',
                 'reviewed-number-chain', 'reviewed-audio-number-chain', 'reviewed-audio-returned']:
        assert '편집기' in ax(name).split('The focused UI element is')[-1] or '피아노 롤' in ax(name).split('The focused UI element is')[-1]
    assert '3개 선택' in ax('final-multi-selected') and '3개 선택' in ax('final-orbit-multi')
    assert 'Value: 1.25' in ax('final-key-edit')
    assert '편집 편집' not in ax('reviewed-group-returned')
    assert '이 서클의 편집으로 돌아가기' in ax('reviewed-group-returned')
    source = Path.home() / 'Library/Application Support/circlr-integration-qa/fixtures/studio.circlr'
    assert hashlib.sha256((source / 'manifest.json').read_bytes()).hexdigest() == '12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d'
    for asset in before['manifest']['assets']:
        for folder in [source, source.with_name('editor-shell.circlr')]:
            assert hashlib.sha256((folder / asset['path']).read_bytes()).hexdigest() == asset['checksum']
    app = FINAL / '써클러 통합 검증.app'
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    assert (info['CFBundleVersion'], info['CFBundleShortVersionString'], info['CFBundleIdentifier']) == ('39', '0.20.0', 'com.circlr.integrationqa')
    sections = runpy.run_path(str(ROOT / 'qa/check-library-evidence.py'))['sections']
    compiled = sections(ROOT / '.build/integration-release/release/circlr')
    assert compiled == sections(app / 'Contents/MacOS/circlr')
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    hashes = json.loads((FINAL / 'source-hashes.json').read_text())
    for name, digest in hashes.items():
        assert hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == digest, name
    compact_hashes = json.loads((OUT / 'compact/source-hashes.json').read_text())
    changed = [name for name in hashes if hashes[name] != compact_hashes[name]]
    assert changed == ['Sources/CirclrApp/InlineEditorHeader.swift']
    # All compact candidate layout/input evidence predates only these two reviewed header changes.
    prior = (ROOT / changed[0]).read_text().replace(
        'help:store.selectedMusic==nil ? "이 서클의 편집으로 돌아가기":"이 서클의 "+contentName+" 편집으로 돌아가기"',
        'help:"이 서클의 "+contentName+" 편집으로 돌아가기"').replace(
        'case .settings:store.connectionsOpen=false;store.automationOpen=false;store.embeddedPlugin=nil;store.hierarchySettingsOpen=true',
        'case .settings:store.connectionsOpen=false;store.automationOpen=false;store.hierarchySettingsOpen=true')
    assert hashlib.sha256(prior.encode()).hexdigest() == compact_hashes[changed[0]]
    kit = app / 'Contents/Resources/Codex'
    files = json.loads((kit / 'manifest.json').read_text())['files']
    for name, digest in files.items():
        assert hashlib.sha256((kit / name).read_bytes()).hexdigest() == digest
    assert 'Executed 325 tests, with 0 failures' in (OUT / 'swift-tests-reviewed.log').read_text()
    assert 'Ran 26 tests' in (OUT / 'python-tests.log').read_text()
    screenshots = {}
    for path in sorted([*OUT.glob('final-*.jpg'), *OUT.glob('reviewed-*.jpg')]):
        raw = path.read_bytes()
        assert raw[:3] == b'\xff\xd8\xff'
        metadata = subprocess.check_output(['sips', '-g', 'pixelWidth', '-g', 'pixelHeight', str(path)], text=True)
        size = [int(re.search(label + r': (\d+)', metadata)[1]) for label in ['pixelWidth', 'pixelHeight']]
        assert size == [1019, 768], path.name
        screenshots[path.name] = dict(size=size, sha256=hashlib.sha256(raw).hexdigest())
    assert len(screenshots) >= 30
    result = dict(result='passed', restoredRevision=64, sourceFiles=len(hashes), kitFiles=len(files),
                  fileBackedSections=len(compiled), screenshots=screenshots,
                  scope='Native editor layout, input, navigation and restoration; no device playback or capture',
                  uuid=subprocess.check_output(['dwarfdump', '--uuid', str(app / 'Contents/MacOS/circlr')], text=True).strip())
    (FINAL / 'verification.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({k: v for k, v in result.items() if k != 'screenshots'}, ensure_ascii=False))


if __name__ == '__main__':
    main()
