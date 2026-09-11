#!/usr/bin/env python3
"""Check build 54's local native placement evidence, restoration and signed package."""
import copy
import hashlib
import json
from pathlib import Path
import plistlib
import runpy
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'qa/generated/library-placement'
FINAL = OUT / 'final'
KEYS = ['name', 'global', 'tracks', 'sections', 'arrangements', 'assets', 'patterns', 'signal', 'portLayout', 'circleLayout']
CASES = {'baseline': (14, 1, 1), 'target-chosen': (14, 2, 1), 'stale-draft': (15, 2, 1),
         'stale-restored': (16, 2, 1), 'final-baseline': (16, 2, 1), 'final-target': (16, 2, 1),
         'final-audio-imported': (17, 2, 1), 'final-audio-undone': (18, 2, 1),
         'final-midi-imported': (19, 2, 1), 'final-midi-undone': (20, 2, 1),
         'final-batch-imported': (21, 2, 2), 'final-batch-import-confirmed': (21, 2, 2),
         'final-batch-undone': (22, 2, 2), 'final-stale-draft': (23, 2, 2),
         'final-restored': (24, 2, 2), 'final-unregistered': (24, 1, 0), 'final-reopened': (24, 1, 0)}


def music(project):
    value = {k: copy.deepcopy(project[k]) for k in KEYS}
    value['portLayout'].pop('revision', None)
    return value


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def ax(name):
    return (FINAL / (name + '.ax.txt')).read_text()


if __name__ == '__main__':
    captures = {n: json.loads((OUT / (n + '.json')).read_text()) for n in CASES}
    initial = captures['baseline']['manifest']
    for name, (revision, folders, selected) in CASES.items():
        s = captures[name]['state']; p = captures[name]['manifest']
        assert s['projectID'] == 'E52594F7-E3C1-533A-96EB-3BCAB30A0B36' and s['revision'] == revision, name
        assert s['runtime']['bundleID'] == 'com.circlr.integrationqa' and not s['dirty']
        assert s['library']['folders'] == folders and s['library']['selectedFiles'] == selected
        assert s['library']['files'] == (4 if folders == 1 else 7)
        assert s['output']['attempts'] == s['audition']['attempts'] == 0
        assert not s['recording']['busy'] and not s['recording']['midi'] and not s['playback']['playing']
        assert not any(s['library'][k] for k in ['scanning', 'searching', 'previewPending', 'previewPlaying', 'previewPreparing'])
        if revision in (15, 23):
            expected = music(initial)
            expected['name'] = '통합 편집 검증 · ' + ('충돌 검사' if revision == 15 else '최종 충돌 검사')
            assert music(p) == expected, name
        elif revision not in (17, 19, 21):
            assert music(p) == music(initial), name
    for before, after in [('baseline', 'target-chosen'), ('final-baseline', 'final-target')]:
        assert captures[before]['state']['selection'] == captures[after]['state']['selection']
        assert captures[before]['manifest'] == captures[after]['manifest']
    for name in ['final-audio-imported', 'final-midi-imported', 'final-batch-imported']:
        p = captures[name]['manifest']
        assert p['sections'] == initial['sections'] and p['tracks'][:3] == initial['tracks'] and p['assets'][:2] == initial['assets']
        assert p['arrangements'][0]['uses'][0] == initial['arrangements'][0]['uses'][0]
    audio = captures['final-audio-imported']['manifest']
    assert len(audio['tracks']) == 3 and len(audio['assets']) == 3
    lanes = audio['arrangements'][0]['uses'][1]['laneOverrides']
    lane = lanes['C02E0506-5351-553D-992A-688B212C4D62']
    assert lane['trackID'] == '3F85A31A-4CB4-5F71-9426-C593B94AC1D5'
    assert lane['audio'][-1]['beat'] == 8.5 and lane['audio'][-1]['assetID'] == audio['assets'][-1]['id']
    midi = captures['final-midi-imported']['manifest']
    assert len(midi['tracks']) == 4 and len(midi['assets']) == 2
    assert midi['arrangements'][0]['uses'][1]['addedLanes'][-1]['notes'][0]['beat'] == 8.5
    batch = captures['final-batch-imported']['manifest']
    assert len(batch['tracks']) == 5 and len(batch['assets']) == 4
    for lane, asset in zip(batch['arrangements'][0]['uses'][1]['addedLanes'][1:], batch['assets'][2:]):
        assert lane['audio'][0]['beat'] == 3.5 and lane['audio'][0]['assetID'] == asset['id']
    hashes = json.loads((OUT / 'batch-media-hashes.json').read_text())
    assert len(hashes) == 4 and all(hashes[a['id']] == a['checksum'] for a in batch['assets'])
    assert 'Value: 공유, Placeholder: 가져올 곡 · 섹션 검색' in ax('section-match')
    assert '일치하는 섹션이 없습니다' in ax('section-empty')
    assert 'Value: Placement wav, Placeholder:' in ax('picker-cancelled') and '2개 선택' in ax('picker-cancelled')
    assert 'button (selected) 출력별 신호 검증 › 출력별 신호 검증' in ax('picker-up')
    assert 'button 2개 가져오기 · Return' in ax('target-refreshed')
    assert 'Help: 시작 위치는 대상 섹션 또는 패턴의 길이 안으로 지정하세요, Value: 65' in ax('outside-range')
    for name in ['start-committed', 'start-cancelled']:
        assert 'Value: 9.5' in ax(name) and '3마디 · 4.25초 / 64박 길이' in ax(name)
    assert '공유 출력 확인 › 출력 2 · 9.5박' in ax('audio-ready')
    assert 'MIDI 가져오기 시작 박, Help: Return으로 적용 · Esc로 취소, Value: 9.5' in ax('midi-preview')
    assert '새 트랙 2개 · 4.5박' in ax('batch-ready') and '가져올 오디오 트랙' not in ax('batch-ready')
    assert 'text field (disabled) Description: 라이브러리 가져오기 시작 박' in ax('stale-draft')
    assert '(disabled) 2개 가져오기 · Return' in ax('stale-draft') and '새 트랙 2개 · 1박' in ax('stale-draft')
    assert 'samples 등록 해제' in ax('unregistered') and 'inputs/Samples' not in ax('unregistered')
    fixture = Path.home() / 'Library/Application Support/circlr-integration-qa/fixtures/library-placement.circlr'
    source = fixture.with_name('studio.circlr')
    assert digest(source / 'manifest.json') == '12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d'
    assert music(json.loads((fixture / 'manifest.json').read_text())) == music(initial)
    for asset in initial['assets']:
        for folder in [source, fixture]:
            assert digest(folder / asset['path']) == asset['checksum']
    samples = json.loads((OUT / 'sample-hashes.json').read_text()); assert len(samples) == 3
    for name, expected in samples.items():
        assert digest(OUT / 'inputs/Samples' / name) == expected
    app = FINAL / '써클러 통합 검증.app'; info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    assert (info['CFBundleVersion'], info['CFBundleShortVersionString'], info['CFBundleIdentifier']) == ('54', '0.20.0', 'com.circlr.integrationqa')
    sections = runpy.run_path(str(ROOT / 'qa/check-library-evidence.py'))['sections']
    compiled = sections(ROOT / '.build/integration-release/release/circlr')
    assert len(compiled) == 37 and compiled == sections(app / 'Contents/MacOS/circlr')
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    sources = json.loads((FINAL / 'source-hashes.json').read_text()); assert len(sources) == 8
    for name, expected in sources.items():
        assert digest(ROOT / name) == expected
    kit = app / 'Contents/Resources/Codex'; files = json.loads((kit / 'manifest.json').read_text())['files']; assert len(files) == 25
    for name, expected in files.items():
        assert digest(kit / name) == expected
    assert 'Executed 401 tests, with 0 failures' in (ROOT / '.build/library-placement-tests.log').read_text()
    assert 'Ran 26 tests' in (ROOT / '.build/library-placement-python.log').read_text()
    assert '0 failures' in (ROOT / '.build/library-placement-final-numbers.log').read_text()
    preserve = json.loads((FINAL / 'preservation.json').read_text())
    assert preserve['ownedQAProcesses'] == [] and preserve['userApp'] == ['0.19.0', '21']
    assert set(preserve['heads'].values()) == {'d88ea5d8d5d87cf49c5ef06154397c36ba1019d7', '1d304eb244f60a21c3598b89d05192d3512d719d'}
    result = dict(status='passed', revision=24, nativeSnapshots=len(captures), finalNativeSnapshots=13,
                  finalAXCaptures=len(list(FINAL.glob('*.ax.txt'))), sourceFiles=len(sources), sampleFiles=3,
                  kitFiles=25, executableSections=37, physicalAudioAttempts=0, voiceOverSpeech='not_verified',
                  screenshots={p.name: digest(p) for p in sorted(FINAL.glob('*.jpg'))})
    (FINAL / 'verification.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({k: v for k, v in result.items() if k != 'screenshots'}, ensure_ascii=False))
