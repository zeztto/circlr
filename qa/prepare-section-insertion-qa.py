#!/usr/bin/env python3
"""Create build87 baseline once; package build88 candidates without resetting music.

  python3 qa/prepare-section-insertion-qa.py --baseline
  python3 qa/prepare-section-insertion-qa.py --candidate final

The first fixture has a three-use chain and a separate arrangement for preservation.
Both arrangements share the original authored section and assets.
"""
import argparse
import copy
import importlib.util
import json
from pathlib import Path
import re
import sys
import uuid

spec = importlib.util.spec_from_file_location('packager', Path(__file__).with_name('prepare-automation-workspace-qa.py'))
p = importlib.util.module_from_spec(spec)
spec.loader.exec_module(p)
NAME = 'section-insertion'
OUT = p.ROOT / 'qa/generated' / NAME


def identifier(name):
    return str(uuid.uuid5(uuid.NAMESPACE_URL, 'circlr-integration-qa/' + NAME + '/' + name)).upper()


def insertion_fixture(project):
    project = copy.deepcopy(project)
    base = copy.deepcopy(project['arrangements'][0])
    source_use = copy.deepcopy(base['uses'][0])
    transition = {'mode': 'within', 'anchor': 'sourceBars', 'length': 0,
                  'effect': {'kind': 'gain', 'amount': 1, 'secondary': .25}}
    arrangements = []
    for index in range(2):
        arrangement = copy.deepcopy(base)
        arrangement['id'] = base['id'] if index == 0 else identifier('comparison-arrangement')
        arrangement['name'] = '섹션 삽입 검증' if index == 0 else '보존 대조 편곡'
        arrangement['uses'] = []
        for position, name in enumerate(['도입', '절', '후렴']):
            use = copy.deepcopy(source_use)
            use['id'] = source_use['id'] if index == position == 0 else identifier(f'{index}/use/{position}')
            use.update(name=name, repeatCount=1, isEnd=position == 2)
            arrangement['uses'].append(use)
        arrangement['edges'] = [{'id': identifier(f'{index}/edge/{i}'),
                                 'from': arrangement['uses'][i]['id'],
                                 'to': arrangement['uses'][i+1]['id'],
                                 'transition': copy.deepcopy(transition)} for i in range(2)]
        arrangement['chosenEdges'] = {}
        arrangement['startID'] = arrangement['uses'][0]['id']
        arrangement['layout']['positions'] = {u['id']: {'x': i*700, 'y': 0} for i, u in enumerate(arrangement['uses'])}
        arrangement['layout']['groups'] = []
        arrangements.append(arrangement)
    project['arrangements'] = arrangements
    assert len(project['album']['compositions']) == 1
    owner = project['album']['compositions'][0]
    owner['arrangementIDs'] = [a['id'] for a in arrangements]
    owner['selectedArrangementID'] = arrangements[0]['id']
    project['activeArrangementID'] = arrangements[0]['id']
    return project


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--baseline', action='store_true', help='First creation only, from build87 release')
    mode.add_argument('--candidate', help='New build88 package folder; preserve the existing fixture')
    args = parser.parse_args()
    if args.candidate:
        assert re.fullmatch('[a-z0-9-]{1,32}', args.candidate)
        assert args.candidate != 'baseline', 'baseline is reserved for the original build87 package'
        assert (OUT / 'baseline/package.json').is_file(), 'Create --baseline first'
    p.NAME = NAME
    p.BUILD = '87' if args.baseline else '88'
    p.FIXTURE = p.SOURCE.with_name(NAME + '.circlr')
    # Baseline must enter the common FIRST-CREATION path, not its candidate path.
    p.OUT = OUT / 'baseline' if args.baseline else OUT
    p.APP = p.OUT / '써클러 통합 검증.app'
    original_argv = sys.argv
    try:
        sys.argv = [original_argv[0]] + ([] if args.baseline else ['--candidate', args.candidate])
        p.main()
    finally:
        sys.argv = original_argv
    if args.baseline:
        path = p.FIXTURE / 'manifest.json'
        transformed = insertion_fixture(json.loads(path.read_text()))
        path.write_text(json.dumps(transformed, ensure_ascii=False, indent=2) + '\n')
        with (p.OUT / 'fixture-initial.json').open('x') as file:
            json.dump(transformed, file, ensure_ascii=False, indent=2)


if __name__ == '__main__':
    main()
