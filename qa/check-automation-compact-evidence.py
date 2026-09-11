#!/usr/bin/env python3
"""Verify build105 native edits, restoration, focus evidence and fixture integrity."""
import hashlib
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'qa/generated/automation-compact'
spec = importlib.util.spec_from_file_location('checks', Path(__file__).with_name('check-midi-compact-evidence.py'))
c = importlib.util.module_from_spec(spec)
spec.loader.exec_module(c)

def load(name):
    return json.loads((OUT / (name + '.json')).read_text())

def node(manifest):
    return next(n for n in manifest['arrangements'][0]['uses'][0]['graphEdits']['addedNodes']
                if n['id'] == 'mix:7E0D9016-E91D-4325-B807-033F233E32EA')

def main():
    package = load('final/package')
    assert package['build'] == '105'
    assert 'C8CD3657-8610-324F-9055-5248741EC6EB' in package['uuid']
    baseline = load('baseline/compact')
    c.guard(baseline, load('baseline/package'), 22)
    assert len(node(baseline['manifest'])['automation'][0]['points']) == 2
    revisions = {'draft-cancelled':22, 'linear':22, 'point-edited':23, 'point-undo':24,
                 'pan-created':25, 'pan-edited':26, 'pan-undo':28, 'restored':28, 'reopened':28}
    captures = {name: load('final/' + name) for name in revisions}
    point_id = baseline['state']['automationEditor']['selectedPointID']
    pan_id = captures['pan-created']['state']['automationEditor']['selectedPointID']
    assert point_id and pan_id and point_id != pan_id
    for name, value in captures.items():
        c.guard(value, package, revisions[name])
        expected = c.music(baseline['manifest'])
        if name == 'point-edited':
            point = next(p for p in node(expected)['automation'][0]['points'] if p['id'] == point_id)
            assert point['beat'] == 0.25
            point['beat'] = 1.5
        if name in ['pan-created', 'pan-edited']:
            node(expected)['automation'].append(dict(enabled=True, parameter='pan', points=[
                dict(beat=0, id=pan_id, shape='linear', value=0 if name == 'pan-created' else -0.25)]))
        assert c.music(value['manifest']) == expected, name
        editor = value['state']['automationEditor']
        assert editor['visible'] and editor['displayBeats'] == 64
        assert value['manifest']['circleLayout'] == ('freeform' if name == 'linear' else 'orbit')
        if not name.startswith('pan-'):
            assert editor['parameter'] == 'gain' and editor['selectedPointID'] == point_id
    for name in ['draft', 'draft-wide', 'draft-return']:
        focus = (OUT / 'final' / (name + '.ax.txt')).read_text().split('The focused UI element is')[-1]
        assert '오토메이션 위치 박' in focus and 'Value: 2.' in focus
    invalid = (OUT / 'final/invalid.ax.txt').read_text().split('The focused UI element is')[-1]
    assert '오토메이션 볼륨 dB' in invalid and 'Value: 999' in invalid and '입력 범위:' in invalid
    for name, selected, title in [('gain-last','0.00','오토메이션 볼륨 dB'),
                                  ('pan-last','0.00','오토메이션 팬 %'),
                                  ('pan-position','1','오토메이션 위치 박'),
                                  ('numeric-button','1.25','오토메이션 위치 박')]:
        ax = (OUT / 'final' / (name + '.ax.txt')).read_text()
        assert title in ax and 'Selected text: ```\n' + selected + '\n```' in ax
    fixture = Path(package['fixture'])
    reopened = captures['reopened']['manifest']
    assert captures['restored']['manifest'] == reopened == json.loads((fixture / 'manifest.json').read_text())
    for asset in baseline['manifest']['assets']:
        path = Path(asset['path'])
        assert not path.is_absolute() and '..' not in path.parts
        assert hashlib.sha256((fixture / path).read_bytes()).hexdigest() == asset['checksum']
    assert hashlib.sha256((fixture.with_name('studio.circlr') / 'manifest.json').read_bytes()).hexdigest() == package['sourceSHA256']
    job, done = load('final/reopen-job'), load('final/reopen-completed')
    assert done['job']['id'] == job['jobID'] and done['job']['state'] == 'completed'
    assert done['revision'] == 28 and done['job']['path'] == str(fixture)
    print(json.dumps(dict(status='passed', baselineSnapshots=1, finalSnapshots=9, assets=2, physicalAudioAttempts=0)))

if __name__ == '__main__':
    main()
