#!/usr/bin/env python3
"""Read-only build109 shared-rhythm native evidence; acceptance awaits final captures."""
import hashlib
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'qa/generated/rhythm-scope'
CANDIDATE = 'final'
spec = importlib.util.spec_from_file_location('compact_checks', Path(__file__).with_name('check-midi-compact-evidence.py'))
c = importlib.util.module_from_spec(spec); spec.loader.exec_module(c)


def load(name):
    return json.loads((OUT / (name + '.json')).read_text())


def expected_music(baseline, scenario, edited=False):
    expected = c.music(baseline)
    pattern = next(p for p in expected['patterns'] if p['id'] == scenario['patternID'])
    note = next(n for n in pattern['notes'] if n['id'] == scenario['noteID'])
    assert note['pitch'] == scenario['originalPitch'] == 66
    if edited:
        note['pitch'] = scenario['editedPitch']
        assert note['pitch'] == 67
    return expected


def capture(name, package, revision, baseline, scenario, edited=False):
    value = load(CANDIDATE + '/' + name)
    c.guard(value, package, revision)
    assert c.music(value['manifest']) == expected_music(baseline, scenario, edited), name
    return value


def restored_files(package, restored, reopened, scenario):
    fixture = Path(package['fixture'])
    assert restored['manifest'] == reopened['manifest'] == json.loads((fixture / 'manifest.json').read_text())
    assert hashlib.sha256((Path(scenario['source']) / 'manifest.json').read_bytes()).hexdigest() == scenario['sourceSHA256']
    for asset in reopened['manifest']['assets']:
        path = Path(asset['path']); assert not path.is_absolute() and '..' not in path.parts
        assert hashlib.sha256((fixture / path).read_bytes()).hexdigest() == asset['checksum']
    job = reopened['state']['job']
    assert job['kind'] == 'open' and job['state'] == 'completed' and job['path'] == str(fixture)


def main():
    scenario = load('baseline/scenario')
    initial = load('baseline/fixture-initial')
    assert initial['musicRevision'] == scenario['initialRevision'] == 14
    assert len(initial['assets']) == 2
    expected_music(initial, scenario)
    package = load(CANDIDATE + '/package')
    assert package['build'] == '109'
    revisions = {'before':16, 'edited':17, 'shared-b':17, 'undo':18, 'restored':18, 'reopened':18}
    captures = {name:capture(name, package, revision, initial, scenario, name in ['edited','shared-b'])
                for name,revision in revisions.items()}
    assert captures['before']['state']['selection']['music']['useID'] == scenario['useA']
    assert captures['shared-b']['state']['selection']['music']['useID'] == scenario['useB']
    for name in ['shared','shared-b']:
        text = (OUT / CANDIDATE / (name + '.ax.txt')).read_text()
        assert 'menu button Description: 공유 리듬 MIDI' in text
        assert any(' text ' in row and scenario['patternName'] in row and '노트·클립은 모든 사용에 반영' in row for row in text.splitlines())
    shared_b = (OUT / CANDIDATE / 'shared-b.ax.txt').read_text()
    assert any('Description: MIDI 음높이' in row and 'Value: 67' in row for row in shared_b.splitlines())
    ordinary = (OUT / CANDIDATE / 'ordinary.ax.txt').read_text()
    assert 'menu button Description: MIDI, Help:' in ordinary
    assert 'menu button Description: 공유 리듬 MIDI' not in ordinary
    assert not any(' text ' in row and '노트·클립은 모든 사용에 반영' in row for row in ordinary.splitlines())
    for name in ['shared', 'shared-b', 'ordinary']:
        assert (OUT / CANDIDATE / (name + '.jpg')).read_bytes().startswith(b'\xff\xd8\xff')
    restored_files(package, captures['restored'], captures['reopened'], scenario)
    print(json.dumps(dict(status='passed', candidate=CANDIDATE, finalCandidateAccepted=True,
        snapshots=6, pitchSequence=[66,67,66], sharedBObserved=True, ordinaryBannerAbsent=True,
        strictReopenEquality=True, assets=2, physicalAudioAttempts=0)))


if __name__ == '__main__':
    main()
