#!/usr/bin/env python3
"""Create an exclusive production-flow QA copy or package prebuilt build122 binaries.

Reuses the five-helper deny package contract; never starts an app or audio device.
"""
import argparse
import importlib.util
import json
from pathlib import Path
import plistlib
import re
import uuid

spec = importlib.util.spec_from_file_location('production_flow_package', Path(__file__).with_name('prepare-step-target-qa.py'))
p = importlib.util.module_from_spec(spec)
spec.loader.exec_module(p)
p.OUT = p.ROOT / 'qa/generated/production-flow'
p.SOURCE = p.SOURCE.with_name('step-target.circlr')
p.FIXTURE = p.SOURCE.with_name('production-flow.circlr')
p.PROJECT_ID = str(uuid.uuid5(uuid.NAMESPACE_URL, 'circlr-integration-qa/production-flow')).upper()
ROOT, OUT, SOURCE, FIXTURE, PROJECT_ID = p.ROOT, p.OUT, p.SOURCE, p.FIXTURE, p.PROJECT_ID
HELPERS, digest, run, exclusive, assets = p.HELPERS, p.digest, p.run, p.exclusive, p.assets


def seed():
    assert not OUT.exists() and not FIXTURE.exists(), 'Preserve all earlier evidence'
    raw = (SOURCE / 'manifest.json').read_bytes()
    project = json.loads(raw)
    assets(project, SOURCE)
    assert len(project['tracks']) == 3
    assert all(t['instrument']['kind'] == 'synthesizer' and t['instrument']['synth']['engineVersion'] == 3 for t in project['tracks'])
    arrangement = project['arrangements'][0]; use = arrangement['uses'][0]
    node = next(n for n in use['graphEdits']['addedNodes'] if n['id'] == p.NODE)
    track = node['content']['rhythmMIDI']['trackID']
    pattern = next(x for x in project['patterns'] if x['id'] == project['global']['rhythm']['patternID'])
    assert pattern['trackID'] == track
    lane = next(x for x in use['addedLanes'] if x['trackID'] == track and x['notes'])
    original_id, original_name = project['id'], project['name']
    project.update(id=PROJECT_ID, name='음악 제작 흐름 검증')
    comparison = dict(project, id=original_id, name=original_name)
    assert comparison == json.loads(raw), 'Only new project identity/name may differ'
    baseline = OUT / 'baseline'; baseline.mkdir(parents=True); FIXTURE.mkdir()
    for asset in project['assets']:
        destination = FIXTURE / asset['path']; destination.parent.mkdir(parents=True, exist_ok=True)
        with destination.open('xb') as handle: handle.write((SOURCE / asset['path']).read_bytes())
    exclusive(FIXTURE / 'manifest.json', project)
    exclusive(baseline / 'fixture-initial.json', project)
    exclusive(baseline / 'scenario.json', dict(projectID=PROJECT_ID, fixture=str(FIXTURE), source=str(SOURCE),
        sourceSHA256=digest(SOURCE / 'manifest.json'), initialRevision=project['musicRevision'],
        arrangementID=arrangement['id'], useID=use['id'], nodeID=p.NODE, trackID=track,
        patternID=pattern['id'], laneID=lane['id'], midiNodeID='midi:' + lane['id'],
        assets=project['assets'], physicalAudioAttempts=0,
        scope='Exact authored step-target copy except project identity/name; three built-in engine3 synthesizer tracks; five device/AU/audition helpers denied'))
    assets(project, FIXTURE)
    assert (SOURCE / 'manifest.json').read_bytes() == raw
    print(json.dumps(dict(fixture=str(FIXTURE), projectID=PROJECT_ID, revision=project['musicRevision'])))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--candidate'); parser.add_argument('--binary-dir', type=Path)
    parser.add_argument('--info-plist', type=Path)
    args = parser.parse_args()
    if args.candidate:
        assert re.fullmatch('[a-z0-9-]{1,32}', args.candidate) and args.candidate != 'baseline'
        assert args.binary_dir is not None and args.info_plist is not None
        assert plistlib.loads(args.info_plist.read_bytes())['CFBundleVersion'] == '122'
        p.package(args.candidate, args.binary_dir, args.info_plist)
    else:
        assert args.binary_dir is None and args.info_plist is None
        seed()
