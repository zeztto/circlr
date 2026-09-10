#!/usr/bin/env python3
"""Seed isolated continuation QA; --candidate final packages build112 with output denied."""
import argparse
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import uuid

ROOT = Path(__file__).resolve().parents[1]
NAME = 'arrangement-continuation'
OUT = ROOT / 'qa/generated' / NAME
SOURCE = Path.home() / 'Library/Application Support/circlr-integration-qa/fixtures/studio.circlr'
FIXTURE = SOURCE.with_name(NAME + '.circlr')
PROJECT_ID = str(uuid.uuid5(uuid.NAMESPACE_URL, 'circlr-integration-qa/' + NAME)).upper()


def module(name, file):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(file))
    result = importlib.util.module_from_spec(spec); spec.loader.exec_module(result)
    return result


def identifier(name):
    return str(uuid.uuid5(uuid.NAMESPACE_URL, 'circlr-integration-qa/' + NAME + '/' + name)).upper()


def exclusive(path, value):
    with path.open('x') as file: json.dump(value, file, ensure_ascii=False, indent=2)


def seed():
    assert not OUT.exists() and not FIXTURE.exists(), 'Preserve existing fixture/evidence'
    raw = (SOURCE / 'manifest.json').read_bytes(); project = json.loads(raw)
    assert len(project['assets']) == 2
    for asset in project['assets']:
        path = Path(asset['path']); assert not path.is_absolute() and '..' not in path.parts
        assert hashlib.sha256((SOURCE / path).read_bytes()).hexdigest() == asset['checksum']
    project['id'] = PROJECT_ID
    arrangement = project['arrangements'][0]; arrangement['name'] = '현재 편곡 · 이어 편집'
    first = arrangement['uses'][0]; first['name'] = '같은 이름 섹션'
    second = copy.deepcopy(first); second['id'] = identifier('second-use')
    arrangement['uses'].append(second)
    arrangement['layout']['positions'][second['id']] = {'x':700,'y':0}
    section = next(s for s in project['sections'] if s['id'] == first['sectionID'])
    lane = section['lanes'][0]; clip = lane['audio'][0]
    assert clip['duration'] == 32 and clip['sourceStart'] == 0
    clip['duration'] = 16
    later = copy.deepcopy(clip); later.update(id=identifier('later-clip'), beat=32, sourceStart=16)
    lane['audio'].append(later)
    node = next(n for n in section['graph']['nodes'] if n['content'].get('audio', {}).get('clipID') == clip['id'])
    later_node = copy.deepcopy(node)
    later_node.update(id=identifier('later-audio-node'), name='검증 톤 1 · 뒤', startBeat=32)
    later_node['content']['audio']['clipID'] = later['id']
    points = [dict(id=identifier('point-'+str(i)), beat=b, value=v, shape='linear')
              for i,(b,v) in enumerate([(0,0.4),(8,0.8),(24,0.6)])]
    later_node['automation'] = [dict(parameter='gain', enabled=True, points=points)]
    section['graph']['nodes'].append(later_node)
    edge = copy.deepcopy(next(e for e in section['graph']['edges'] if e['from'] == node['id']))
    edge.update(id=identifier('later-edge'), **{'from':later_node['id']})
    section['graph']['edges'].append(edge)
    section['graph']['layout']['positions'][later_node['id']] = {'x':-360,'y':100}
    alternatives = module('continuation_alternatives', 'prepare-arrangement-search-qa.py')
    alternatives.identifier = identifier
    candidate = alternatives.alternative(arrangement, 2, '다른 후보 · 이어 편집 없음')
    project['arrangements'].append(candidate)
    owner = next(o for o in project['album']['compositions'] if arrangement['id'] in o['arrangementIDs'])
    owner['arrangementIDs'].append(candidate['id']); owner['selectedArrangementID'] = arrangement['id']
    project['activeArrangementID'] = arrangement['id']
    baseline = OUT / 'baseline'; baseline.mkdir(parents=True); FIXTURE.mkdir()
    for asset in project['assets']:
        destination = FIXTURE / asset['path']; destination.parent.mkdir(parents=True, exist_ok=True)
        with destination.open('xb') as file: file.write((SOURCE / asset['path']).read_bytes())
    exclusive(FIXTURE / 'manifest.json', project)
    exclusive(baseline / 'fixture-initial.json', project)
    exclusive(baseline / 'scenario.json', dict(projectID=PROJECT_ID, fixture=str(FIXTURE),
        source=str(SOURCE), sourceSHA256=hashlib.sha256(raw).hexdigest(), initialRevision=project['musicRevision'],
        currentArrangementID=arrangement['id'], candidateArrangementID=candidate['id'],
        firstUseID=first['id'], targetUseID=second['id'], sectionID=section['id'],
        nodeID=later_node['id'], laneID=lane['id'], clipID=later['id'], assetID=later['assetID'],
        automationParameter='gain', targetPointID=points[1]['id'], points=points,
        seedChanges='Two same-name uses; first source audio split into two 16-second clips; later node gain automation; alternative copy.',
        continuation='Clone current then Shift-Command-E: remap arrangement/use only; same node/clip/point IDs.', assets=2))
    assert (SOURCE / 'manifest.json').read_bytes() == raw
    print(json.dumps({'fixture':str(FIXTURE),'projectID':PROJECT_ID},ensure_ascii=False))


def main():
    parser = argparse.ArgumentParser(description=__doc__); parser.add_argument('--candidate')
    args = parser.parse_args()
    if not args.candidate: seed(); return
    assert args.candidate != 'baseline'
    assert not (OUT / args.candidate).exists(), 'Preserve all prior candidate evidence'
    before = (FIXTURE / 'manifest.json').read_bytes(); assert json.loads(before)['id'] == PROJECT_ID
    p = module('continuation_package', 'prepare-automation-workspace-qa.py')
    p.NAME=NAME; p.BUILD='112'; p.OUT=OUT; p.FIXTURE=FIXTURE
    p.main()
    deny = module('continuation_deny', 'prepare-midi-generation-qa.py')
    deny.deny_output(OUT / args.candidate)
    assert (FIXTURE / 'manifest.json').read_bytes() == before


if __name__ == '__main__': main()
