#!/usr/bin/env python3
"""Seed an isolated take-identity fixture or package a prebuilt build110 candidate."""
import argparse
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import uuid

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'qa/generated/take-identity'
BASE = Path.home() / 'Library/Application Support/circlr-integration-qa/fixtures'
SOURCE = BASE / 'take-search.circlr'
FIXTURE = BASE / 'take-identity.circlr'
PROJECT_ID = str(uuid.uuid5(uuid.NAMESPACE_URL, 'circlr-integration-qa/take-identity')).upper()


def exclusive(path, value):
    with path.open('x') as handle:
        json.dump(value, handle, ensure_ascii=False, indent=2)
        handle.write('\n')


def seed():
    baseline = OUT / 'baseline'
    assert not baseline.exists() and not FIXTURE.exists(), 'Preserve previous evidence and fixture'
    original = (SOURCE / 'manifest.json').read_bytes()
    project = json.loads(original)
    source_package = json.loads((ROOT / 'qa/generated/take-search/final3/package.json').read_text())
    assert source_package['build'] == '108' and Path(source_package['fixture']) == SOURCE
    assert project['id'] == source_package['projectID'] and project['musicRevision'] == 30
    assert len(project['takes']) == 5 and len(project['assets']) == 2
    source_scenario = json.loads((ROOT / 'qa/generated/take-search/baseline/scenario.json').read_text())
    for asset in project['assets']:
        path = Path(asset['path'])
        assert not path.is_absolute() and '..' not in path.parts and path.parts
        assert hashlib.sha256((SOURCE / path).read_bytes()).hexdigest() == asset['checksum']
    baseline.mkdir(parents=True); FIXTURE.mkdir()
    for asset in project['assets']:
        path = Path(asset['path']); target = FIXTURE / path
        target.parent.mkdir(parents=True, exist_ok=True)
        with target.open('xb') as handle:
            handle.write((SOURCE / path).read_bytes())
        assert hashlib.sha256(target.read_bytes()).hexdigest() == asset['checksum']
    eligible = [t for t in project['takes'] if t['id'] in source_scenario['visibleTakeIDs']]
    assert len(eligible) == 3
    lane = copy.deepcopy(eligible[0]['lane'])
    assert len(lane['audio']) == 1 and lane['notes'] == [] and lane['audio'][0]['gain'] == 1
    for take, gain in zip(eligible, [0.25, 0.5, 0.75]):
        take['lane'] = copy.deepcopy(lane); take['lane']['audio'][0]['gain'] = gain
    project['id'] = PROJECT_ID
    exclusive(FIXTURE / 'manifest.json', project)
    exclusive(baseline / 'fixture-initial.json', project)
    package = dict(source_package, fixture=str(FIXTURE), projectID=PROJECT_ID,
                   fixtureSource=str(SOURCE), fixtureSourceSHA256=hashlib.sha256(original).hexdigest())
    exclusive(baseline / 'package.json', package)
    scenario = dict(source_scenario, scope='QA take-identity copy; same names/counts, distinct clip gain; no recording',
        source=str(SOURCE), sourceProjectID=source_package['projectID'], projectID=PROJECT_ID,
        fixtureSourceSHA256=hashlib.sha256(original).hexdigest(), initialRevision=30,
        baselineBuild='108', candidateBuild='110', hierarchyPreserved=True,
        eligible=[{'ordinal':i+1, 'takeID':t['id'], 'expectedLane':t['lane']} for i,t in enumerate(eligible)],
        currentLane=lane, targetTakeID=eligible[1]['id'], mixedNotes=0, mixedAudioClips=1,
        sameDurationSeconds=32, eligibleAudioGains=[0.25,0.5,0.75], currentAudioGain=1)
    exclusive(baseline / 'scenario.json', scenario)
    assert (SOURCE / 'manifest.json').read_bytes() == original
    print(json.dumps(dict(fixture=str(FIXTURE), baselineApp=package['app'], revision=30, takes=5, assets=2), ensure_ascii=False))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--candidate')
    args = parser.parse_args()
    if not args.candidate:
        seed(); return
    assert args.candidate != 'baseline'
    before = (FIXTURE / 'manifest.json').read_bytes()
    assert json.loads(before)['id'] == PROJECT_ID
    spec = importlib.util.spec_from_file_location('packager', Path(__file__).with_name('prepare-automation-workspace-qa.py'))
    p = importlib.util.module_from_spec(spec); spec.loader.exec_module(p)
    p.NAME = 'take-identity'; p.BUILD = '110'; p.OUT = OUT; p.APP = OUT / '써클러 통합 검증.app'; p.FIXTURE = FIXTURE
    p.main()
    assert (FIXTURE / 'manifest.json').read_bytes() == before


if __name__ == '__main__':
    main()
