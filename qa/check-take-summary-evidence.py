#!/usr/bin/env python3
"""Read-only build107 final2 AX selection evidence; earlier failed candidate stays excluded."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'qa/generated/take-summary'
spec = importlib.util.spec_from_file_location('compact_checks', Path(__file__).with_name('check-midi-compact-evidence.py'))
c = importlib.util.module_from_spec(spec)
spec.loader.exec_module(c)

def load(name):
    return json.loads((OUT / (name + '.json')).read_text())

def menu(name):
    text = (OUT / (name + '.ax.txt')).read_text()
    return [line.strip() for line in text.splitlines() if 'ID: menuAction:' in line or 'ID: recorded-take-' in line]

def use(manifest, scenario):
    arrangement = next(a for a in manifest['arrangements'] if a['id'] == scenario['arrangementID'])
    return next(u for u in arrangement['uses'] if u['id'] == scenario['useID'])

def check_menu(name, matched_index, visible_ids):
    lines = menu(name)
    assert len(lines) == 3, (name, lines)
    for index, line in enumerate(lines):
        assert 'ID: recorded-take-' + visible_ids[index] in line, (name, line)
        assert '녹음 테이크' in line and '클립 1개' in line, (name, line)
        assert ('노트 1개' if index == 2 else '노트 0개') in line, (name, line)
        assert ('현재 내용과 일치' in line) == (index == matched_index), (name, line)

def main():
    scenario = load('baseline/scenario')
    packages = {phase: load(phase + '/package') for phase in ['baseline', 'final2']}
    assert packages['baseline']['build'] == '106' and packages['final2']['build'] == '107'
    assert packages['baseline']['fixture'] == packages['final2']['fixture']
    baseline = load('baseline/baseline')
    c.guard(baseline, packages['baseline'], 14)
    initial = c.music(baseline['manifest'])
    assert initial['takes'] == load('baseline/fixture-initial')['takes']
    assert len(initial['takes']) == 5
    takes = {take['id']: take for take in initial['takes']}
    current, short, mixed = [takes[i] for i in scenario['visibleTakeIDs']]
    assert short['lane']['audio'][0]['id'] == current['lane']['audio'][0]['id'] == scenario['sameClipID']
    assert short['lane']['audio'][0]['duration'] == 16 and short['lane']['audio'][0]['sourceStart'] == 0
    assert len(mixed['lane']['notes']) == len(mixed['lane']['audio']) == 1
    old_menu = menu('baseline/menu')
    assert len(old_menu) == 4 and all('녹음 테이크' in line and '노트 ' not in line and '클립 ' not in line for line in old_menu)
    revisions = dict(initial=16, applied=17, switched=18, **{'undo-switch':19}, reselected=20, undo=22, restored=22, reopened=22)
    captures = {name: load('final2/' + name) for name in revisions}
    for name, capture in captures.items():
        c.guard(capture, packages['final2'], revisions[name])
        expected = copy.deepcopy(initial)
        if name in ['applied', 'undo-switch', 'switched', 'reselected']:
            selected = short if name in ['applied', 'undo-switch'] else current
            use(expected, scenario)['laneOverrides'][scenario['laneID']] = copy.deepcopy(selected['lane'])
        assert c.music(capture['manifest']) == expected, name
        assert capture['manifest']['takes'] == initial['takes'], name
    for name, matched in [('menu', 0), ('applied-menu', 1), ('undo-switch-menu', 1), ('undo-menu', 0), ('compact-menu', 0)]:
        check_menu('final2/' + name, matched, scenario['visibleTakeIDs'])
    # Compact JPEG shows the closed header; open menus are verified by AX only.
    compact = OUT / 'final2/compact.jpg'
    assert compact.read_bytes().startswith(b'\xff\xd8\xff')
    fixture = Path(packages['final2']['fixture'])
    assert captures['restored']['manifest'] == captures['reopened']['manifest'] == json.loads((fixture / 'manifest.json').read_text())
    for asset in initial['assets']:
        path = Path(asset['path'])
        assert not path.is_absolute() and '..' not in path.parts
        for folder in [fixture, fixture.with_name('studio.circlr')]:
            assert hashlib.sha256((folder / path).read_bytes()).hexdigest() == asset['checksum']
    assert hashlib.sha256((fixture.with_name('studio.circlr') / 'manifest.json').read_bytes()).hexdigest() == packages['final2']['sourceSHA256'] == packages['baseline']['sourceSHA256']
    job, completed = load('final2/reopen-job'), load('final2/reopen-completed')
    assert job['jobID'] == completed['job']['id'] and completed['revision'] == 22
    assert completed['job']['kind'] == 'open' and completed['job']['state'] == 'completed' and completed['job']['path'] == str(fixture)
    print(json.dumps(dict(status='passed', baselineSnapshots=1, finalSnapshots=8, menuVisibleTakes=3,
        scopedOutTakes=2, preservedTakes=5, assets=2, physicalAudioAttempts=0, strictReopenEquality=True, candidate='final2', keyboardSelectionVerified=False, menuPixelCaptureAvailable=False)))

if __name__ == '__main__':
    main()
