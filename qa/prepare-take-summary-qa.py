#!/usr/bin/env python3
"""Seed isolated recorded-take QA data, or package an already-built build107 candidate."""
import argparse
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import uuid

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'qa/generated/take-summary'
SOURCE = Path.home() / 'Library/Application Support/circlr-integration-qa/fixtures/studio.circlr'
FIXTURE = SOURCE.with_name('take-summary.circlr')

def ident(name):
    return str(uuid.uuid5(uuid.NAMESPACE_URL, 'circlr-integration-qa/take-summary' + name)).upper()

def exclusive(path, data):
    with path.open('x') as handle:
        json.dump(data, handle, ensure_ascii=False, indent=2)
        handle.write('\n')

def seed():
    baseline = OUT / 'baseline'
    assert not baseline.exists() and not FIXTURE.exists(), 'Preserve existing fixture and evidence'
    source_bytes = (SOURCE / 'manifest.json').read_bytes()
    project = json.loads(source_bytes)
    package = json.loads((ROOT / 'qa/generated/bounce-notices/final/package.json').read_text())
    assert package['build'] == '106'
    assert hashlib.sha256(source_bytes).hexdigest() == package['sourceSHA256']
    assert len(project['assets']) == 2 and project['musicRevision'] == 14
    arrangement = project['arrangements'][0]; use = arrangement['uses'][0]
    section = next(s for s in project['sections'] if s['id'] == use['sectionID'])
    lane = next(l for l in section['lanes'] if l['id'].startswith('7F32786A-'))
    audio_node = next(n for n in section['graph']['nodes'] if n['id'].startswith('DDB48BA6-'))
    assert len(lane['audio']) == 1 and not lane['notes']
    takes = []
    def take(suffix, content, target=None, arrangement_id=None):
        item = dict(id=ident('/take/' + suffix), useID=use['id'], targetLaneID=target or lane['id'],
                    arrangementID=arrangement_id or arrangement['id'], name='녹음 테이크', lane=copy.deepcopy(content))
        takes.append(item); return item
    take('current', lane)
    shortened = copy.deepcopy(lane)
    shortened['audio'][0]['duration'] = 16
    shortened['audio'][0]['sourceStart'] = 0
    take('short', shortened)
    mixed = copy.deepcopy(lane)
    mixed['notes'] = [dict(id=ident('/mixed-note'), beat=0, pitch=60, length=0.5, velocity=64)]
    take('mixed', mixed)
    other_lane = next(l for l in section['lanes'] if l['id'] != lane['id'])
    hidden_lane = take('other-lane', other_lane, target=other_lane['id'])
    hidden_arrangement = take('other-arrangement', lane, arrangement_id=ident('/other-arrangement'))
    project['id'] = ident(''); project['takes'] = takes
    reference = json.loads((FIXTURE.with_name('bounce-notices.circlr') / 'manifest.json').read_text())
    project['hierarchyView'] = copy.deepcopy(reference['hierarchyView'])
    project['hierarchyView']['selection'] = {'music': dict(arrangementID=arrangement['id'], useID=use['id'], nodeID=audio_node['id'])}
    project['hierarchyView'].pop('workspace', None)
    project['hierarchyView'].pop('editor', None)
    baseline.mkdir(parents=True); FIXTURE.mkdir()
    for asset in project['assets']:
        relative = Path(asset['path']); assert not relative.is_absolute() and '..' not in relative.parts
        assert hashlib.sha256((SOURCE / relative).read_bytes()).hexdigest() == asset['checksum']
        destination = FIXTURE / relative; destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(SOURCE / relative, destination)
        assert hashlib.sha256(destination.read_bytes()).hexdigest() == asset['checksum']
    exclusive(FIXTURE / 'manifest.json', project)
    exclusive(baseline / 'fixture-initial.json', project)
    package.update(fixture=str(FIXTURE), projectID=project['id'])
    exclusive(baseline / 'package.json', package)
    exclusive(baseline / 'scenario.json', dict(scope='QA seed only; not a real recording or production content',
        sourceSHA256=hashlib.sha256(source_bytes).hexdigest(), initialRevision=14, assets=2,
        arrangementID=arrangement['id'], useID=use['id'], laneID=lane['id'], audioNodeID=audio_node['id'],
        visibleTakeIDs=[t['id'] for t in takes[:3]], hiddenTakeIDs=[hidden_lane['id'], hidden_arrangement['id']],
        sameName='녹음 테이크', shortDurationSeconds=16, sameClipID=lane['audio'][0]['id'],
        mixedNotes=1, mixedAudioClips=1, physicalAudioAttempts=0))
    assert (SOURCE / 'manifest.json').read_bytes() == source_bytes
    print(json.dumps(dict(fixture=str(FIXTURE), baselineApp=package['app'], seededTakes=5), ensure_ascii=False))

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--candidate')
    args = parser.parse_args()
    if not args.candidate:
        seed(); return
    assert args.candidate != 'baseline'
    before = (FIXTURE / 'manifest.json').read_bytes()
    spec = importlib.util.spec_from_file_location('packager', Path(__file__).with_name('prepare-automation-workspace-qa.py'))
    p = importlib.util.module_from_spec(spec); spec.loader.exec_module(p)
    p.NAME = 'take-summary'; p.BUILD = '107'; p.OUT = OUT; p.APP = OUT / '써클러 통합 검증.app'
    p.FIXTURE = FIXTURE
    p.main()
    assert (FIXTURE / 'manifest.json').read_bytes() == before

if __name__ == '__main__':
    main()
