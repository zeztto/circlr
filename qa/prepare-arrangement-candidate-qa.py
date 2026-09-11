#!/usr/bin/env python3
"""Create exclusive build99 QA with current A, explicit candidate B, and foreign-owner D."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import uuid


def module(name, filename):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(filename))
    result = importlib.util.module_from_spec(spec); spec.loader.exec_module(result)
    return result


p = module('packager', 'prepare-automation-workspace-qa.py')
a = module('alternatives', 'prepare-arrangement-search-qa.py')
NAME = 'arrangement-candidate'


def identifier(name):
    return str(uuid.uuid5(uuid.NAMESPACE_URL, 'circlr-integration-qa/' + NAME + '/' + name)).upper()


def main():
    assert len(sys.argv) == 1, 'First creation only; no candidate/reset mode'
    p.NAME = NAME; p.BUILD = '99'; p.OUT = p.ROOT / 'qa/generated' / NAME
    p.APP = p.OUT / '써클러 통합 검증.app'; p.FIXTURE = p.SOURCE.with_name(NAME + '.circlr')
    assert not p.OUT.exists() and not p.FIXTURE.exists(), 'Preserve existing QA package/fixture'
    source = (p.SOURCE / 'manifest.json').read_bytes()
    p.main()
    path = p.FIXTURE / 'manifest.json'; project = json.loads(path.read_text())
    base = project['arrangements'][0]; base['name'] = '현재 편곡 A'
    owner = project['album']['compositions'][0]
    a.identifier = identifier
    candidate = a.alternative(base, 2, '세 번 반복하는 후보 B')
    candidate['uses'][0]['repeatCount'] = 3
    other_arrangement = a.alternative(base, 3, '다른 곡의 편곡 D')
    owner['arrangementIDs'] = [base['id'], candidate['id']]
    owner['selectedArrangementID'] = base['id']; project['activeArrangementID'] = base['id']
    other = copy.deepcopy(owner)
    other.update(id=identifier('other-owner'), name='다른 곡 D', arrangementIDs=[other_arrangement['id']],
                 selectedArrangementID=other_arrangement['id'], children=[])
    project['arrangements'] += [candidate, other_arrangement]
    project['album']['compositions'].append(other); project['album']['children'].append(other['id'])
    project['album']['layout']['positions'][other['id']] = {'x': 700, 'y': 0}
    project['circleColors'] = [{'section': {'arrangementID': candidate['id'], 'useID': candidate['uses'][0]['id']}},
                               {'red': 235, 'green': 156, 'blue': 134}]
    path.write_text(json.dumps(project, ensure_ascii=False, indent=2) + '\n')
    with (p.OUT / 'fixture-initial.json').open('x') as file: json.dump(project, file, ensure_ascii=False, indent=2)
    with (p.OUT / 'scenario.json').open('x') as file:
        json.dump({'projectID': project['id'], 'ownerID': owner['id'], 'currentA': base['id'],
                   'candidateB': candidate['id'], 'candidateUseID': candidate['uses'][0]['id'],
                   'otherOwnerID': other['id'], 'otherD': other_arrangement['id'],
                   'sourceSHA256': hashlib.sha256(source).hexdigest()}, file, ensure_ascii=False, indent=2)
    assert (p.SOURCE / 'manifest.json').read_bytes() == source


if __name__ == '__main__':
    main()
