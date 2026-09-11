#!/usr/bin/env python3
"""Read-only candidate-scoped MIDI compact evidence checks; final2 acceptance is separate."""
import copy
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'qa/generated/midi-compact'


def load(name):
    return json.loads((OUT / (name + '.json')).read_text())


def music(value):
    value = copy.deepcopy(value)
    for key in ['hierarchyView', 'musicRevision', 'circleLayout']: value.pop(key, None)
    colors = value.get('circleColors')
    if colors is not None:
        assert len(colors) % 2 == 0
        value['circleColors'] = {json.dumps(colors[i], sort_keys=True): colors[i+1] for i in range(0, len(colors), 2)}
        assert len(value['circleColors']) * 2 == len(colors)
    return value


def guard(capture, package, revision):
    state = capture['state']; manifest = capture['manifest']
    assert state['runtime']['bundleID'] == 'com.circlr.integrationqa' and state['runtime']['build'] == package['build']
    assert state['projectID'] == manifest['id'] == package['projectID']
    assert state['path'] == package['fixture'] and not state['dirty']
    assert state['revision'] == manifest['musicRevision'] == revision
    assert state['output']['attempts'] == state['audition']['attempts'] == 0
    assert not state['playback']['playing'] and not any(state['recording'][k] for k in ['audio','midi','busy'])
    assert len(manifest['assets']) == 2


def main():
    packages = {phase:load(phase + '/package') for phase in ['baseline','final','final2']}
    assert packages['baseline']['build'] == '99'
    assert packages['final']['build'] == packages['final2']['build'] == '100'
    assert 'DA62630D-4EA0-3F48-9471-122345AAF4B7' in packages['final2']['uuid']
    revisions = {'baseline/wide':30,'baseline/compact':30,'final/compact':30,'final/draft-roundtrip':30,
                 'final/length-edited':31,'final/length-undo':32,'final/invalid-cancelled':32,
                 'final/multi-edited':33,'final/page-before':34,'final/page-roundtrip':34,'final/step-compact':34}
    captures = {name:load(name) for name in revisions}
    original = music(captures['baseline/compact']['manifest'])
    note_id = 'BA8C30C3-3F0E-482A-A108-7A9C829C96AE'
    original_notes = original['arrangements'][0]['uses'][0]['addedLanes'][0]['notes']
    assert len(original_notes) == 3
    for name, capture in captures.items():
        guard(capture, packages[name.split('/')[0]], revisions[name])
        expected = copy.deepcopy(original)
        notes = expected['arrangements'][0]['uses'][0]['addedLanes'][0]['notes']
        if name == 'final/length-edited':
            note = next(n for n in notes if n['id'] == note_id)
            assert note['length'] == 0.5; note['length'] = 1
        elif name == 'final/multi-edited':
            for note in notes: note['pitch'] += 1
        assert music(capture['manifest']) == expected, name
    for name in ['compact','draft-roundtrip','length-edited','length-undo','invalid-cancelled']:
        assert captures['final/'+name]['state']['selectedNoteIDs'] == [note_id]
    selected = {n['id'] for n in original_notes}
    for name in ['multi-edited','page-before','page-roundtrip','step-compact']:
        assert set(captures['final/'+name]['state']['selectedNoteIDs']) == selected
    left = captures['final/page-before']['manifest']['hierarchyView']['workspace']['editor']
    right = captures['final/page-roundtrip']['manifest']['hierarchyView']['workspace']['editor']
    assert left == right and left['orbit'] == {'barsPerPage':4,'page':1,'pitchRows':12,'topPitch':73}
    checks = {'draft-wide':['Description: MIDI 길이 박','Value: 1.'],
              'draft-compact':['Description: MIDI 길이 박','Value: 1.'],
              'invalid-roundtrip':['입력 범위: 1–127','Value: 999']}
    for name, strings in checks.items():
        text = (OUT / 'final' / (name+'.ax.txt')).read_text()
        for string in strings: assert string in text, (name,string)
    fixture = Path(packages['final2']['fixture']); source = fixture.with_name('studio.circlr')
    assert hashlib.sha256((source/'manifest.json').read_bytes()).hexdigest() == packages['final2']['sourceSHA256'] == '12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d'
    for asset in original['assets']:
        path = Path(asset['path']); assert not path.is_absolute() and '..' not in path.parts
        for folder in [fixture,source]:
            assert hashlib.sha256((folder/path).read_bytes()).hexdigest() == asset['checksum']
    final2_revisions = {'step-compact':34,'search-roundtrip':34,'step-edited':35,'step-undone':36,
                        'orbit-draft-roundtrip':36,'saved':36,'reopened':36}
    final2 = {name:load('final2/'+name) for name in final2_revisions}
    for name, capture in final2.items():
        guard(capture, packages['final2'], final2_revisions[name])
        expected = copy.deepcopy(original)
        if name == 'step-edited':
            for note in expected['arrangements'][0]['uses'][0]['addedLanes'][0]['notes']: note['pitch'] += 1
        assert music(capture['manifest']) == expected, name
        assert set(capture['state']['selectedNoteIDs']) == selected, name
    base_editor = final2['step-compact']['manifest']['hierarchyView']['workspace']['editor']
    search_editor = copy.deepcopy(base_editor); search_editor['steps']['rowQuery'] = '66'
    assert final2['search-roundtrip']['manifest']['hierarchyView']['workspace']['editor'] == search_editor
    for name in ['step-undone','orbit-draft-roundtrip','saved','reopened']:
        assert final2[name]['manifest']['hierarchyView']['workspace']['editor'] == base_editor
    assert final2['saved']['manifest'] == final2['reopened']['manifest']
    assert json.loads((fixture/'manifest.json').read_text()) == final2['reopened']['manifest']
    started = load('final2/reopen-job'); completed = load('final2/reopen-completed')
    assert started['jobID'] == completed['job']['id'] and completed['revision'] == 36
    assert completed['job']['kind'] == 'open' and completed['job']['state'] == 'completed'
    assert completed['job']['path'] == packages['final2']['fixture']
    final2_checks = {'search-roundtrip':['Description: 드럼 행 검색','Value: 66'],
                     'orbit-draft-roundtrip':['Description: MIDI 선택 길이 변경','Value: 1.']}
    for name, strings in final2_checks.items():
        text = (OUT/'final2'/(name+'.ax.txt')).read_text()
        for string in strings: assert string in text, (name,string)
    print(json.dumps({'status':'passed','baselineSnapshots':2,'firstCandidateSnapshots':9,
                      'finalCandidateSnapshots':len(final2),'firstCandidateAXChecked':3,
                      'finalCandidateAXChecked':len(final2_checks),'tripletMenuSelectionVerified':False,
                      'preservedAssets':2,'physicalAudioAttempts':0,'packageUUID':packages['final2']['uuid']}))



if __name__ == '__main__':
    main()
