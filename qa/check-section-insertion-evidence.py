#!/usr/bin/env python3
"""Read preserved insertion snapshots without launching the app or audio."""
import copy
import ast
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'qa/generated/section-insertion'


def load(name):
    return json.loads((OUT / (name + '.json')).read_text())


def music(project):
    project = copy.deepcopy(project)
    project.pop('musicRevision', None); project.pop('hierarchyView', None)
    colors = project.get('circleColors')
    if colors is not None:
        assert len(colors) % 2 == 0
        project['circleColors'] = {json.dumps(colors[i], sort_keys=True): colors[i+1] for i in range(0, len(colors), 2)}
        assert len(project['circleColors']) * 2 == len(colors)
    return project


def route(arrangement):
    uses = {u['id']: u for u in arrangement['uses']}; current = arrangement['startID']; result = []
    while current:
        assert current not in result
        result.append(current)
        if uses[current]['isEnd']: break
        edges = [e for e in arrangement['edges'] if e['from'] == current]
        assert len(edges) == 1
        current = edges[0]['to']
    return result


def main():
    names = ['baseline/before', 'baseline/independent-added', 'baseline/before-reorder', 'baseline/restored',
             'initial/before', 'initial/inserted', 'initial/undone', 'initial/redone', 'initial/restored']
    names += ['final/' + n for n in ['before', 'inserted', 'undone', 'redone', 'restored', 'mcp-before',
                                     'terminal-inserted', 'terminal-undone', 'middle-inserted',
                                     'middle-reordered', 'reorder-undone', 'mcp-restored', 'reopened']]
    captures = {n: load(n) for n in names}; package = load('baseline/package')
    m = lambda name: captures[name]['manifest']
    baseline = music(m('baseline/before'))
    for name, capture in captures.items():
        s = capture['state']; project = capture['manifest']
        assert s['projectID'] == package['projectID'] == project['id']
        assert s['runtime']['build'] == ('87' if name.startswith('baseline/') else '88')
        assert s['runtime']['bundleID'] == 'com.circlr.integrationqa'
        assert s['revision'] == project['musicRevision'] and not s['dirty']
        assert s['output']['attempts'] == s['audition']['attempts'] == 0
        assert not s['playback']['playing'] and not any(s['recording'][k] for k in ['audio', 'midi', 'busy'])
        expected = copy.deepcopy(baseline)
        assert project['arrangements'][1] == baseline['arrangements'][1]
        assert project['sections'][:len(baseline['sections'])] == baseline['sections']
        expected['arrangements'][0] = copy.deepcopy(project['arrangements'][0])
        expected['sections'] = copy.deepcopy(project['sections'])
        assert expected == music(project), name
    a = baseline['arrangements'][0]
    assert [u['name'] for u in a['uses']] == ['도입', '절', '후렴']
    assert route(a) == [u['id'] for u in a['uses']]
    independent = m('baseline/independent-added')['arrangements'][0]
    assert independent['uses'][:3] == a['uses'] and independent['edges'] == a['edges']
    assert len(independent['uses']) == 4 and independent['uses'][-1]['id'] not in route(independent)
    assert music(m('baseline/independent-added')) == music(m('baseline/before-reorder'))
    rejected = load('baseline/reorder-rejected')
    error = ast.literal_eval(rejected['error'])
    assert error['ok'] is False and '전체 섹션 경로' in error['error']
    before = copy.deepcopy(rejected['before']); after = copy.deepcopy(rejected['after'])
    before.pop('sequence'); after.pop('sequence'); assert before == after
    assert music(m('baseline/restored')) == baseline == music(m('initial/before'))
    assert music(m('initial/undone')) == baseline == music(m('initial/restored'))
    assert music(m('initial/redone')) == music(m('initial/inserted'))
    inserted = m('initial/inserted')['arrangements'][0]
    new = inserted['uses'][2]
    assert inserted['uses'][:2] + inserted['uses'][3:] == a['uses']
    assert new['id'] not in {u['id'] for u in a['uses']} and not new['isEnd']
    assert route(inserted) == [a['uses'][0]['id'], a['uses'][1]['id'], new['id'], a['uses'][2]['id']]
    expected_edge = copy.deepcopy(a['edges'][1]); expected_edge['to'] = new['id']
    assert inserted['edges'][:2] == [a['edges'][0], expected_edge]
    assert inserted['edges'][2]['from'] == new['id'] and inserted['edges'][2]['to'] == a['uses'][2]['id']
    assert new['sectionID'] == m('initial/inserted')['sections'][-1]['id']
    assert new['sectionID'] not in {s['id'] for s in baseline['sections']}
    assert captures['initial/inserted']['state']['selection']['section']['useID'] == new['id']
    assert 'Description: 서클 이름' in (OUT / 'initial/inserted.ax.txt').read_text()
    for name in ['before', 'undone', 'restored', 'mcp-before', 'terminal-undone', 'mcp-restored', 'reopened']:
        assert music(m('final/' + name)) == baseline, name
    assert music(m('final/redone')) == music(m('final/inserted'))
    assert music(m('final/reorder-undone')) == music(m('final/middle-inserted'))
    assert m('final/mcp-restored') == m('final/reopened')
    for name, position in [('inserted', 2), ('terminal-inserted', 3), ('middle-inserted', 2)]:
        project = m('final/' + name); arr = project['arrangements'][0]
        new_use = next(u for u in arr['uses'] if u['id'] not in {u['id'] for u in a['uses']})
        expected_ids = [u['id'] for u in a['uses']]; expected_ids.insert(position, new_use['id'])
        assert route(arr) == expected_ids
        assert len(project['sections']) == len(baseline['sections']) + 1
        assert new_use['sectionID'] == project['sections'][-1]['id']
        if position == 3:
            assert new_use['isEnd']
            expected_uses = copy.deepcopy(a['uses']); expected_uses[-1]['isEnd'] = False
            assert arr['uses'][:-1] == expected_uses and arr['edges'][:2] == a['edges']
        else:
            assert not new_use['isEnd'] and [u for u in arr['uses'] if u['id'] != new_use['id']] == a['uses']
        if name != 'inserted':
            assert captures['final/' + name]['state']['selection'] == captures['final/mcp-before']['state']['selection']
    middle = m('final/middle-inserted')['arrangements'][0]
    mid = next(u['id'] for u in middle['uses'] if u['id'] not in {u['id'] for u in a['uses']})
    reordered = m('final/middle-reordered')['arrangements'][0]
    assert route(reordered) == [a['uses'][0]['id'], mid, a['uses'][1]['id'], a['uses'][2]['id']]
    expected = music(m('final/middle-inserted'))
    expected['arrangements'][0] = copy.deepcopy(reordered)
    assert expected == music(m('final/middle-reordered'))
    assert {u['id']: u for u in middle['uses']} == {u['id']: u for u in reordered['uses']}
    final_package = load('final/package')
    assert 'DE8AF525-6D22-39AA-A7EE-FA95F22E4442' in final_package['uuid']
    fixture = Path(package['fixture']); source = fixture.with_name('studio.circlr')
    assert hashlib.sha256((source / 'manifest.json').read_bytes()).hexdigest() == package['sourceSHA256'] == '12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d'
    assert len(baseline['assets']) == 2
    for asset in baseline['assets']:
        for folder in [fixture, source]:
            assert hashlib.sha256((folder / asset['path']).read_bytes()).hexdigest() == asset['checksum']
    assert music(json.loads((fixture / 'manifest.json').read_text())) == baseline
    print(json.dumps({'status': 'passed', 'nativeSnapshots': len(names), 'preservedAssets': 2,
                      'physicalAudioAttempts': 0, 'finalPackageUUID': final_package['uuid']}, ensure_ascii=False))


if __name__ == '__main__':
    main()
