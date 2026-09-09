#!/usr/bin/env python3
"""Check build 52's local native captures, source identity, and preserved media."""
import copy
import hashlib
import json
from pathlib import Path
import plistlib
import re
import runpy
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'qa/generated/library-batch'
KEYS = ['name', 'global', 'tracks', 'sections', 'arrangements', 'assets', 'patterns', 'signal', 'portLayout', 'circleLayout']
CASES = {'baseline': 14, 'range-two': 14, 'mixed-rejected': 14, 'broken-rejected': 14,
         'imported': 15, 'undone': 16, 'redone': 17, 'reopened': 17, 'folders-removed': 17}


def read(name):
    return json.loads((OUT / (name + '.json')).read_text())


def music(project):
    result = {k: copy.deepcopy(project[k]) for k in KEYS}
    result['portLayout'].pop('revision', None)
    return result


def ax(name):
    return (OUT / (name + '.ax.txt')).read_text()


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


if __name__ == '__main__':
    captures = {name: read(name) for name in CASES}
    initial = captures['baseline']['manifest']
    imported = captures['imported']['manifest']
    for name, revision in CASES.items():
        s = captures[name]['state']
        assert s['projectID'] == '51ABBBAD-3FF7-5795-8B93-8D04F89DC8B7' and s['revision'] == revision, name
        assert s['runtime']['bundleID'] == 'com.circlr.integrationqa' and not s['dirty']
        assert s['output']['attempts'] == s['audition']['attempts'] == 0
        assert not s['recording']['busy'] and not s['recording']['midi'] and not s['playback']['playing']
        assert not any(s['library'][k] for k in ['scanning', 'searching', 'previewPending', 'previewPlaying', 'previewPreparing'])
        if 'manifest' in captures[name]:
            expected = initial if name in ['baseline', 'mixed-rejected', 'broken-rejected', 'undone'] else imported
            assert music(captures[name]['manifest']) == music(expected), name
    assert len(imported['tracks']) == 5 and imported['tracks'][:3] == initial['tracks']
    assert len(imported['assets']) == 4 and imported['assets'][:2] == initial['assets']
    for key in ['name', 'global', 'sections', 'patterns', 'portLayout', 'circleLayout']:
        assert imported[key] == initial[key], key
    original_use, other_use = initial['arrangements'][0]['uses']
    current_use, current_other = imported['arrangements'][0]['uses']
    assert current_other == other_use
    for key in original_use:
        if key not in ['addedLanes', 'graphEdits']:
            assert current_use[key] == original_use[key], key
    assert current_use['addedLanes'][:1] == original_use['addedLanes']
    assert len(current_use['addedLanes']) == 3
    for lane, track, asset, expected_name in zip(current_use['addedLanes'][1:], imported['tracks'][3:],
                                                  imported['assets'][2:], ['Batch kick.wav', 'Batch pad.wav']):
        assert track['name'] == asset['name'] == expected_name
        assert lane['trackID'] == track['id'] and lane['notes'] == [] and len(lane['audio']) == 1
        clip = lane['audio'][0]
        assert clip['assetID'] == asset['id'] and clip['beat'] == clip['sourceStart'] == 0
        assert clip['duration'] == asset['duration'] == 32 and clip['sourceBPM'] == 120
    assert captures['range-two']['state']['library']['selectedFiles'] == 2
    for name, count in [('range-two', 2), ('range-one', 1), ('checkbox-two', 2), ('cleared', 0),
                        ('all-two', 2), ('filter-one', 1), ('folder-a-removed', 1), ('folders-removed', 0)]:
        content = ax(name)
        assert f'{count}개 선택' in content
        assert len(re.findall(r'checkbox Description: .*가져오기 선택, Value: 1', content)) == count
    assert '(disabled) 0개 가져오기 · Return' in ax('cleared')
    assert '새 트랙 2개 · 0박' in ax('import-ready')
    for name in ['mixed-disabled', 'mixed-return']:
        assert 'MIDI는 한 파일씩 가져옵니다. 오디오와 따로 선택하세요' in ax(name)
        assert '(disabled) 2개 가져오기 · Return' in ax(name)
    assert '가져오기 실패:' in ax('mixed-return')
    assert 'MIDI 트랙 선택 →' in ax('midi-single')
    assert 'MIDI 노트 가져오기' in ax('midi-preview') and '1개 노트 · 채널 1' in ax('midi-preview')
    assert '오디오 가져오기 실패: 오디오를 읽을 수 없습니다: broken.wav' in ax('broken-rejected')
    assert 'Batch kick.wav' in ax('imported') and 'Batch pad.wav' in ax('imported')
    assert 'MCP 연결 가능 r16' in ax('undone') and 'MCP 연결 가능 r17' in ax('reopened')
    restored = captures['folders-removed']['state']['library']
    assert restored['folders'] == 1 and restored['files'] == 4 and restored['selectedFiles'] == 0
    assert '4개 파일' in ax('library-restored') and 'Batch kick.wav' not in ax('library-restored')
    fixture = Path.home() / 'Library/Application Support/circlr-integration-qa/fixtures/library-batch.circlr'
    source = fixture.with_name('studio.circlr')
    assert digest(source / 'manifest.json') == '12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d'
    assert music(json.loads((fixture / 'manifest.json').read_text())) == music(imported)
    for asset in imported['assets']:
        assert digest(fixture / asset['path']) == asset['checksum']
    for asset in initial['assets']:
        assert digest(source / asset['path']) == asset['checksum']
    samples = read('sample-hashes'); assert len(samples) == 4
    for name, expected in samples.items():
        assert digest(OUT / 'samples' / name) == expected
    app = OUT / '써클러 통합 검증.app'
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    assert (info['CFBundleVersion'], info['CFBundleShortVersionString'], info['CFBundleIdentifier']) == ('52', '0.20.0', 'com.circlr.integrationqa')
    sections = runpy.run_path(str(ROOT / 'qa/check-library-evidence.py'))['sections']
    compiled = sections(ROOT / '.build/integration-release/release/circlr')
    assert len(compiled) == 37 and compiled == sections(app / 'Contents/MacOS/circlr')
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    hashes = read('source-hashes'); assert len(hashes) == 7
    for name, expected in hashes.items():
        assert digest(ROOT / name) == expected
    kit = app / 'Contents/Resources/Codex'; files = json.loads((kit / 'manifest.json').read_text())['files']
    assert len(files) == 25
    for name, expected in files.items():
        assert digest(kit / name) == expected
    assert 'Executed 391 tests, with 0 failures' in (ROOT / '.build/library-batch-tests.log').read_text()
    assert 'Ran 26 tests' in (ROOT / '.build/library-batch-python.log').read_text()
    preserve = read('preservation')
    assert preserve['ownedQAProcesses'] == [] and preserve['userApp'] == ['0.19.0', '21']
    assert set(preserve['heads'].values()) == {'d88ea5d8d5d87cf49c5ef06154397c36ba1019d7', '1d304eb244f60a21c3598b89d05192d3512d719d'}
    result = dict(status='passed', revision=17, nativeSnapshots=len(captures),
                  axCaptures=len(list(OUT.glob('*.ax.txt'))), sourceFiles=len(hashes),
                  sampleFiles=len(samples), kitFiles=len(files), executableSections=len(compiled),
                  physicalAudioAttempts=0, voiceOverSpeech='not_verified',
                  screenshots={p.name: digest(p) for p in sorted(OUT.glob('*.jpg'))})
    (OUT / 'verification.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({k: v for k, v in result.items() if k != 'screenshots'}, ensure_ascii=False))
