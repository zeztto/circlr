#!/usr/bin/env python3
"""Preparation-only check until native scenario evidence is finalized; never controls the app."""
import copy
import hashlib
import json
import math
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'qa/generated/workflow-visibility'


def main():
    package = json.loads((OUT / 'baseline/package.json').read_text())
    assert package['build'] == '96' and package['projectID'] == '68B5D3D0-07E9-5631-A611-ED78245A4C89'
    fixture = Path(package['fixture']); source = fixture.with_name('studio.circlr')
    manifest = json.loads((fixture / 'manifest.json').read_text())
    assert manifest['id'] == package['projectID'] and len(manifest['assets']) == 2
    assert hashlib.sha256((source / 'manifest.json').read_bytes()).hexdigest() == package['sourceSHA256'] == '12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d'
    for asset in manifest['assets']:
        path = Path(asset['path'])
        assert not path.is_absolute() and '..' not in path.parts
        for directory in [source, fixture]:
            assert hashlib.sha256((directory / path).read_bytes()).hexdigest() == asset['checksum']
    partial(package)


def music(value):
    value = copy.deepcopy(value)
    value.pop('hierarchyView', None); value.pop('musicRevision', None)
    value.pop('circleLayout', None)  # orbit/freeform is editor presentation, checked separately.
    colors = value.get('circleColors')
    if colors is not None:
        assert len(colors) % 2 == 0
        value['circleColors'] = {json.dumps(colors[i], sort_keys=True): colors[i+1] for i in range(0, len(colors), 2)}
        assert len(value['circleColors']) * 2 == len(colors)
    return value


def partial(package):
    directory = OUT / 'final'
    revisions = {'orbit': 14, 'tail-cancel': 14, 'note-edited': 15, 'note-undo': 16,
                 'one-note-deleted': 17, 'delete-undo': 17, 'delete-restored': 18,
                 'navigation-restored': 26, 'all-selected': 26, 'empty': 27, 'empty-undo': 28,
                 'step': 28, 'drum-step': 28, 'piano-roll': 28, 'bounced': 29,
                 'bounce-undo': 30, 'compact-midi': 30, 'saved': 30, 'reopened': 30}
    captures = {n: json.loads((directory / (n + '.json')).read_text()) for n in revisions}
    final_package = json.loads((directory / 'package.json').read_text())
    assert 'A2991ADB-048F-3EE2-B41E-3B731FB9B92E' in final_package['uuid']
    baseline = json.loads((OUT / 'baseline/orbit.json').read_text())
    assert baseline['state']['runtime']['build'] == '96'
    assert baseline['state']['runtime']['bundleID'] == 'com.circlr.integrationqa'
    assert baseline['state']['path'] == package['fixture'] and not baseline['state']['dirty']
    assert not baseline['state']['playback']['playing']
    assert not any(baseline['state']['recording'][k] for k in ['audio', 'midi', 'busy'])
    assert baseline['manifest']['musicRevision'] == 14
    assert baseline['state']['projectID'] == package['projectID'] and baseline['state']['revision'] == 14
    assert baseline['state']['output']['attempts'] == baseline['state']['audition']['attempts'] == 0
    original = music(captures['orbit']['manifest'])
    assert music(baseline['manifest']) == original
    note_id = 'BA8C30C3-3F0E-482A-A108-7A9C829C96AE'
    notes = original['arrangements'][0]['uses'][0]['addedLanes'][0]['notes']
    assert len(notes) == 3
    for name, capture in captures.items():
        state = capture['state']
        assert state['runtime']['bundleID'] == 'com.circlr.integrationqa' and state['runtime']['build'] == '97'
        assert state['projectID'] == capture['manifest']['id'] == package['projectID']
        assert state['path'] == package['fixture'] and not state['dirty']
        assert state['revision'] == capture['manifest']['musicRevision'] == revisions[name]
        assert state['output']['attempts'] == state['audition']['attempts'] == 0
        assert not state['playback']['playing'] and not any(state['recording'][k] for k in ['audio', 'midi', 'busy'])
        expected = copy.deepcopy(original)
        lane = expected['arrangements'][0]['uses'][0]['addedLanes'][0]
        if name == 'note-edited':
            note = next(n for n in lane['notes'] if n['id'] == note_id)
            assert note['pitch'] == 66; note['pitch'] = 67
        elif name in ['one-note-deleted', 'delete-undo']:
            lane['notes'] = [n for n in lane['notes'] if n['id'] != note_id]
        elif name == 'empty':
            lane['notes'] = []
        if name == 'bounced':
            expected = bounce_expected(original, capture, Path(package['fixture']))
        assert music(capture['manifest']) == expected, name
    assert captures['orbit']['manifest']['circleLayout'] == 'orbit'
    assert captures['piano-roll']['manifest']['circleLayout'] == 'freeform'
    assert set(captures['all-selected']['state']['selectedNoteIDs']) == {n['id'] for n in notes}
    assert captures['saved']['manifest'] == captures['reopened']['manifest']
    assert json.loads((Path(package['fixture']) / 'manifest.json').read_text()) == captures['reopened']['manifest']
    assert captures['reopened']['state']['job']['kind'] == 'open' and captures['reopened']['state']['job']['state'] == 'completed'
    assert captures['compact-midi']['state']['view']['consoleBounds'][3] == 110.5
    ax_checks = {'midi-menu': ['MIDI 파일 가져오기', 'MIDI 저장', '전체 선택 · ⌘A'],
                 'compact-midi': ['MIDI 편집 방식', '바운스 · 통합 키보드', 'Description: MIDI 녹음'],
                 'empty': ['0개 노트 표시', 'button (disabled) Description: 이전 MIDI 노트', 'button (disabled) Description: 다음 MIDI 노트'],
                 'drum-step': ['드럼 행 검색'], 'piano-roll': ['피아노 롤 · Tab 노트 선택'],
                 'orbit': ['3개 노트 표시']}
    for name, strings in ax_checks.items():
        text = (directory / (name + '.ax.txt')).read_text()
        for string in strings: assert string in text, (name, string)
    print(json.dumps({'status': 'passed', 'axChecked': len(ax_checks), 'nativeSnapshots': len(captures)+1, 'preservedAssets': 2,
                      'offlineBounceAssets': 1, 'physicalAudioAttempts': 0, 'packageUUID': final_package['uuid']}))


def bounce_expected(original, capture, fixture):
    expected = copy.deepcopy(original); actual = capture['manifest']
    asset = actual['assets'][-1]
    assert asset == {'checksum': '7fcfb393e3298da2c6b3fa782f1b9f1b69b5e5d26028d2aa5eea2526ba0cb566',
                     'duration': 34, 'id': '2E3F44A6-1B38-4BD5-8DA8-6F4C4B8D91E6',
                     'name': '통합 키보드 바운스', 'path': 'media/2E3F44A6-1B38-4BD5-8DA8-6F4C4B8D91E6.wav', 'sampleRate': 48000}
    path = OUT / 'final/bounce.wav'
    assert hashlib.sha256(path.read_bytes()).hexdigest() == asset['checksum']
    with wave.open(str(path), 'rb') as reader:
        assert (reader.getnchannels(), reader.getsampwidth(), reader.getframerate(), reader.getnframes()) == (2, 3, 48000, 1632000)
        data = reader.readframes(reader.getnframes())
    peak = 0; squares = 0
    for i in range(0, len(data), 3):
        value = int.from_bytes(data[i:i+3], 'little', signed=True)
        peak = max(peak, abs(value)); squares += value * value
    peak /= 8388608; rms = math.sqrt(squares / (len(data)//3)) / 8388608
    assert math.isclose(peak, 0.0951693, abs_tol=1e-6) and math.isclose(rms, 0.0095503, abs_tol=1e-6)
    job = capture['state']['job']
    assert job['kind'] == 'bounce' and job['state'] == 'completed' and job['renderedSeconds'] == 34
    use = expected['arrangements'][0]['uses'][0]; actual_use = actual['arrangements'][0]['uses'][0]
    node_id = 'BCCB7A58-B92B-47A4-A2C9-3C1EECD3E6CC'; track_id = '7E0D9016-E91D-4325-B807-033F233E32EA'
    lane = actual_use['addedLanes'][-1]
    assert lane == {'id': 'D15E1371-E4DA-487D-BA12-4863A87656A4', 'trackID': track_id, 'notes': [],
                    'audio': [{'assetID': asset['id'], 'beat': 0, 'duration': 34, 'followsTempo': False, 'gain': 1,
                               'id': '70C2DC16-AEB2-4A02-B1BC-CFB3C26D8CD5', 'preservesTail': True, 'sourceBPM': 120, 'sourceStart': 0}]}
    edits = use['graphEdits']; old_edge = copy.deepcopy(edits['addedEdges'][4])
    assert old_edge['from'] == 'mix:' + track_id and old_edge['to'] == 'output:' + track_id
    node = actual_use['graphEdits']['addedNodes'][-1]
    assert node == {'id': node_id, 'name': asset['name'], 'gain': 1, 'muted': False, 'repeatCount': 1, 'startBeat': 0,
                    'settings': {k: {'source': 'inherit'} for k in ['beatGrid','meter','rhythm','scale','tempo']},
                    'content': {'audio': {'clipID': lane['audio'][0]['id'], 'laneID': lane['id']}},
                    'bounce': {'bodySeconds': 32, 'outputNodeID': old_edge['to'], 'replacedInputs': [old_edge], 'sourceRevision': 28, 'tailSeconds': 2}}
    edits['addedEdges'][4]['from'] = node_id
    edits['addedEdges'][4]['id'] = 'F1289A57-2E62-48D3-964F-7E288EACA868'
    edits['addedNodes'].append(node); edits['layout']['positions'][node_id] = {'x': 170, 'y': -220}
    use['addedLanes'].append(lane); expected['assets'].append(asset)
    return expected


if __name__ == '__main__':
    main()
