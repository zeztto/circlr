#!/usr/bin/env python3
"""Check preserved bounce-visibility evidence and final compact native acceptance."""
import copy
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'qa/generated/bounce-visibility'


def load(name):
    return json.loads((OUT / (name + '.json')).read_text())


def music(value):
    value = copy.deepcopy(value)
    value.pop('musicRevision', None)
    value.pop('hierarchyView', None)
    colors = value.get('circleColors')
    if colors is not None:
        assert len(colors) % 2 == 0
        value['circleColors'] = {json.dumps(colors[i], sort_keys=True): colors[i+1] for i in range(0, len(colors), 2)}
        assert len(value['circleColors']) * 2 == len(colors)
    return value


def target_use(project, scenario):
    arrangement = next(a for a in project['arrangements'] if a['id'] == scenario['arrangementID'])
    return next(u for u in arrangement['uses'] if u['id'] == scenario['useID'])


def main():
    names = ['baseline/before', 'baseline/duplicated', 'baseline/outside', 'baseline/no-input',
             'final/no-input', 'final/output-open', 'final/reconnected', 'final/outside']
    names += ['compact/' + n for n in ['before', 'command-open', 'before-disconnect',
                                       'no-input', 'before-undo', 'undo', 'automation',
                                       'stale-before', 'stale-mutated', 'stale-rejected', 'final', 'reopened']]
    captures = {n: load(n) for n in names}; scenario = load('scenario')
    baseline = load('baseline/package'); initial = load('final/package')
    assert baseline['build'] == '84' and initial['build'] == '85'
    manifest = lambda n: captures[n]['manifest']
    for name, capture in captures.items():
        s = capture['state']
        assert s['projectID'] == baseline['projectID'] == capture['manifest']['id']
        assert s['runtime']['build'] == ('84' if name.startswith('baseline/') else '85')
        assert s['runtime']['bundleID'] == 'com.circlr.integrationqa'
        assert s['revision'] == capture['manifest']['musicRevision'] and not s['dirty']
        assert s['output']['attempts'] == s['audition']['attempts'] == 0
        assert not s['playback']['playing']
        assert not any(s['recording'][k] for k in ['audio', 'midi', 'busy'])
        expected = music(manifest('baseline/before'))
        if name in ['compact/stale-mutated', 'compact/stale-rejected']:
            expected['name'] = '대상 보호 검증'
        source_use = target_use(expected, scenario)
        source_use.clear(); source_use.update(copy.deepcopy(target_use(capture['manifest'], scenario)))
        assert expected == music(capture['manifest']), name  # Other use, sources, assets and all unrelated fields.

    duplicated = music(manifest('baseline/duplicated'))
    outside = music(manifest('baseline/outside'))
    edits = target_use(duplicated, scenario)['graphEdits']
    assert scenario['copyEdge'] in edits['addedEdges']
    assert any(n['id'] == scenario['copyNodeID'] for n in edits['addedNodes'])
    edits['addedEdges'].remove(scenario['copyEdge'])
    assert duplicated == outside
    no_input = music(manifest('baseline/no-input'))
    removed = target_use(outside, scenario)['graphEdits']['removedEdgeIDs']
    assert scenario['outputEdge']['id'] not in removed
    removed.append(scenario['outputEdge']['id'])
    assert outside == no_input
    assert manifest('baseline/no-input') == manifest('final/no-input')
    assert music(manifest('final/no-input')) == music(manifest('final/output-open'))
    assert music(manifest('final/reconnected')) == music(manifest('final/outside'))
    expected = music(manifest('final/output-open')); actual = music(manifest('final/reconnected'))
    old_edges = target_use(expected, scenario)['graphEdits']['addedEdges']
    new_edges = target_use(actual, scenario)['graphEdits']['addedEdges']
    added = [e for e in new_edges if e not in old_edges]
    assert len(added) == 1
    edge = copy.deepcopy(added[0]); edge['id'] = scenario['outputEdge']['id']
    assert edge == scenario['outputEdge']
    old_edges.append(added[0])
    assert expected == actual
    assert captures['final/outside']['state']['selection']['music']['nodeID'] == scenario['copyNodeID']

    compact = load('compact/package')
    assert '1A15C6F2-3FA2-38AB-84C0-FC443ED81314' in compact['uuid']
    assert music(manifest('final/outside')) == music(manifest('compact/before'))
    for left, right in [('before', 'command-open'), ('command-open', 'before-disconnect'),
                        ('no-input', 'before-undo'), ('before', 'undo'), ('undo', 'automation')]:
        assert music(manifest('compact/' + left)) == music(manifest('compact/' + right)), (left, right)
    expected = music(manifest('compact/before-disconnect'))
    edges = target_use(expected, scenario)['graphEdits']['addedEdges']
    matching = [e for e in edges if e['from'] == scenario['outputEdge']['from'] and e['to'] == scenario['outputEdge']['to']]
    assert len(matching) == 1
    edges.remove(matching[0])
    assert expected == music(manifest('compact/no-input'))
    destination = captures['compact/command-open']['state']['selection']['music']
    assert destination == {'arrangementID': scenario['arrangementID'], 'useID': scenario['useID'], 'nodeID': scenario['outputEdge']['to']}
    assert manifest('compact/command-open')['hierarchyView']['workspace']['page'] == 'connections'
    assert captures['compact/automation']['state']['automationEditor']['visible']
    assert captures['compact/automation']['state']['selection']['music']['nodeID'] == scenario['copyNodeID']
    outside_ax = (OUT / 'compact/outside.ax.txt').read_text()
    assert '현재 서클은 출력 경로 밖입니다' in outside_ax
    assert '바운스 · 출력 1' in outside_ax and '오디오 파형 편집기' in outside_ax
    assert '바운스 출력 연결 보기' in (OUT / 'compact/command.ax.txt').read_text()
    assert '출력에 연결된 연주가 없습니다' in (OUT / 'compact/no-input.ax.txt').read_text()
    assert '현재 서클은 출력 경로 밖입니다' in (OUT / 'compact/automation.ax.txt').read_text()
    expected = music(manifest('compact/stale-before'))
    expected['name'] = '대상 보호 검증'
    assert expected == music(manifest('compact/stale-mutated'))
    assert manifest('compact/stale-mutated') == manifest('compact/stale-rejected')
    for key in ['selection', 'automationEditor']:
        assert captures['compact/stale-before']['state'][key] == captures['compact/stale-rejected']['state'][key]
    assert '대상이나 음악이 바뀌었습니다. 현재 서클에서 다시 실행하세요' in (OUT / 'compact/stale-rejected.ax.txt').read_text()
    assert music(manifest('compact/final')) == music(manifest('compact/stale-before'))
    assert manifest('compact/final') == manifest('compact/reopened')

    fixture = Path(baseline['fixture']); source = fixture.with_name('studio.circlr')
    digest = hashlib.sha256((source / 'manifest.json').read_bytes()).hexdigest()
    assert digest == baseline['sourceSHA256'] == initial['sourceSHA256'] == '12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d'
    assets = manifest('baseline/before')['assets']; assert len(assets) == 2
    for asset in assets:
        for folder in [source, fixture]:
            assert hashlib.sha256((folder / asset['path']).read_bytes()).hexdigest() == asset['checksum']
    assert music(json.loads((fixture / 'manifest.json').read_text())) == music(manifest('compact/reopened'))
    print(json.dumps({'status': 'passed', 'preservationChecks': 'passed', 'nativeSnapshots': len(names),
                      'preservedAssets': 2, 'physicalAudioAttempts': 0,
                      'compactPackageUUID': compact['uuid']}, ensure_ascii=False))


if __name__ == '__main__':
    main()
