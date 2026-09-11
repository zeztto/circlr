#!/usr/bin/env python3
"""Seed isolated tempo-region QA; --candidate final packages build113 with output denied."""
import argparse
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import uuid

ROOT = Path(__file__).resolve().parents[1]
NAME = 'audio-tempo-region'
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
    arrangement = project['arrangements'][0]
    use = arrangement['uses'][0]; use['repeatCount'] = 1
    section = next(s for s in project['sections'] if s['id'] == use['sectionID'])
    section['tempoChanges'] = [dict(beat=8,bpm=140)]
    nodes = []
    for lane, start in zip(section['lanes'][:2], [0,7]):
        clip = lane['audio'][0]
        clip.update(beat=0,duration=1,sourceStart=0,sourceBPM=120,followsTempo=True,
                    preservesTail=False,fadeIn=0,fadeOut=0)
        node = next(n for n in section['graph']['nodes'] if n['content'].get('audio',{}).get('clipID') == clip['id'])
        node.update(startBeat=start,lengthBeats=2,repeatCount=1)
        nodes.append(dict(nodeID=node['id'],laneID=lane['id'],clipID=clip['id'],
                          startBeat=start,clipLocalBeat=0,endBeat=start+2,durationSeconds=1))
    baseline = OUT / 'baseline'; baseline.mkdir(parents=True); FIXTURE.mkdir()
    for asset in project['assets']:
        destination = FIXTURE / asset['path']; destination.parent.mkdir(parents=True, exist_ok=True)
        with destination.open('xb') as file: file.write((SOURCE / asset['path']).read_bytes())
    exclusive(FIXTURE / 'manifest.json', project)
    exclusive(baseline / 'fixture-initial.json', project)
    exclusive(baseline / 'scenario.json', dict(projectID=PROJECT_ID,fixture=str(FIXTURE),
        source=str(SOURCE),sourceSHA256=hashlib.sha256(raw).hexdigest(),initialRevision=project['musicRevision'],
        arrangementID=arrangement['id'],useID=use['id'],sectionID=section['id'],
        constantRegion=nodes[0],crossingRegion=nodes[1],tempoChanges=section['tempoChanges'],
        baseBPM=120,assets=2,
        expected='Selected constant-region graph bounce succeeds; crossing region rejected; legacy broad-map behavior covered by Core tests.',
        seedChanges='Only QA copy: two source clips are one-second tempo-following regions at node beats0 and7, both clip-local beat0; nodes length2 repeat1; section tempo140 from beat8.'))
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
    p.NAME=NAME; p.BUILD='113'; p.OUT=OUT; p.FIXTURE=FIXTURE
    p.main()
    deny = module('continuation_deny', 'prepare-midi-generation-qa.py')
    deny.deny_output(OUT / args.candidate)
    assert (FIXTURE / 'manifest.json').read_bytes() == before


if __name__ == '__main__': main()
