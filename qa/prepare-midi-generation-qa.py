#!/usr/bin/env python3
"""Seed an isolated MIDI generation fixture; package build111 only after Release."""
import argparse
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import uuid
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'qa/generated/midi-generation'
BASE = Path.home() / 'Library/Application Support/circlr-integration-qa/fixtures'
SOURCE = BASE / 'rhythm-scope.circlr'
FIXTURE = BASE / 'midi-generation.circlr'
PROJECT_ID = str(uuid.uuid5(uuid.NAMESPACE_URL, 'circlr-integration-qa/midi-generation')).upper()


def exclusive(path, value):
    with path.open('x') as file: json.dump(value, file, ensure_ascii=False, indent=2)


def seed():
    baseline = OUT / 'baseline'
    assert not baseline.exists() and not FIXTURE.exists()
    raw = (SOURCE / 'manifest.json').read_bytes(); project = json.loads(raw)
    package = json.loads((ROOT / 'qa/generated/rhythm-scope/final/package.json').read_text())
    assert project['id'] == package['projectID'] and project['musicRevision'] == 18
    assert package['build'] == '109' and Path(package['fixture']) == SOURCE
    scenario = json.loads((ROOT / 'qa/generated/rhythm-scope/baseline/scenario.json').read_text())
    assert len(project['assets']) == 2
    for asset in project['assets']:
        path = Path(asset['path']); assert not path.is_absolute() and '..' not in path.parts
        assert hashlib.sha256((SOURCE/path).read_bytes()).hexdigest() == asset['checksum']
    lane = next(l for l in project['arrangements'][0]['uses'][0]['addedLanes'] if l['id'] == '055F3787-2B9D-4DD1-9752-56106F8D94F5')
    note = copy.deepcopy(lane['notes'][0]); note.update(beat=8, length=0.5, pitch=66)
    lane['notes'] = [note]
    pattern = next(p for p in project['patterns'] if p['id'] == scenario['patternID'])
    assert pattern['length'] == 4 and len(pattern['notes']) == 1 and pattern['notes'][0]['beat'] == 0
    project['id'] = PROJECT_ID
    baseline.mkdir(parents=True); FIXTURE.mkdir()
    for asset in project['assets']:
        target = FIXTURE / asset['path']; target.parent.mkdir(parents=True, exist_ok=True)
        with target.open('xb') as file: file.write((SOURCE/asset['path']).read_bytes())
    exclusive(FIXTURE/'manifest.json', project); exclusive(baseline/'fixture-initial.json', project)
    exclusive(baseline/'package.json', dict(package, fixture=str(FIXTURE), projectID=PROJECT_ID,
              fixtureSource=str(SOURCE), fixtureSourceSHA256=hashlib.sha256(raw).hexdigest()))
    exclusive(baseline/'scenario.json', dict(projectID=PROJECT_ID, initialRevision=18, source=str(SOURCE),
        fixtureSourceSHA256=hashlib.sha256(raw).hexdigest(), arrangementID=scenario['arrangementID'],
        useA=scenario['useA'], useB=scenario['useB'], ordinaryMIDINodeID=scenario['ordinaryMIDINodeID'],
        rhythmNodeID=scenario['rhythmNodeID'], laneID=lane['id'], patternID=pattern['id'],
        expectedOrdinaryNote=note, expectedSharedNote=pattern['notes'][0],
        ordinary=dict(lengthBeats=64,endBeats=64,startBeat=8,remainingBeats=56,displayCursorBeat=9),
        shared=dict(lengthBeats=4,startBeat=0,remainingBeats=4), generator='rhythm pulse',
        assets=2, scope='QA seed changes only A ordinary lane notes; shared beat0 note preserved; no recording'))
    assert (SOURCE/'manifest.json').read_bytes() == raw
    print(json.dumps({'fixture':str(FIXTURE),'projectID':PROJECT_ID,'revision':18},ensure_ascii=False))


def deny_output(directory):
    package = json.loads((directory / 'package.json').read_text())
    app = Path(package['app']); macos = app / 'Contents/MacOS'
    names = ['circlr-output-worker', 'circlr-au-effect-worker',
             'circlr-au-instrument-worker', 'circlr-output-device-catalog']
    digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
    original = {name: digest(macos / name) for name in names}
    preserved = directory / 'production-helpers'; preserved.mkdir()
    worker = macos / names[0]
    shutil.copy2(worker, preserved / worker.name)
    assert digest(preserved / worker.name) == original[worker.name]
    source = directory / 'deny-output.c'
    with source.open('x') as file: file.write('int main(void){return 78;}\n')
    def run(command):
        return subprocess.run(command, check=True, capture_output=True, text=True, timeout=60).stdout
    run(['xcrun', 'clang', '-Os', str(source), '-o', str(worker)])
    run(['codesign', '--force', '--sign', '-', str(worker)])
    assert 'Mach-O' in run(['file', str(worker)])
    run(['codesign', '--force', '--deep', '--sign', '-', str(app)])
    run(['codesign', '--verify', '--deep', '--strict', str(app)])
    current = {name: digest(macos / name) for name in names}
    assert all(current[name] == original[name] for name in names[1:])
    assert current[worker.name] != original[worker.name]
    exclusive(directory / 'qa-injection.json', dict(
        qaOnlyMock=True, candidate=directory.name, denyOutput=True, outputWorkerExit=78,
        scope='UI-only QA; authored C stub contains no audio calls; other three helpers preserved',
        productionHelperSHA256=original, packagedHelperSHA256=current,
        preservedOutputWorker=str(preserved / worker.name),
        stubSourceSHA256=digest(source), strictSignatureVerified=True))


def main():
    parser = argparse.ArgumentParser(description=__doc__); parser.add_argument('--candidate'); parser.add_argument('--deny-output', action='store_true'); args=parser.parse_args()
    if not args.candidate:
        assert not args.deny_output, '--deny-output requires a new candidate'
        seed(); return
    assert args.candidate != 'baseline'
    before = (FIXTURE/'manifest.json').read_bytes(); assert json.loads(before)['id'] == PROJECT_ID
    spec = importlib.util.spec_from_file_location('packager',Path(__file__).with_name('prepare-automation-workspace-qa.py'))
    p = importlib.util.module_from_spec(spec); spec.loader.exec_module(p)
    p.NAME='midi-generation'; p.BUILD='111'; p.OUT=OUT; p.APP=OUT/'써클러 통합 검증.app'; p.FIXTURE=FIXTURE
    argv = sys.argv
    try:
        sys.argv = [argv[0], '--candidate', args.candidate]
        p.main()
    finally:
        sys.argv = argv
    if args.deny_output: deny_output(OUT / args.candidate)
    assert (FIXTURE/'manifest.json').read_bytes() == before


if __name__ == '__main__': main()
