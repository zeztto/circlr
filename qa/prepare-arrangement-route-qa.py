#!/usr/bin/env python3
"""Package build84 with authored audio and deterministic arrangement-route cases.

Run only after the matching release build. --candidate NAME packages another app
without resetting the existing QA document or its recorded edits.
"""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import uuid

spec = importlib.util.spec_from_file_location('packager', Path(__file__).with_name('prepare-automation-workspace-qa.py'))
p = importlib.util.module_from_spec(spec)
spec.loader.exec_module(p)
p.NAME = 'arrangement-route'
p.BUILD = '84'
p.OUT = p.ROOT / 'qa/generated/arrangement-route'
p.APP = p.OUT / '써클러 통합 검증.app'
p.FIXTURE = p.SOURCE.with_name('arrangement-route.circlr')


def identifier(name):
    return str(uuid.uuid5(uuid.NAMESPACE_URL, 'circlr-integration-qa/arrangement-route/' + name)).upper()


def route_fixture(project):
    """Transform a private copy only; retain sections, tracks and authored assets."""
    result = copy.deepcopy(project)
    base = result['arrangements'][0]
    original_use = copy.deepcopy(base['uses'][0])
    owner = result['album']['compositions'][0]
    cases = []
    transition = {'mode': 'within', 'anchor': 'sourceBars', 'length': 0,
                  'effect': {'kind': 'gain', 'amount': 1, 'secondary': .25}}

    def arrangement(index, name, order, repeats, branch=False):
        value = copy.deepcopy(base)
        value['id'] = base['id'] if index == 0 else identifier(f'arrangement/{index}')
        value['name'] = name
        value['uses'] = []
        for position, use_name in enumerate(['도입', '주제', '마무리', '경로 밖 보관']):
            use = copy.deepcopy(original_use)
            use['id'] = original_use['id'] if index == position == 0 else identifier(f'{index}/use/{position}')
            use.update(name=use_name, repeatCount=repeats.get(position, 1), isEnd=True)
            value['uses'].append(use)
        value['edges'] = []
        value['chosenEdges'] = {}
        connections = [(0, 1), (0, 2)] if branch else list(zip(order, order[1:]))
        for sequence, (start, end) in enumerate(connections):
            value['uses'][start]['isEnd'] = False
            value['edges'].append({'id': identifier(f'{index}/edge/{sequence}'),
                                   'from': value['uses'][start]['id'],
                                   'to': value['uses'][end]['id'],
                                   'transition': copy.deepcopy(transition)})
        value['startID'] = value['uses'][order[0]]['id']
        value['layout']['positions'] = {u['id']: {'x': i * 700, 'y': 0 if i < 3 else 700}
                                         for i, u in enumerate(value['uses'])}
        value['layout']['groups'] = []
        cases.append({'arrangementID': value['id'], 'name': name,
                      'expectedStatus': 'unresolvedBranch' if branch else 'ready',
                      'routeUseIDs': [] if branch else [value['uses'][i]['id'] for i in order],
                      'repeatCounts': [] if branch else [value['uses'][i]['repeatCount'] for i in order],
                      'offRouteUseIDs': [value['uses'][3]['id']]})
        return value

    first = arrangement(0, '도시의 밤', [0, 1, 2], {})
    second = arrangement(1, '도시의 밤', [2, 0, 1], {0: 2, 1: 3})
    unresolved = arrangement(2, '갈림길 선택 전', [0], {}, branch=True)
    empty = copy.deepcopy(base)
    empty.update(id=identifier('arrangement/3'), name='빈 편곡', uses=[], edges=[], chosenEdges={})
    empty.pop('startID', None)
    empty['layout']['positions'] = {}
    empty['layout']['groups'] = []
    cases.append({'arrangementID': empty['id'], 'name': empty['name'], 'expectedStatus': 'empty',
                  'routeUseIDs': [], 'repeatCounts': [], 'offRouteUseIDs': []})
    result['arrangements'] = [first, second, unresolved, empty]
    owner['arrangementIDs'] = [a['id'] for a in result['arrangements']]
    owner['selectedArrangementID'] = first['id']
    result['activeArrangementID'] = first['id']
    assert len(result['album']['compositions']) == 1
    assert all(u['sectionID'] == original_use['sectionID'] for a in result['arrangements'] for u in a['uses'])
    assert result['sections'] == project['sections'] and result['assets'] == project['assets']
    return result, cases


if __name__ == '__main__':
    source_before = (p.SOURCE / 'manifest.json').read_bytes()
    p.main()
    if not any(arg == '--candidate' or arg.startswith('--candidate=') for arg in sys.argv[1:]):
        target = p.FIXTURE / 'manifest.json'
        project, cases = route_fixture(json.loads(target.read_text()))
        target.write_text(json.dumps(project, ensure_ascii=False, indent=2) + '\n')
        with (p.OUT / 'fixture-initial.json').open('x') as file:
            json.dump(project, file, ensure_ascii=False, indent=2)
        with (p.OUT / 'route-cases.json').open('x') as file:
            json.dump(cases, file, ensure_ascii=False, indent=2)
    assert (p.SOURCE / 'manifest.json').read_bytes() == source_before
    assert hashlib.sha256(source_before).hexdigest() == json.loads((p.OUT / 'package.json').read_text())['sourceSHA256']
