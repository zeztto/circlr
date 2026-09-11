#!/usr/bin/env python3
"""Check isolated build103 UI evidence, trim delta, Undo and reopen integrity."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'qa/generated/audio-compact'
spec = importlib.util.spec_from_file_location('checks', Path(__file__).with_name('check-midi-compact-evidence.py'))
c = importlib.util.module_from_spec(spec)
spec.loader.exec_module(c)

def load(name):
    return json.loads((OUT / (name + '.json')).read_text())

def main():
    package = load('final/package')
    assert package['build'] == '103'
    assert 'AA06CD29-088B-3429-B2C0-D2B218E216AB' in package['uuid']
    initial = load('baseline/fixture-initial')
    values = {name: load('final/' + name) for name in ['draft', 'trim', 'restored', 'reopened']}
    for name, revision in [('draft',36), ('trim',37), ('restored',38), ('reopened',38)]:
        value = values[name]
        c.guard(value, package, revision)
        expected = c.music(initial)
        if name == 'trim':
            lane_id = 'C02E0506-5351-553D-992A-688B212C4D62'
            lane = copy.deepcopy(next(l for s in expected['sections'] for l in s['lanes'] if l['id'] == lane_id))
            lane['audio'][0]['sourceStart'] = 0.1
            lane['audio'][0]['duration'] = 31.9
            expected['arrangements'][0]['uses'][0]['laneOverrides'][lane_id] = lane
        assert c.music(value['manifest']) == expected, name
    assert values['restored']['manifest'] == values['reopened']['manifest']
    fixture = Path(package['fixture'])
    assert json.loads((fixture / 'manifest.json').read_text()) == values['reopened']['manifest']
    for asset in initial['assets']:
        path = Path(asset['path'])
        assert not path.is_absolute() and '..' not in path.parts
        assert hashlib.sha256((fixture / path).read_bytes()).hexdigest() == asset['checksum']
    assert hashlib.sha256((fixture.with_name('studio.circlr') / 'manifest.json').read_bytes()).hexdigest() == package['sourceSHA256']
    for name in ['draft', 'draft-wide', 'draft-return']:
        ax = (OUT / 'final' / (name + '.ax.txt')).read_text()
        focus = ax.split('The focused UI element is')[-1]
        assert 'Description: 오디오 원본 시작 초' in focus and 'Value: 0.' in focus
    invalid = (OUT / 'final/invalid.ax.txt').read_text().split('The focused UI element is')[-1]
    assert 'Description: 오디오 원본 시작 초' in invalid and 'Value: 999' in invalid
    last = (OUT / 'final/last-compact.ax.txt').read_text()
    assert 'Selected text: ```\n120\n```' in last and 'Description: 오디오 원본 BPM' in last
    job = load('final/reopen-job')
    done = load('final/reopen-completed')
    assert done['job']['id'] == job['jobID'] and done['job']['state'] == 'completed'
    assert done['revision'] == 38 and done['job']['path'] == str(fixture)
    print(json.dumps(dict(status='passed', snapshots=4, assets=2, physicalAudioAttempts=0)))

if __name__ == '__main__':
    main()
