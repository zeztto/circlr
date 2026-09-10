#!/usr/bin/env python3
"""Prepare an isolated build113 input fixture; package only on explicit --candidate."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import uuid

ROOT = Path(__file__).resolve().parents[1]
NAME = 'arrangement-input'
OUT = ROOT / 'qa/generated' / NAME
SOURCE_SEED = ROOT / 'qa/generated/arrangement-continuation/baseline/fixture-initial.json'
SOURCE_SCENARIO = SOURCE_SEED.with_name('scenario.json')
FIXTURE = Path.home() / 'Library/Application Support/circlr-integration-qa/fixtures' / (NAME + '.circlr')
PROJECT_ID = str(uuid.uuid5(uuid.NAMESPACE_URL, 'circlr-integration-qa/' + NAME)).upper()


def module(name, file):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(file))
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


def exclusive(path, value):
    with path.open('x') as handle:
        json.dump(value, handle, ensure_ascii=False, indent=2)
        handle.write('\n')


def seed():
    assert not OUT.exists() and not FIXTURE.exists(), 'Preserve prior fixtures/evidence'
    raw = SOURCE_SEED.read_bytes()
    source = json.loads(raw)
    scenario = json.loads(SOURCE_SCENARIO.read_text())
    assert source['musicRevision'] == 14 and len(source['assets']) == 2
    asset_source = Path(scenario['source'])
    assert hashlib.sha256((asset_source / 'manifest.json').read_bytes()).hexdigest() == scenario['sourceSHA256']
    for asset in source['assets']:
        relative = Path(asset['path'])
        assert relative.parts and not relative.is_absolute() and '..' not in relative.parts
        assert hashlib.sha256((asset_source / relative).read_bytes()).hexdigest() == asset['checksum']
    source['id'] = PROJECT_ID
    source['name'] = '편곡 입력 즉시 반응 검증'
    baseline = OUT / 'baseline'
    baseline.mkdir(parents=True)
    FIXTURE.mkdir()
    for asset in source['assets']:
        relative = Path(asset['path'])
        destination = FIXTURE / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        with destination.open('xb') as handle:
            handle.write((asset_source / relative).read_bytes())
    exclusive(FIXTURE / 'manifest.json', source)
    exclusive(baseline / 'fixture-initial.json', source)
    scenario.update(projectID=PROJECT_ID, fixture=str(FIXTURE), sourceSeed=str(SOURCE_SEED),
                    sourceSeedSHA256=hashlib.sha256(raw).hexdigest(), candidateBuild='113',
                    seedChanges='Copy build112 baseline; only project ID and name changed; assets preserved.')
    exclusive(baseline / 'scenario.json', scenario)
    assert SOURCE_SEED.read_bytes() == raw
    print(json.dumps(dict(fixture=str(FIXTURE), projectID=PROJECT_ID, revision=14, assets=2)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--candidate')
    args = parser.parse_args()
    if not args.candidate:
        seed()
        return
    assert args.candidate != 'baseline' and not (OUT / args.candidate).exists()
    before = (FIXTURE / 'manifest.json').read_bytes()
    assert json.loads(before)['id'] == PROJECT_ID
    packager = module('input_packager', 'prepare-automation-workspace-qa.py')
    packager.NAME = NAME; packager.BUILD = '113'; packager.OUT = OUT; packager.FIXTURE = FIXTURE
    packager.main()
    module('input_deny', 'prepare-midi-generation-qa.py').deny_output(OUT / args.candidate)
    assert (FIXTURE / 'manifest.json').read_bytes() == before


if __name__ == '__main__':
    main()
