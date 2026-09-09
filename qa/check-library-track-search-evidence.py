#!/usr/bin/env python3
"""Audit build 58 search-only state, real audio import history and signed native evidence."""
import copy
import hashlib
import json
from pathlib import Path
import plistlib
import runpy
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'qa/generated/library-track-search'
CASES = {'baseline': 14, 'selection-only': 14, 'stale-before': 15, 'stale-after': 15,
         'before-import': 16, 'imported': 17, 'import-undone': 18, 'import-redone': 19,
         'imported-reopened': 19}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def document(value):
    value = copy.deepcopy(value)
    value.pop('musicRevision'); value.pop('hierarchyView')
    return value


def ax(name):
    return (OUT / (name + '.ax.txt')).read_text()


if __name__ == '__main__':
    captures = {n: json.loads((OUT / (n + '.json')).read_text()) for n in CASES}
    baseline = captures['baseline']['manifest']
    initial = document(baseline)
    assert len(initial['tracks']) == 99 and len(initial['assets']) == 2
    assert initial['tracks'][96]['name'] == initial['tracks'][97]['name'] == 'Nordic 패드'
    changed = copy.deepcopy(initial); changed['name'] = '검색 요청 충돌 검증'
    imported = document(captures['imported']['manifest'])
    track = initial['tracks'][98]
    original_use = initial['arrangements'][0]['uses'][0]
    imported_use = imported['arrangements'][0]['uses'][0]
    original_graph = original_use['graphEdits']; imported_graph = imported_use['graphEdits']
    assert imported_use['addedLanes'][:-1] == original_use['addedLanes']
    lane = imported_use['addedLanes'][-1]
    assert lane['trackID'] == track['id'] and lane['notes'] == [] and len(lane['audio']) == 1
    clip = lane['audio'][0]
    assert clip['beat'] == 8.5 and clip['sourceStart'] == 0 and clip['duration'] == 32
    assert len(imported['assets']) == 3 and imported['assets'][:2] == initial['assets']
    asset = imported['assets'][-1]
    assert asset['id'] == clip['assetID'] and asset['name'] == 'Nordic pad.wav'
    sample = ROOT / 'qa/generated/library-editing/samples/Textures/Nordic pad.wav'
    assert digest(sample) == asset['checksum']
    audio_id = 'audio:' + clip['id']; mix_id = 'mix:' + track['id']
    rhythm_id = 'rhythm-audio:' + track['id']; output_id = 'output:' + track['id']
    nodes = imported_graph['addedNodes'][len(original_graph['addedNodes']):]
    assert imported_graph['addedNodes'][:len(original_graph['addedNodes'])] == original_graph['addedNodes']
    assert len(nodes) == 4
    assert {n['id']: n['content'] for n in nodes} == {
        audio_id: {'audio': {'laneID': lane['id'], 'clipID': clip['id']}},
        mix_id: {'mix': {}}, rhythm_id: {'rhythmAudio': {'trackID': track['id']}},
        output_id: {'output': {'trackID': track['id']}}}
    assert all(n['gain'] == 1 and not n['muted'] and n['repeatCount'] == 1 for n in nodes)
    edges = imported_graph['addedEdges'][len(original_graph['addedEdges']):]
    assert imported_graph['addedEdges'][:len(original_graph['addedEdges'])] == original_graph['addedEdges']
    assert edges == [dict(id=a+'>'+b, **{'from': a, 'to': b}, gain=1, sidechain=False, signal='audio')
                     for a, b in [(audio_id, mix_id), (rhythm_id, mix_id), (mix_id, output_id)]]
    expected = copy.deepcopy(initial)
    expected['assets'].append(asset)
    expected_use = expected['arrangements'][0]['uses'][0]
    expected_use['addedLanes'].append(lane)
    expected_graph = expected_use['graphEdits']
    expected_graph['addedNodes'] += nodes; expected_graph['addedEdges'] += edges
    new_positions = {k: v for k, v in imported_graph['layout']['positions'].items()
                     if k not in original_graph['layout']['positions']}
    assert set(new_positions) == {audio_id, mix_id, rhythm_id, output_id}
    expected_graph['layout']['positions'].update(new_positions)
    assert imported == expected  # Other use, source lanes, routing and all preferences are unchanged.
    clean_before = {'baseline', 'selection-only', 'stale-after', 'imported-reopened'}
    for name, revision in CASES.items():
        capture = captures[name]; state = capture['state']; project = capture['manifest']
        assert state['projectID'] == 'BD041572-0833-5A03-9049-976D33EBDC07'
        assert state['revision'] == project['musicRevision'] == revision, name
        assert not state['dirty'] and capture['beforeSave']['dirty'] == (name not in clean_before), name
        assert state['output']['attempts'] == state['audition']['attempts'] == 0
        assert not state['recording']['busy'] and not state['recording']['midi'] and not state['playback']['playing']
        assert state['runtime']['bundleID'] == 'com.circlr.integrationqa'
        assert state['library']['folders'] == 1 and not state['library']['previewPlaying']
        wanted = changed if name in ['stale-before', 'stale-after'] else imported if name in ['imported', 'import-redone', 'imported-reopened'] else initial
        assert document(project) == wanted, name
    assert captures['imported-reopened']['manifest'] == captures['import-redone']['manifest']
    for name, ordinal in [('files-start', '2 · 출력 2'), ('duplicate-chosen', '98 · Nordic 패드'),
                          ('long-chosen', '99 · '+track['name']), ('escape-preserved', '99 · '+track['name']),
                          ('new-track-chosen', '새 트랙')]:
        text = ax(name)
        assert 'Value: Nordic, Placeholder: 파일명' in text and '1개 선택 현재 파일 · Nordic pad.wav' in text
        assert ordinal+' · 9.5박' in text and ordinal+' · 이름·번호로 대상 트랙 검색' in text
        assert any('Description: 라이브러리 가져오기 시작 박' in line and line.endswith('Value: 9.5') for line in text.splitlines())
    assert '100개 결과' in ax('track-current') and 'button (selected) 출력 2 · 2번 트랙' in ax('track-current')
    assert '2개 결과' in ax('duplicate-results')
    for number in [97, 98]:
        assert 'Nordic 패드 · '+str(number)+'번 트랙' in ax('duplicate-results')
    assert 'button (selected) Nordic 패드 · 98번 트랙' in ax('current-scrolled')
    assert 'scroll bar (settable, float) 1' in ax('current-scrolled')
    assert track['name']+' · 99번 트랙' in ax('long-result')
    assert '0개 결과' in ax('no-results') and '일치하는 트랙이 없습니다' in ax('no-results')
    assert '파일이나 대상이 변경됐습니다' in ax('stale-rejected')
    assert 'button (selected, disabled) '+track['name'] in ax('stale-rejected')
    assert any('Description: 오디오 배치 박' in line and line.endswith('Value: 9.5') for line in ax('imported').splitlines())
    fixture = Path(captures['baseline']['state']['path']); source = fixture.with_name('studio.circlr')
    assert digest(source / 'manifest.json') == '12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d'
    assert json.loads((fixture / 'manifest.json').read_text()) == baseline
    assert json.loads((OUT / 'fixture-reset.json').read_text())['manifest'] == baseline
    for item in imported['assets']:
        assert digest(fixture / item['path']) == item['checksum']
    for item in initial['assets']:
        assert digest(source / item['path']) == item['checksum']
    app = OUT / '써클러 통합 검증.app'
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    assert (info['CFBundleVersion'], info['CFBundleShortVersionString'], info['CFBundleIdentifier']) == ('58', '0.20.0', 'com.circlr.integrationqa')
    sections = runpy.run_path(str(ROOT / 'qa/check-library-evidence.py'))['sections']
    compiled = sections(ROOT / '.build/integration-release/release/circlr')
    assert len(compiled) == 37 and compiled == sections(app / 'Contents/MacOS/circlr')
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    sources = json.loads((OUT / 'source-hashes.json').read_text()); assert len(sources) == 6
    for name, expected_digest in sources.items():
        assert digest(ROOT / name) == expected_digest
    kit = app / 'Contents/Resources/Codex'; files = json.loads((kit / 'manifest.json').read_text())['files']
    assert len(files) == 25
    for name, expected_digest in files.items():
        assert digest(kit / name) == expected_digest
    for log, count in [('library-track-search-tests.log', 423), ('library-track-search-final-tests.log', 9)]:
        assert 'Executed '+str(count)+' tests, with 0 failures' in (ROOT / '.build' / log).read_text()
    assert 'Ran 26 tests' in (ROOT / '.build/library-track-search-python.log').read_text()
    preserve = json.loads((OUT / 'preservation.json').read_text())
    assert preserve['ownedQAProcesses'] == [] and preserve['userApp'] == ['0.19.0', '21']
    assert set(preserve['heads'].values()) == {'d88ea5d8d5d87cf49c5ef06154397c36ba1019d7', '1d304eb244f60a21c3598b89d05192d3512d719d'}
    for path, head in preserve['heads'].items():
        assert subprocess.check_output(['git', '-C', path, 'rev-parse', 'HEAD'], text=True).strip() == head
    processes = [line for line in subprocess.check_output(['ps', '-axo', 'pid=,command='], text=True).splitlines()
                 if len(line.split(None, 1)) == 2 and line.split(None, 1)[1].startswith(str(ROOT / 'qa/generated') + '/')
                 and '/Contents/MacOS/circlr' in line]
    assert not processes
    screenshots = {p.name: digest(p) for p in sorted(OUT.glob('*.jpg'))}
    assert len(screenshots) == len(list(OUT.glob('*.ax.txt'))) == 13
    result = dict(status='passed', nativeSnapshots=len(CASES), denseTracks=99, axCaptures=13,
                  screenshots=screenshots, sourceFiles=6, kitFiles=25, executableSections=37,
                  physicalAudioAttempts=0, fixtureReset='closed-app baseline copy')
    (OUT / 'verification.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({k: v for k, v in result.items() if k != 'screenshots'}, ensure_ascii=False))
