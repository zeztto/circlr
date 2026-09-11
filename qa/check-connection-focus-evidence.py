#!/usr/bin/env python3
"""Check build104 focus evidence separately from untested cable/audio operations."""
import hashlib
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'qa/generated/connection-focus'
spec = importlib.util.spec_from_file_location('checks', Path(__file__).with_name('check-midi-compact-evidence.py'))
c = importlib.util.module_from_spec(spec)
spec.loader.exec_module(c)

def load(name):
    return json.loads((OUT / (name + '.json')).read_text())

def workspace(value):
    return value['manifest']['hierarchyView']['workspace']['connection']

def main():
    groups = {
        'baseline': ['compact'],
        'final': ['search-roundtrip', 'list-roundtrip'],
        'final2': ['list-jump', 'reconnect', 'target-roundtrip'],
        'final3': ['target-roundtrip', 'search-roundtrip', 'reconnect', 'cancelled', 'reopened'],
    }
    initial = load('baseline/fixture-initial')
    values = {}
    for phase, names in groups.items():
        package = load(phase + '/package')
        assert package['build'] == ('103' if phase == 'baseline' else '104')
        for name in names:
            value = load(phase + '/' + name)
            c.guard(value, package, 36)
            assert c.music(value['manifest']) == c.music(initial), (phase, name)
            values[phase + '/' + name] = value
    package = load('final3/package')
    assert 'B16B8E8C-434B-3D8F-BB19-23EAF5BC3737' in package['uuid']
    baseline = workspace(values['baseline/compact'])
    for name in ['search-roundtrip', 'cancelled', 'reopened']:
        assert workspace(values['final3/' + name]) == baseline
    reconnect = workspace(values['final3/reconnect'])
    assert reconnect == workspace(values['final3/target-roundtrip']) == workspace(values['final2/reconnect'])
    assert reconnect['target'] == reconnect['replacementDestination']
    assert reconnect['replacing']['from'] == reconnect['replacementSource']['node']
    assert reconnect['replacing']['to'] == reconnect['replacementDestination']['node']
    assert reconnect['firstOctant'] == 2 and reconnect['secondOctant'] == 6
    for name in ['search-compact', 'search-wide', 'search-return']:
        ax = (OUT / 'final3' / (name + '.ax.txt')).read_text()
        assert 'Selected text: ```\n출력\n```' in ax and '대상 이름' in ax
    caret = (OUT / 'final3/caret-insert.ax.txt').read_text().split('The focused UI element is')[-1]
    assert '대상 이름' in caret and 'Value: 출X력' in caret
    for name in ['list-jump', 'filter-wide', 'filter-return']:
        ax = (OUT / 'final3' / (name + '.ax.txt')).read_text()
        assert '연결 표시 범위' in ax.split('The focused UI element is')[-1]
    for name in ['target-compact', 'target-wide', 'target-return']:
        ax = (OUT / 'final3' / (name + '.ax.txt')).read_text()
        assert 'Selected:' in ax and 'row (selected)' in ax
    for name in ['wide-loss', 'roundtrip-loss']:
        ax = (OUT / 'baseline' / (name + '.ax.txt')).read_text()
        assert '0 standard window' in ax.split('The focused UI element is')[-1]
    fixture = Path(package['fixture'])
    reopened = values['final3/reopened']['manifest']
    assert values['final3/cancelled']['manifest'] == reopened == json.loads((fixture / 'manifest.json').read_text())
    for asset in initial['assets']:
        path = Path(asset['path'])
        assert not path.is_absolute() and '..' not in path.parts
        assert hashlib.sha256((fixture / path).read_bytes()).hexdigest() == asset['checksum']
    assert hashlib.sha256((fixture.with_name('studio.circlr') / 'manifest.json').read_bytes()).hexdigest() == package['sourceSHA256']
    job, done = load('final3/reopen-job'), load('final3/reopen-completed')
    assert done['job']['id'] == job['jobID'] and done['job']['state'] == 'completed'
    assert done['revision'] == 36 and done['job']['path'] == str(fixture)
    print(json.dumps(dict(status='passed', snapshots=11, finalSnapshots=5, assets=2, physicalAudioAttempts=0)))

if __name__ == '__main__':
    main()
