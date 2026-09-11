#!/usr/bin/env python3
"""Create an exclusive shared-rhythm QA fixture, or package a prebuilt build109 app."""
import argparse
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import uuid

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'qa/generated/rhythm-scope'
SOURCE = Path.home() / 'Library/Application Support/circlr-integration-qa/fixtures/studio.circlr'
FIXTURE = SOURCE.with_name('rhythm-scope.circlr')


def ident(name=''):
    return str(uuid.uuid5(uuid.NAMESPACE_URL, 'circlr-integration-qa/rhythm-scope' + name)).upper()


def exclusive(path, data):
    with path.open('x') as handle:
        json.dump(data, handle, ensure_ascii=False, indent=2)
        handle.write('\n')


def seed():
    baseline = OUT / 'baseline'
    assert not baseline.exists() and not FIXTURE.exists(), 'Preserve existing evidence'
    raw = (SOURCE / 'manifest.json').read_bytes()
    project = json.loads(raw)
    arrangement = project['arrangements'][0]
    use = arrangement['uses'][0]
    # Reuse the valid existing use graph, including its instrument/MIDI/rhythm paths.
    nodes = use['graphEdits']['addedNodes']
    rhythm = next(n for n in nodes if 'rhythmMIDI' in n['content'])
    track = rhythm['content']['rhythmMIDI']['trackID']
    lane = next(l for l in use['addedLanes'] if l['trackID'] == track)
    midi = next(n for n in nodes if n['content'].get('midi', {}).get('laneID') == lane['id'])
    assert project['global']['rhythm'] == {} and not project['patterns']
    pattern = dict(id=ident('/pattern'), name='밤하늘을 가로지르는 긴 한국어 이름의 공유 리듬 패턴 · 두 섹션에서 함께 편집',
                   trackID=track, length=4, meter=dict(numerator=4, denominator=4), audio=[],
                   notes=[dict(id=ident('/note'), beat=0, length=0.5, pitch=66, velocity=64)])
    project['patterns'] = [pattern]
    project['global']['rhythm'] = dict(patternID=pattern['id'])
    second = copy.deepcopy(use); second['id'] = ident('/second-use'); second['name'] = '공유 리듬 확인 B'
    use['name'] = '공유 리듬 편집 A'
    arrangement['uses'].append(second)
    arrangement['layout']['positions'][second['id']] = dict(x=700, y=0)
    project['id'] = ident()
    reference = json.loads((FIXTURE.with_name('take-search.circlr') / 'manifest.json').read_text())
    project['hierarchyView'] = copy.deepcopy(reference['hierarchyView'])
    project['hierarchyView']['selection'] = {'music':dict(arrangementID=arrangement['id'], useID=use['id'], nodeID=rhythm['id'])}
    project['hierarchyView'].pop('workspace', None); project['hierarchyView'].pop('editor', None)
    for asset in project['assets']:
        path = Path(asset['path'])
        assert path.parts and not path.is_absolute() and '..' not in path.parts
        assert hashlib.sha256((SOURCE / path).read_bytes()).hexdigest() == asset['checksum']
    baseline.mkdir(parents=True); FIXTURE.mkdir()
    for asset in project['assets']:
        path = Path(asset['path']); target = FIXTURE / path
        target.parent.mkdir(parents=True, exist_ok=True)
        with target.open('xb') as handle:
            handle.write((SOURCE / path).read_bytes())
        assert hashlib.sha256(target.read_bytes()).hexdigest() == asset['checksum']
    exclusive(FIXTURE / 'manifest.json', project)
    exclusive(baseline / 'fixture-initial.json', project)
    package = json.loads((ROOT / 'qa/generated/take-search/final3/package.json').read_text())
    assert package['build'] == '108'
    package.update(fixture=str(FIXTURE), projectID=ident(), sourceSHA256=hashlib.sha256(raw).hexdigest())
    exclusive(baseline / 'package.json', package)
    exclusive(baseline / 'scenario.json', dict(scenarioID='rhythm-shared-content-109', scope='Authored QA fixture only',
        source=str(SOURCE), sourceSHA256=hashlib.sha256(raw).hexdigest(), baselineBuild='108', candidateBuild='109',
        initialRevision=project['musicRevision'], arrangementID=arrangement['id'], useA=use['id'], useB=second['id'],
        rhythmNodeID=rhythm['id'], ordinaryMIDINodeID=midi['id'], patternID=pattern['id'], noteID=pattern['notes'][0]['id'],
        originalPitch=66, editedPitch=67, patternName=pattern['name'], assets=len(project['assets']),
        expected='A note edit changes shared pattern to pitch67; B sees67; Undo restores66; ordinary MIDI stays unchanged',
        native=['compact long name and scope text', 'edit A note pitch66 to67', 'open B inherited rhythm and confirm67',
                'Undo and confirm66 in A/B', 'ordinary MIDI has no shared-pattern banner', 'save/reopen preserves shared pattern'],
        physicalAudioAttempts=0))
    assert (SOURCE / 'manifest.json').read_bytes() == raw
    print(json.dumps(dict(fixture=str(FIXTURE), patternID=pattern['id'], useA=use['id'], useB=second['id']), ensure_ascii=False))


def main():
    parser = argparse.ArgumentParser(description=__doc__); parser.add_argument('--candidate'); args = parser.parse_args()
    if not args.candidate:
        seed(); return
    assert args.candidate != 'baseline'
    before = (FIXTURE / 'manifest.json').read_bytes(); assert json.loads(before)['id'] == ident()
    spec = importlib.util.spec_from_file_location('packager', Path(__file__).with_name('prepare-automation-workspace-qa.py'))
    p = importlib.util.module_from_spec(spec); spec.loader.exec_module(p)
    p.NAME = 'rhythm-scope'; p.BUILD = '109'; p.OUT = OUT; p.APP = OUT / '써클러 통합 검증.app'; p.FIXTURE = FIXTURE
    p.main()
    assert (FIXTURE / 'manifest.json').read_bytes() == before


if __name__ == '__main__':
    main()
