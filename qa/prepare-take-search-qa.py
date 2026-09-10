#!/usr/bin/env python3
"""Seed an isolated take-search fixture or package a prebuilt build108 candidate."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import uuid

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'qa/generated/take-search'
BASE = Path.home() / 'Library/Application Support/circlr-integration-qa/fixtures'
SOURCE = BASE / 'take-summary.circlr'
FIXTURE = BASE / 'take-search.circlr'
PROJECT_ID = str(uuid.uuid5(uuid.NAMESPACE_URL, 'circlr-integration-qa/take-search')).upper()


def exclusive(path, value):
    with path.open('x') as handle:
        json.dump(value, handle, ensure_ascii=False, indent=2)
        handle.write('\n')


def seed():
    baseline = OUT / 'baseline'
    assert not baseline.exists() and not FIXTURE.exists(), 'Preserve previous evidence and fixture'
    original = (SOURCE / 'manifest.json').read_bytes()
    project = json.loads(original)
    source_package = json.loads((ROOT / 'qa/generated/take-summary/final2/package.json').read_text())
    assert source_package['build'] == '107' and Path(source_package['fixture']) == SOURCE
    assert project['id'] == source_package['projectID'] and project['musicRevision'] == 22
    assert len(project['takes']) == 5 and len(project['assets']) == 2
    source_scenario = json.loads((ROOT / 'qa/generated/take-summary/baseline/scenario.json').read_text())
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
    project['id'] = PROJECT_ID
    exclusive(FIXTURE / 'manifest.json', project)
    exclusive(baseline / 'fixture-initial.json', project)
    package = dict(source_package, fixture=str(FIXTURE), projectID=PROJECT_ID,
                   fixtureSource=str(SOURCE), fixtureSourceSHA256=hashlib.sha256(original).hexdigest())
    exclusive(baseline / 'package.json', package)
    scenario = dict(source_scenario, scope='QA copy of take-summary seed; no new recording',
        source=str(SOURCE), sourceProjectID=source_package['projectID'],
        fixtureSourceSHA256=hashlib.sha256(original).hexdigest(), initialRevision=22,
        baselineBuild='107', candidateBuild='108', hierarchyPreserved=True)
    exclusive(baseline / 'scenario.json', scenario)
    assert (SOURCE / 'manifest.json').read_bytes() == original
    print(json.dumps(dict(fixture=str(FIXTURE), baselineApp=package['app'], revision=22, takes=5, assets=2), ensure_ascii=False))


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
    p.NAME = 'take-search'; p.BUILD = '108'; p.OUT = OUT; p.APP = OUT / '써클러 통합 검증.app'; p.FIXTURE = FIXTURE
    p.main()
    assert (FIXTURE / 'manifest.json').read_bytes() == before


if __name__ == '__main__':
    main()
