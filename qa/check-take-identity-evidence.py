#!/usr/bin/env python3
"""Read-only take identity native evidence checker; missing artifacts never pass."""
import argparse
import copy
import hashlib
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'qa/generated/take-identity'
spec = importlib.util.spec_from_file_location('compact_checks', Path(__file__).with_name('check-midi-compact-evidence.py'))
c = importlib.util.module_from_spec(spec)
spec.loader.exec_module(c)


def load(path):
    return json.loads(path.read_text())


def scoped_use(manifest, scenario):
    arrangement = next(a for a in manifest['arrangements'] if a['id'] == scenario['arrangementID'])
    return next(u for u in arrangement['uses'] if u['id'] == scenario['useID'])


def rows(text):
    return [line for line in text.splitlines() if 'button' in line and '녹음 테이크' in line and '노트' in line]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--candidate', default='final')
    args = parser.parse_args()
    assert args.candidate not in ['.', '..', 'baseline'] and '/' not in args.candidate
    final = OUT / args.candidate
    scenario = load(OUT / 'baseline/scenario.json')
    seed = load(OUT / 'baseline/fixture-initial.json')
    baseline_package = load(OUT / 'baseline/package.json')
    package = load(final / 'package.json')
    revision = scenario['initialRevision']
    assert str(baseline_package['build']) == str(scenario['baselineBuild'])
    assert str(package['build']) == str(scenario['candidateBuild'])
    assert package['fixture'] == baseline_package['fixture']
    original = c.music(seed)
    assert seed['musicRevision'] == revision and seed['id'] == baseline_package['projectID']
    assert len(seed['takes']) == 5 and len(scenario['visibleTakeIDs']) == 3
    visible = [next(t for t in seed['takes'] if t['id'] == identifier) for identifier in scenario['visibleTakeIDs']]
    assert len(set(scenario['visibleTakeIDs'])) == 3
    scoped = [t['id'] for t in seed['takes'] if t['arrangementID'] == scenario['arrangementID']
              and t['useID'] == scenario['useID'] and t['targetLaneID'] == scenario['laneID']]
    assert scoped == scenario['visibleTakeIDs']
    assert {t['id'] for t in seed['takes']} - set(scoped) == set(scenario['hiddenTakeIDs'])
    assert all(t['name'] == '녹음 테이크' for t in visible)
    target = visible[1]
    assert target['lane']['audio'][0]['id'] == scenario['sameClipID']
    assert target['id'] == scenario['targetTakeID']
    assert [item['takeID'] for item in scenario['eligible']] == scenario['visibleTakeIDs']
    for index, take in enumerate(visible):
        assert scenario['eligible'][index]['ordinal'] == index + 1
        assert take['lane'] == scenario['eligible'][index]['expectedLane']
        assert take['lane']['notes'] == [] and len(take['lane']['audio']) == 1
        assert take['lane']['audio'][0]['duration'] == scenario['sameDurationSeconds'] == 32
        assert take['lane']['audio'][0]['gain'] == scenario['eligibleAudioGains'][index]
    assert scenario['eligibleAudioGains'] == [0.25, 0.5, 0.75]
    assert scenario['currentLane']['audio'][0]['gain'] == scenario['currentAudioGain'] == 1
    changed = copy.deepcopy(original)
    scoped_use(changed, scenario)['laneOverrides'][scenario['laneID']] = copy.deepcopy(target['lane'])
    assert changed != original
    captures = {}
    for name, delta in [('before', 0), ('applied', 1), ('undo', 2), ('restored', 2), ('reopened', 2)]:
        capture = load(final / (name + '.json'))
        c.guard(capture, package, revision + delta)
        assert c.music(capture['manifest']) == (changed if name == 'applied' else original), name
        assert capture['manifest']['takes'] == seed['takes'], name
        captures[name] = capture
    all_text = (final / 'all-takes.ax.txt').read_text()
    all_rows = rows(all_text)
    assert len(all_rows) == 3
    for number, row in enumerate(all_rows, 1):
        assert f'#{number} · 녹음 테이크' in row
        assert '현재 내용과 일치' not in row
        assert '노트 0개' in row and '클립 1개' in row
    filtered = (final / 'number-filter.ax.txt').read_text()
    found = rows(filtered)
    assert len(found) == 1 and '#2 · 녹음 테이크' in found[0]
    assert '#1 · 녹음 테이크' not in filtered and '#3 · 녹음 테이크' not in filtered
    assert 'Value: #2' in filtered and '(selected)' in found[0]
    assert 'search text field' in filtered.split('The focused UI element is')[-1]
    for name, selected in [('keyboard-selection', 2), ('reset', 1)]:
        text = (final / (name + '.ax.txt')).read_text()
        observed_rows = rows(text)
        assert len(observed_rows) == 3, name
        for number, row in enumerate(observed_rows, 1):
            assert f'#{number} · 녹음 테이크' in row, name
            assert ('(selected)' in row) == (number == selected), name
            assert '노트 0개' in row and '클립 1개' in row
            assert '현재 내용과 일치' not in row
        fields = [line for line in text.splitlines() if 'search text field' in line]
        assert fields and all('Value:' not in line for line in fields), name
        assert 'search text field' in text.split('The focused UI element is')[-1], name
    for name in ['all-takes', 'number-filter', 'keyboard-selection', 'reset']:
        assert (final / (name + '.jpg')).read_bytes().startswith(b'\xff\xd8\xff')
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
    print(json.dumps(dict(status='passed', candidate=args.candidate, snapshots=5, baselineEvidence='seed manifest only',
        numberedScopedTakes=3, filteredNumber=2, axSnapshots=4, appliedTakeID=target['id'],
        strictUndoMusic=True, strictReopenEquality=True, preservedAssets=2,
        physicalAudioAttempts=0, inputMethodEvidence='native operator observation required; snapshots prove result only')))


if __name__ == '__main__':
    main()
