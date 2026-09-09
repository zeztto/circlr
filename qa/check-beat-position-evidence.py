#!/usr/bin/env python3
"""Check build 55's position units, raw document edits, restoration and package."""
import copy
import hashlib
import json
from pathlib import Path
import plistlib
import runpy
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'qa/generated/beat-position'
KEYS = ['name', 'global', 'tracks', 'sections', 'arrangements', 'assets', 'patterns', 'signal', 'portLayout', 'circleLayout']
CASES = {'baseline': 14, 'audio-edited': 15, 'audio-undone': 16, 'midi-edited': 17,
         'midi-modes-return': 17, 'layout-undo': 18, 'automation-edited': 20,
         'automation-stale': 21, 'automation-undone': 24, 'node-edited': 25, 'node-undone': 26,
         'edits-restored': 28, 'audio-imported': 29, 'audio-import-undone': 30,
         'midi-imported': 31, 'restored': 32, 'unregistered': 32, 'reopened': 32, 'linear-reopened': 32}


def music(project):
    value = {k: copy.deepcopy(project[k]) for k in KEYS}
    value['portLayout'].pop('revision', None)
    return value


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def ax(name):
    return (OUT / (name + '.ax.txt')).read_text()


def field(name, title, value):
    assert any('Description: ' + title + ', Help:' in line and line.endswith('Value: ' + value)
               for line in ax(name).splitlines()), (name, title, value)


if __name__ == '__main__':
    captures = {n: json.loads((OUT / (n + '.json')).read_text()) for n in CASES}
    initial = music(captures['baseline']['manifest'])
    midi = copy.deepcopy(initial)
    midi['arrangements'][0]['uses'][0]['addedLanes'][0]['notes'][0]['beat'] = 8.5
    orbital = copy.deepcopy(midi); orbital['circleLayout'] = 'orbit'
    audio = copy.deepcopy(initial)
    lane = copy.deepcopy(next(l for l in initial['sections'][0]['lanes'] if l['id'] == 'C02E0506-5351-553D-992A-688B212C4D62'))
    lane['audio'][0]['beat'] = 8.5
    audio['arrangements'][0]['uses'][0]['laneOverrides'][lane['id']] = lane
    node_id = '8E30C634-08A5-5F38-9135-26EF84C21DB5'
    original_node = next(n for n in initial['sections'][0]['graph']['nodes'] if n['id'] == node_id)
    automation = copy.deepcopy(orbital)
    curve = captures['automation-edited']['manifest']['arrangements'][0]['uses'][0]['graphEdits']['nodeOverrides'][node_id]['automation']
    assert len(curve) == 1 and curve[0]['enabled'] and curve[0]['parameter'] == 'gain'
    assert len(curve[0]['points']) == 1 and curve[0]['points'][0]['beat'] == 8.5 and curve[0]['points'][0]['value'] == 1
    n = copy.deepcopy(original_node); n['automation'] = curve
    automation['arrangements'][0]['uses'][0]['graphEdits']['nodeOverrides'][node_id] = n
    stale = copy.deepcopy(automation); stale['name'] = '통합 편집 검증 · 위치 충돌'
    node = copy.deepcopy(orbital); n = copy.deepcopy(original_node); n['startBeat'] = 2.25
    node['arrangements'][0]['uses'][0]['graphEdits']['nodeOverrides'][node_id] = n
    variants = {'audio-edited': audio, 'midi-edited': midi, 'midi-modes-return': midi,
                'layout-undo': orbital, 'automation-edited': automation, 'automation-stale': stale,
                'automation-undone': orbital, 'node-edited': node, 'node-undone': orbital}
    for name, revision in CASES.items():
        s = captures[name]['state']; p = captures[name]['manifest']
        assert s['projectID'] == 'D2F41557-396B-5515-8537-EB56F8EFFAA5' and s['revision'] == revision, name
        assert s['runtime']['bundleID'] == 'com.circlr.integrationqa' and not s['dirty']
        folders = 2 if name in ['audio-imported', 'audio-import-undone', 'midi-imported', 'restored'] else 1
        files = 6 if folders == 2 else 4 if name in ['unregistered', 'reopened'] else 0
        assert s['library']['folders'] == folders and s['library']['files'] == files, name
        assert s['output']['attempts'] == s['audition']['attempts'] == 0
        assert not s['recording']['busy'] and not s['recording']['midi'] and not s['playback']['playing']
        assert not any(s['library'][k] for k in ['scanning', 'searching', 'previewPending', 'previewPlaying', 'previewPreparing'])
        assert p['sections'] == initial['sections'] and p['arrangements'][0]['uses'][1] == initial['arrangements'][0]['uses'][1]
        if name not in ['audio-imported', 'midi-imported']:
            assert music(p) == variants.get(name, initial), name
    imported = captures['audio-imported']['manifest']; assert len(imported['tracks']) == 3 and len(imported['assets']) == 3
    assert imported['tracks'] == initial['tracks'] and imported['assets'][:2] == initial['assets']
    lane = imported['arrangements'][0]['uses'][0]['laneOverrides']['C02E0506-5351-553D-992A-688B212C4D62']
    assert len(lane['audio']) == 2 and lane['audio'][-1]['beat'] == 8.5 and lane['audio'][-1]['duration'] == 2
    assert lane['audio'][-1]['assetID'] == imported['assets'][-1]['id']
    hashes = json.loads((OUT / 'import-media-hashes.json').read_text())
    assert len(hashes) == 3 and all(hashes[a['id']] == a['checksum'] for a in imported['assets'])
    imported = captures['midi-imported']['manifest']; assert len(imported['tracks']) == 4 and imported['assets'] == initial['assets']
    assert imported['tracks'][:3] == initial['tracks']
    lanes = imported['arrangements'][0]['uses'][0]['addedLanes']; assert len(lanes) == 2
    assert lanes[0] == initial['arrangements'][0]['uses'][0]['addedLanes'][0]
    assert len(lanes[-1]['notes']) == 1 and lanes[-1]['notes'][0]['beat'] == 8.5 and lanes[-1]['notes'][0]['length'] == 1
    for name in ['audio-first', 'midi-first', 'automation-first', 'node-first']:
        title = {'audio-first': '오디오 배치 박', 'midi-first': 'MIDI 시작 박', 'automation-first': '오토메이션 위치 박', 'node-first': '부모 안 시작 박'}[name]
        field(name, title, '1'); assert '첫 위치는 1박 · 4분음표 기준' in ax(name)
    field('audio-position-tab', '오디오 배치 박', '9.5'); field('audio-position-tab', '오디오 원본 시작 초', '0.000')
    for name in ['midi-position-tab', 'step-position', 'orbit-position', 'midi-cancelled']:
        field(name, 'MIDI 시작 박', '9.5'); field(name, 'MIDI 길이 박', '0.5')
    assert '입력 범위: 1–64.5 박' in ax('midi-outside')
    field('automation-position', '오토메이션 위치 박', '9.5')
    assert '9.5박 · 4.25초' in ax('automation-position') and '표시 위치 1–65박' in ax('automation-position')
    assert '표시 위치 1–65박' in ax('automation-linear')
    assert '편집 대상이 변경되었습니다. Esc로 취소한 뒤 다시 입력하세요' in ax('automation-stale')
    field('node-committed', '부모 안 시작 박', '3.25'); field('node-committed', '길이 박', '64')
    for name in ['audio-import-ready', 'midi-import-ready']:
        field(name, '라이브러리 가져오기 시작 박', '9.5')
    field('audio-import-editor', '오디오 배치 박', '9.5'); field('audio-import-editor', '오디오 원본 끝 초', '2.000')
    field('midi-import-preview', 'MIDI 가져오기 시작 박', '9.5')
    assert 'MIDI 시작 위치는 현재 섹션 안으로 지정하세요' in ax('midi-import-end-rejected')
    field('midi-import-before-end', 'MIDI 가져오기 시작 박', '64.9995')
    assert '끝 위치 65.9995박' in ax('midi-import-before-end')
    field('midi-import-editor', 'MIDI 시작 박', '9.5'); field('midi-import-editor', 'MIDI 길이 박', '1')
    field('reopened-first', 'MIDI 시작 박', '1')
    fixture = Path.home() / 'Library/Application Support/circlr-integration-qa/fixtures/beat-position.circlr'
    source = fixture.with_name('studio.circlr')
    assert digest(source / 'manifest.json') == '12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d'
    assert music(json.loads((fixture / 'manifest.json').read_text())) == initial
    for asset in initial['assets']:
        for folder in [source, fixture]: assert digest(folder / asset['path']) == asset['checksum']
    samples = json.loads((OUT / 'sample-hashes.json').read_text()); assert len(samples) == 2
    for name, expected in samples.items(): assert digest(OUT / 'inputs/Samples' / name) == expected
    app = OUT / '써클러 통합 검증.app'; info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    assert (info['CFBundleVersion'], info['CFBundleShortVersionString'], info['CFBundleIdentifier']) == ('55', '0.20.0', 'com.circlr.integrationqa')
    sections = runpy.run_path(str(ROOT / 'qa/check-library-evidence.py'))['sections']
    compiled = sections(ROOT / '.build/integration-release/release/circlr')
    assert len(compiled) == 37 and compiled == sections(app / 'Contents/MacOS/circlr')
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    sources = json.loads((OUT / 'source-hashes.json').read_text()); assert len(sources) == 17
    for name, expected in sources.items(): assert digest(ROOT / name) == expected
    kit = app / 'Contents/Resources/Codex'; files = json.loads((kit / 'manifest.json').read_text())['files']; assert len(files) == 25
    for name, expected in files.items(): assert digest(kit / name) == expected
    assert 'Executed 406 tests, with 0 failures' in (ROOT / '.build/beat-position-fixed-tests.log').read_text()
    assert 'Ran 26 tests' in (ROOT / '.build/beat-position-python.log').read_text()
    preserve = json.loads((OUT / 'preservation.json').read_text())
    assert preserve['ownedQAProcesses'] == [] and preserve['userApp'] == ['0.19.0', '21']
    assert set(preserve['heads'].values()) == {'d88ea5d8d5d87cf49c5ef06154397c36ba1019d7', '1d304eb244f60a21c3598b89d05192d3512d719d'}
    result = dict(status='passed', revision=32, nativeSnapshots=len(captures), axCaptures=len(list(OUT.glob('*.ax.txt'))),
                  sourceFiles=len(sources), kitFiles=25, executableSections=37, physicalAudioAttempts=0,
                  screenshots={p.name: digest(p) for p in sorted(OUT.glob('*.jpg'))})
    (OUT / 'verification.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({k: v for k, v in result.items() if k != 'screenshots'}, ensure_ascii=False))
