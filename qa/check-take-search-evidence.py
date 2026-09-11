#!/usr/bin/env python3
"""Read-only build108 final3 evidence checker; final3 acceptance only; earlier checkpoints are excluded."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'qa/generated/take-search'
CANDIDATE = 'final3'
spec = importlib.util.spec_from_file_location('compact_checks', Path(__file__).with_name('check-midi-compact-evidence.py'))
c = importlib.util.module_from_spec(spec)
spec.loader.exec_module(c)


def load(name):
    return json.loads((OUT / (name + '.json')).read_text())


def selected_use(manifest, scenario):
    arrangement = next(a for a in manifest['arrangements'] if a['id'] == scenario['arrangementID'])
    return next(u for u in arrangement['uses'] if u['id'] == scenario['useID'])


def expected_take_manifest(baseline, scenario, shortened=False):
    expected = c.music(baseline)
    if shortened:
        take = next(t for t in expected['takes'] if t['id'] == scenario['visibleTakeIDs'][1])
        assert take['lane']['audio'][0]['id'] == scenario['sameClipID']
        assert take['lane']['audio'][0]['duration'] == 16
        selected_use(expected, scenario)['laneOverrides'][scenario['laneID']] = copy.deepcopy(take['lane'])
    return expected


def check_capture(name, package, revision, expected, baseline):
    capture = load(CANDIDATE + '/' + name)
    c.guard(capture, package, revision)
    assert c.music(capture['manifest']) == expected, name
    assert capture['manifest']['takes'] == baseline['takes'], name
    return capture


def check_preserved_files(package, baseline, scenario):
    fixture = Path(package['fixture'])
    source = Path(scenario['source'])
    assert hashlib.sha256((source / 'manifest.json').read_bytes()).hexdigest() == scenario['fixtureSourceSHA256']
    studio = fixture.with_name('studio.circlr')
    assert hashlib.sha256((studio / 'manifest.json').read_bytes()).hexdigest() == package['sourceSHA256']
    for asset in baseline['assets']:
        relative = Path(asset['path'])
        assert not relative.is_absolute() and '..' not in relative.parts
        for root in [fixture, source, studio]:
            assert hashlib.sha256((root / relative).read_bytes()).hexdigest() == asset['checksum']


def check_reopen(package, restored, reopened, revision):
    fixture = Path(package['fixture'])
    assert restored['manifest'] == reopened['manifest'] == json.loads((fixture / 'manifest.json').read_text())
    # The native open reply pair was not persisted as separate evidence files.
    # Validate only the actual reopened snapshot and its saved job state.
    job = reopened['state']['job']
    assert reopened['state']['revision'] == revision
    assert job['kind'] == 'open' and job['state'] == 'completed'
    assert job['path'] == str(fixture) and job['progress'] == 1


def expected_split(baseline, observed, scenario):
    expected = c.music(baseline)
    base_use = selected_use(expected, scenario)
    actual = selected_use(observed, scenario)
    section = next(s for s in expected['sections'] if s['id'] == base_use['sectionID'])
    lane = copy.deepcopy(next(l for l in section['lanes'] if l['id'] == scenario['laneID']))
    clip = lane['audio'][0]
    assert clip['duration'] == 32 and clip['sourceStart'] == 0 and clip['beat'] == 0
    actual_clips = actual['laneOverrides'][lane['id']]['audio']
    assert len(actual_clips) == 2 and actual_clips[0]['id'] == clip['id']
    new_clip_id = actual_clips[1]['id']
    assert new_clip_id != clip['id']
    import uuid
    uuid.UUID(new_clip_id)
    clip['duration'] = 16
    clip['renderWindow'] = dict(automaticEdges=False, cycleBeat=0, duration=32, envelopes=[], sourceStart=0)
    latter = copy.deepcopy(clip); latter.update(id=new_clip_id, beat=32, sourceStart=16)
    lane['audio'] = [clip, latter]
    base_use['laneOverrides'][lane['id']] = lane
    graph = base_use['graphEdits']; observed_graph = actual['graphEdits']
    old_node_ids = {n['id'] for n in graph['addedNodes']}
    added = [n for n in observed_graph['addedNodes'] if n['id'] not in old_node_ids]
    assert len(added) == 1
    new_id = added[0]['id']; uuid.UUID(new_id)
    assert new_id not in {n['id'] for n in section['graph']['nodes']}
    source_node = next(n for n in section['graph']['nodes'] if n['id'] == scenario['audioNodeID'])
    node = copy.deepcopy(source_node); node.update(id=new_id, name=source_node['name'] + ' · 뒤')
    node['content']['audio']['clipID'] = new_clip_id
    graph['addedNodes'].append(node)
    original_edge = next(e for e in section['graph']['edges'] if e['from'] == source_node['id'])
    new_edges = [e for e in observed_graph['addedEdges'] if e['id'] not in {x['id'] for x in graph['addedEdges']}]
    assert len(new_edges) == 1
    edge_id = new_edges[0]['id']; uuid.UUID(edge_id)
    edge = copy.deepcopy(original_edge); edge.update(id=edge_id, **{'from': new_id})
    graph['addedEdges'].append(edge)
    position = graph['layout']['positions'][source_node['id']]
    graph['layout']['positions'][new_id] = dict(x=position['x'] + 90, y=position['y'] + 130)
    group = next(g for g in graph['layout']['groups'] if source_node['id'] in g['members'])
    group['members'].append(new_id)
    return expected


def ax(name):
    return (OUT / CANDIDATE / (name + '.ax.txt')).read_text()


def take_rows(name):
    return [line for line in ax(name).splitlines() if 'button' in line and '녹음 테이크, 노트' in line]


def check_search_ax():
    for name, selected in [('shortcut', 0), ('second-selected', 1)]:
        rows = take_rows(name)
        assert len(rows) == 3
        for index, row in enumerate(rows):
            assert ('(selected)' in row) == (index == selected)
            assert ('현재 내용과 일치' in row) == (index == 0)
            assert ('노트 1개' if index == 2 else '노트 0개') in row and '클립 1개' in row
        assert 'search text field' in ax(name).split('The focused UI element is')[-1]
    current = take_rows('current-filter')
    assert len(current) == 1 and '현재 내용과 일치' in current[0]
    assert 'Value: 현재' in ax('current-filter')
    assert not take_rows('empty') and '일치하는 테이크가 없습니다' in ax('empty')
    assert 'Value: 없는테이크' in ax('empty')
    for name in ['shortcut', 'second-selected', 'current-filter', 'empty']:
        assert (OUT / CANDIDATE / (name + '.jpg')).read_bytes().startswith(b'\xff\xd8\xff')


def main():
    baseline_package = load('baseline/package')
    baseline = load('baseline/baseline')
    scenario = load('baseline/scenario')
    assert baseline_package['build'] == '107'
    c.guard(baseline, baseline_package, 22)
    assert baseline['manifest']['takes'] == load('baseline/fixture-initial')['takes']
    assert len(baseline['manifest']['takes']) == 5 and len(scenario['visibleTakeIDs']) == 3
    package = load(CANDIDATE + '/package')
    assert package['build'] == '108' and package['fixture'] == baseline_package['fixture']
    captures = {}
    revisions = {'shortcut':26, 'applied':27, 'search-cancelled':27, 'undo':28, 'split':29, 'split-undo':30, 'stale':30, 'restored':30, 'reopened':30}
    for name, revision in revisions.items():
        expected = expected_take_manifest(baseline['manifest'], scenario, name in ['applied', 'search-cancelled'])
        if name == 'split':
            expected = expected_split(baseline['manifest'], load(CANDIDATE + '/split')['manifest'], scenario)
        captures[name] = check_capture(name, package, revision, expected, baseline['manifest'])
    check_search_ax()
    check_preserved_files(package, baseline['manifest'], scenario)
    for name in ['command-entry', 'header']:
        rows = take_rows(name)
        assert len(rows) == 3 and '(selected)' in rows[0] and '현재 내용과 일치' in rows[0]
    assert 'Value: 녹음 테이크' in ax('command-filter') and '명령 또는 서클 이름 검색' in ax('command-filter')
    assert 'search text field' in ax('command-entry').split('The focused UI element is')[-1]
    assert '편집 대상이 바뀌었습니다. 테이크 검색을 다시 여세요' in ax('stale')
    assert not take_rows('stale')
    changed_selection = captures['stale']['state']['selection']['music']
    assert changed_selection['nodeID'] == '8E30C634-08A5-5F38-9135-26EF84C21DB5'
    assert captures['restored']['state']['selection']['music']['nodeID'] == scenario['audioNodeID']
    check_reopen(package, captures['restored'], captures['reopened'], 30)
    print(json.dumps(dict(status='passed', candidate=CANDIDATE, baselineSnapshots=1,
        finalSnapshots=len(captures), preservedTakes=5, scopedTakes=3, assets=2,
        keyboardSelectionStateVerified=True, splitShortcutPreserved=True,
        staleTargetRejected=True, strictReopenEquality=True, physicalAudioAttempts=0)))


if __name__ == '__main__':
    main()
