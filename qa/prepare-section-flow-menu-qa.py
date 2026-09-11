#!/usr/bin/env python3
"""Create an exclusive build98 single-edge section-flow menu QA fixture and package.

Run only after the build98 Release is complete. Existing app/fixture are rejected.
"""
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import uuid

spec = importlib.util.spec_from_file_location('packager', Path(__file__).with_name('prepare-automation-workspace-qa.py'))
p = importlib.util.module_from_spec(spec)
spec.loader.exec_module(p)
NAME = 'section-flow-menu'


def main():
    if len(sys.argv) != 1:
        raise SystemExit('This first-creation wrapper takes no arguments; existing evidence is never overwritten.')
    p.NAME = NAME
    p.BUILD = '98'
    p.OUT = p.ROOT / 'qa/generated' / NAME
    p.APP = p.OUT / '써클러 통합 검증.app'
    p.FIXTURE = p.SOURCE.with_name(NAME + '.circlr')
    assert not p.OUT.exists(), 'Preserve the existing QA evidence directory'
    assert not p.FIXTURE.exists(), 'Preserve the existing QA fixture'
    source_before = (p.SOURCE / 'manifest.json').read_bytes()
    p.main()
    target = p.FIXTURE / 'manifest.json'
    project = json.loads(target.read_text())
    arrangement = next(a for a in project['arrangements'] if a['id'] == project['activeArrangementID'])
    assert len(arrangement['uses']) == 2 and arrangement['edges'] == []
    first, second = arrangement['uses']
    first['isEnd'] = False
    second['isEnd'] = True
    arrangement['chosenEdges'] = {}
    edge = {'id': str(uuid.uuid5(uuid.NAMESPACE_URL, 'circlr-integration-qa/' + NAME + '/single-edge')).upper(),
            'from': first['id'], 'to': second['id'],
            'transition': {'anchor': 'sourceBars', 'effect': {'amount': 1, 'kind': 'gain', 'secondary': 0.25},
                           'length': 0, 'mode': 'within'}}
    arrangement['edges'] = [edge]
    target.write_text(json.dumps(project, ensure_ascii=False, indent=2) + '\n')
    with (p.OUT / 'fixture-initial.json').open('x') as file:
        json.dump(project, file, ensure_ascii=False, indent=2)
    with (p.OUT / 'scenario.json').open('x') as file:
        json.dump({'projectID': project['id'], 'arrangementID': arrangement['id'],
                   'fromUseID': first['id'], 'toUseID': second['id'], 'edgeID': edge['id'],
                   'sourceSHA256': hashlib.sha256(source_before).hexdigest(),
                   'initialContract': 'single outgoing edge; chosenEdges empty; source not end; destination end'},
                  file, ensure_ascii=False, indent=2)
    assert (p.SOURCE / 'manifest.json').read_bytes() == source_before


if __name__ == '__main__':
    main()
