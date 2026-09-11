#!/usr/bin/env python3
"""Read-only native MIDI append evidence; baseline is an isolated seed, not a native capture."""
import argparse
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import uuid

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'qa/generated/midi-generation'
spec = importlib.util.spec_from_file_location('compact_checks', Path(__file__).with_name('check-midi-compact-evidence.py'))
c = importlib.util.module_from_spec(spec)
spec.loader.exec_module(c)


def load(path):
    return json.loads(path.read_text())


def target(manifest, scenario, shared):
    if shared:
        return next(p for p in manifest['patterns'] if p['id'] == scenario['patternID'])
    arrangement = next(a for a in manifest['arrangements'] if a['id'] == scenario['arrangementID'])
    use = next(u for u in arrangement['uses'] if u['id'] == scenario['useA'])
    return next(lane for lane in use['addedLanes'] if lane['id'] == scenario['laneID'])


def ordinary_span(seed, scenario):
    # This fixture has no local meter changes or node length override. Resolve
    # the initial seed's 16 bars at inherited 4/4 instead of the UI fallback 32.
    arrangement = next(a for a in seed['arrangements'] if a['id'] == scenario['arrangementID'])
    use = next(u for u in arrangement['uses'] if u['id'] == scenario['useA'])
    section = next(s for s in seed['sections'] if s['id'] == use['sectionID'])
    node = next(n for n in use['graphEdits']['addedNodes'] if n['id'] == scenario['ordinaryMIDINodeID'])
    assert node.get('lengthBeats') is None and not section['meterChanges']
    for scope in [section, use, node]:
        assert scope['settings']['meter']['source'] == 'inherit'
    meter = seed['global']['meter']
    assert meter == dict(numerator=4, denominator=4)
    end = use.get('barsOverride', section['bars']) * meter['numerator'] * 4 / meter['denominator']
    start = scenario['expectedOrdinaryNote']['beat']
    assert (start, end) == (8, 64)
    return int(start), int(end - start)


def expected_append(seed, actual, scenario, shared, generator):
    expected = c.music(seed)
    lane = target(expected, scenario, shared)
    old = copy.deepcopy(lane['notes'])
    assert old == [scenario['expectedSharedNote' if shared else 'expectedOrdinaryNote']]
    observed = target(actual, scenario, shared)['notes']
    scope = scenario['shared' if shared else 'ordinary']
    start, count = (scope['startBeat'], scope['remainingBeats']) if shared else ordinary_span(seed, scenario)
    assert (start, count) == ((0, 4) if shared else (8, 56))
    assert len(observed) == len(old) + count
    assert observed[:len(old)] == old, 'Existing notes must retain every field and ID'
    ids = {note['id'] for note in old}
    for index, note in enumerate(observed[len(old):]):
        uuid.UUID(note['id'])
        assert note['id'] not in ids
        ids.add(note['id'])
        if generator == 'pulse':
            length, pitch, velocity = 0.2, 60, 110 if index % 4 == 0 else 90
        else:
            assert generator == 'bass'
            scale = seed['global']['scale']
            intervals = sorted(scale['intervals'])
            degree = [0, 5, 3, 4][(index // 4) % 4] % len(intervals)
            pitch = 24 + scale['root'] + intervals[degree]
            length, velocity = 0.72, 96 if index % 2 == 0 else 82
        assert note == dict(id=note['id'], beat=start + index, length=length,
                            pitch=pitch, velocity=velocity)
    lane['notes'] = copy.deepcopy(observed)
    return expected


def check_menu(path, range_label):
    text = path.read_text()
    assert range_label in text
    assert '기존 노트 유지 · 겹쳐 추가' in text
    lines = text.splitlines()
    actions = []
    for label in ['7th 코드 추가', '아르페지오 추가', '베이스 추가', '리듬 펄스 추가']:
        matches = [line for line in lines if 'ID: menuAction:' in line and label in line]
        assert len(matches) == 1, label
        actions.extend(matches)
    assert len({len(line) - len(line.lstrip()) for line in actions}) == 1
    assert not any('ID: menuAction:' in line and '패턴 추가' in line for line in lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--candidate', default='final4')
    args = parser.parse_args()
    assert args.candidate == 'final4', 'Only final4 is an acceptance candidate; earlier candidates are preserved separately'
    final = OUT / args.candidate
    seed = load(OUT / 'baseline/fixture-initial.json')
    scenario = load(OUT / 'baseline/scenario.json')
    package = load(final / 'package.json')
    assert package['build'] == '111'
    revision = scenario['initialRevision']
    assert seed['musicRevision'] == revision == 18
    assert seed['id'] == scenario['projectID'] == package['projectID']
    injection = load(final / 'qa-injection.json')
    assert injection['qaOnlyMock'] is True and injection['denyOutput'] is True
    assert injection['candidate'] == args.candidate and injection['outputWorkerExit'] == 78
    assert injection['strictSignatureVerified'] is True
    helpers = {'circlr-output-worker', 'circlr-au-effect-worker',
               'circlr-au-instrument-worker', 'circlr-output-device-catalog'}
    assert set(injection['productionHelperSHA256']) == set(injection['packagedHelperSHA256']) == helpers
    for helper in helpers:
        binary = Path(package['app']) / 'Contents/MacOS' / helper
        assert hashlib.sha256(binary.read_bytes()).hexdigest() == injection['packagedHelperSHA256'][helper]
        if helper != 'circlr-output-worker':
            assert injection['productionHelperSHA256'][helper] == injection['packagedHelperSHA256'][helper]
    assert hashlib.sha256(Path(injection['preservedOutputWorker']).read_bytes()).hexdigest() == injection['productionHelperSHA256']['circlr-output-worker']
    stub = final / 'deny-output.c'
    assert hashlib.sha256(stub.read_bytes()).hexdigest() == injection['stubSourceSHA256']
    assert stub.read_text().strip() == 'int main(void){return 78;}'
    original = c.music(seed)
    revisions = {'before':28, 'ordinary-added':29, 'ordinary-undo':30, 'shared-added':31,
                 'shared-b':31, 'shared-undo':32, 'restored':32, 'reopened':32}
    captures = {}
    for name, delta in revisions.items():
        capture = load(final / (name + '.json'))
        c.guard(capture, package, delta)
        expected = original
        if name in ['ordinary-added', 'shared-added', 'shared-b']:
            shared_scope = name in ['shared-added', 'shared-b']
            generator = 'pulse'
            expected = expected_append(seed, capture['manifest'], scenario, shared_scope, generator)
        assert c.music(capture['manifest']) == expected, name
        captures[name] = capture
    rapid = load(final / 'rapid-keys.json')
    c.guard(rapid, package, 28)
    assert c.music(rapid['manifest']) == original
    rapid_ax = (final / 'rapid-keys.ax.txt').read_text()
    focus = rapid_ax.split('The focused UI element is')[-1]
    assert 'search text field' in focus and 'Value: MIDI ,' in focus
    assert '명령 또는 서클 이름 검색' in focus
    rapid_paste = load(final / 'rapid-paste.json')
    c.guard(rapid_paste, package, 28)
    assert c.music(rapid_paste['manifest']) == original
    paste_ax = (final / 'rapid-paste.ax.txt').read_text()
    paste_focus = paste_ax.split('The focused UI element is')[-1]
    assert 'search text field' in paste_focus and 'Value: 리듬 펄스,' in paste_focus
    assert '명령 또는 서클 이름 검색' in paste_focus

    assert c.music(captures['shared-added']['manifest']) == c.music(captures['shared-b']['manifest'])
    assert captures['shared-b']['state']['selection']['music']['useID'] == scenario['useB']
    check_menu(final / 'ordinary-menu.ax.txt', '9박부터 · 남은 56박')
    check_menu(final / 'shared-menu.ax.txt', '1박부터 · 남은 4박')
    for name, span in [('ordinary-command', '9박부터 · 남은 56박'),
                       ('shared-command', '1박부터 · 남은 4박')]:
        text = (final / (name + '.ax.txt')).read_text()
        pulse = [line for line in text.splitlines() if 'button' in line and 'MIDI 패턴 생성 · 리듬 펄스' in line]
        assert len(pulse) == 1 and '(selected)' in pulse[0], name
        assert span in pulse[0] and '기존 노트 유지 · 겹쳐 추가' in pulse[0], name
        assert 'Value: 리듬 펄스' in text and '명령 또는 서클 이름 검색' in text, name
        assert 'search text field' in text.split('The focused UI element is')[-1], name
    shared = (final / 'shared-b.ax.txt').read_text()
    assert '공유 리듬 MIDI' in shared and '노트·클립은 모든 사용에 반영' in shared
    fixture = Path(package['fixture'])
    source = Path(scenario['source'])
    assert hashlib.sha256((source / 'manifest.json').read_bytes()).hexdigest() == scenario['fixtureSourceSHA256']
    for asset in seed['assets']:
        relative = Path(asset['path'])
        assert relative.parts and not relative.is_absolute() and '..' not in relative.parts
        for root in [fixture, source]:
            assert hashlib.sha256((root / relative).read_bytes()).hexdigest() == asset['checksum']
    assert captures['restored']['manifest'] == captures['reopened']['manifest'] == load(fixture / 'manifest.json')
    job = captures['reopened']['state']['job']
    assert job['kind'] == 'open' and job['state'] == 'completed' and job['progress'] == 1
    assert job['path'] == str(fixture)
    print(json.dumps(dict(status='passed', candidate=args.candidate, snapshots=len(captures) + 2, rapidASCIIQueryVerified=True, rapidKoreanPasteVerified=True, koreanIMECompositionVerified=False, qaDenyOutputStub=True,
        baselineEvidence='seed only', generators=['pulse'], ordinaryAppended=ordinary_span(seed, scenario)[1], sharedAppended=4,
        existingNotesPreserved=True, sharedBObserved=True, strictUndoMusic=True,
        strictReopenEquality=True, assets=2, physicalAudioAttempts=0)))


if __name__ == '__main__':
    main()
