#!/usr/bin/env python3
"""Check track shortcut selection and authored project preservation; no app calls."""
import copy
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'qa/generated/track-shortcut'


def load(name):
    return json.loads((OUT / (name + '.json')).read_text())


def music(value):
    value = copy.deepcopy(value); value.pop('hierarchyView', None)
    colors = value.get('circleColors')
    if colors is not None:
        assert len(colors) % 2 == 0
        value['circleColors'] = {json.dumps(colors[i], sort_keys=True): colors[i+1] for i in range(0, len(colors), 2)}
        assert len(value['circleColors']) * 2 == len(colors)
    return value


def main():
    names = ['baseline/' + n for n in ['before', 'candidates-connected', 'prepared', 'shortcut-source', 'shortcut-effect']]
    names += ['final/' + n for n in ['before', 'disconnected-opened', 'effect-opened', 'single-instrument',
                                    'empty-return', 'midi-opened', 'saved', 'reopened']]
    captures = {n: load(n) for n in names}; scenario = load('scenario'); package = load('final/package')
    m = lambda n: captures[n]['manifest']
    prepared = music(m('baseline/prepared'))
    for name, capture in captures.items():
        s = capture['state']
        assert s['projectID'] == package['projectID'] == capture['manifest']['id']
        assert s['runtime']['build'] == ('88' if name.startswith('baseline/') else '89')
        assert s['runtime']['bundleID'] == 'com.circlr.integrationqa'
        assert s['revision'] == capture['manifest']['musicRevision'] and not s['dirty']
        assert s['output']['attempts'] == s['audition']['attempts'] == 0
        assert not s['playback']['playing'] and not any(s['recording'][k] for k in ['audio', 'midi', 'busy'])
        if name not in ['baseline/before', 'baseline/candidates-connected']:
            assert music(capture['manifest']) == prepared, name
    baseline = music(m('baseline/before')); expected = copy.deepcopy(baseline)
    expected['musicRevision'] = prepared['musicRevision']
    expected['arrangements'][0]['uses'][0] = copy.deepcopy(prepared['arrangements'][0]['uses'][0])
    assert expected == prepared  # Setup is restricted to one use; tracks and source sections are unchanged.
    use = prepared['arrangements'][0]['uses'][0]
    section = next(s for s in prepared['sections'] if s['id'] == use['sectionID'])
    edits = use['graphEdits']
    assert len(scenario['effectNodeIDs']) == 2 and len(scenario['midiNodeIDs']) == 1
    copy_node = next(n for n in edits['addedNodes'] if n['id'] == scenario['copyNodeID'])
    assert 'audio' in copy_node['content']
    nodes = {n['id']: n for n in section['graph']['nodes'] + edits['addedNodes']}
    nodes.update(edits['nodeOverrides'])
    edges = {e['id']: e for e in section['graph']['edges'] + edits['addedEdges']}
    edges.update(edits['edgeOverrides'])
    edges = [e for k, e in edges.items() if k not in edits['removedEdgeIDs'] and not e['sidechain']]
    assert not any(e['from'] == scenario['copyNodeID'] for e in edges)
    # Navigation currently follows node-level adjacency through the shared router.
    # This is not an assertion about port-specific DSP audio ownership.
    for effect in scenario['effectNodeIDs']:
        todo = [effect]; seen = set()
        while todo:
            current = todo.pop()
            if current in seen: continue
            seen.add(current); todo.extend(e['to'] for e in edges if e['from'] == current)
        tracks = {nodes[n]['content']['output']['trackID'] for n in seen if 'output' in nodes[n]['content']}
        assert scenario['trackID'] in tracks and '3F85A31A-4CB4-5F71-9426-C593B94AC1D5' in tracks
    expected_nodes = {'baseline/shortcut-source': scenario['sourceNodeID'],
                      'baseline/shortcut-effect': scenario['effectNodeIDs'][1],
                      'final/disconnected-opened': scenario['copyNodeID'],
                      'final/effect-opened': scenario['effectNodeIDs'][0],
                      'final/single-instrument': 'instrument:' + scenario['trackID'],
                      'final/midi-opened': scenario['midiNodeIDs'][0],
                      'final/empty-return': 'midi:055F3787-2B9D-4DD1-9752-56106F8D94F5'}
    for name, node in expected_nodes.items():
        assert captures[name]['state']['selection'] == {'music': {'arrangementID': scenario['arrangementID'], 'useID': scenario['useID'], 'nodeID': node}}, name
    ax = lambda n: (OUT / 'final' / (n + '.ax.txt')).read_text()
    for file, text in [('source-search', '3개 결과'), ('source-search', '(selected) MIDI·오디오'),
                       ('effect-search', '2개 결과'), ('other-track-effect', '2 · 출력 2'),
                       ('other-track-effect', '2개 결과'), ('empty-effect', '3 · 통합 키보드'),
                       ('empty-effect', '0개 결과'), ('empty-effect', '이 트랙에 이펙트 작업이 없습니다'),
                       ('audio-button-search', '2개 결과'), ('midi-filter', '1개 결과'),
                       ('find-current', '(selected) 전체 종류'), ('find-current', '전체 앨범 31개 결과')]:
        assert text in ax(file), (file, text)
    assert '미연결' in ax('source-search')
    reopened = copy.deepcopy(m('final/reopened'))
    editor = reopened['hierarchyView']['workspace'].pop('editor')
    assert editor == {'audio': {}, 'orbit': {'barsPerPage': 4, 'page': 0, 'pitchRows': 12, 'topPitch': 71},
                      'scrolls': {}, 'steps': {'drumMode': False, 'extraPitches': [], 'newPitch': 36,
                                             'page': 0, 'rowQuery': '', 'subdivisions': 4}, 'topPitch': 72}
    assert reopened == m('final/saved')  # Reopen materialized only this previously absent default editor state.
    fixture = Path(package['fixture']); source = fixture.with_name('studio.circlr')
    assert music(json.loads((fixture / 'manifest.json').read_text())) == prepared
    assert hashlib.sha256((source / 'manifest.json').read_bytes()).hexdigest() == package['sourceSHA256'] == '12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d'
    assert len(prepared['assets']) == 2
    for asset in prepared['assets']:
        for folder in [fixture, source]:
            assert hashlib.sha256((folder / asset['path']).read_bytes()).hexdigest() == asset['checksum']
    print(json.dumps({'status': 'passed', 'nativeSnapshots': len(names), 'preservedAssets': 2,
                      'physicalAudioAttempts': 0, 'packageUUID': package['uuid']}, ensure_ascii=False))


if __name__ == '__main__':
    main()
