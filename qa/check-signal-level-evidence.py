#!/usr/bin/env python3
"""Read-only build91 native gain and project preservation checks; no app calls."""
import copy
import hashlib
import math
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'qa/generated/signal-level'


def main():
    load = lambda name: json.loads((OUT / 'baseline' / (name + '.json')).read_text())
    package = load('package'); origin = load('fixture-origin'); initial = load('fixture-initial')
    evidence = Path(origin['sourceEvidence'])
    assert hashlib.sha256(evidence.read_bytes()).hexdigest() == origin['sourceEvidenceSHA256']
    original = json.loads(evidence.read_text())['manifest']
    assert original['id'] == origin['sourceProjectID'] != initial['id'] == package['projectID']
    original['id'] = initial['id']
    assert original == initial and initial['musicRevision'] == origin['sourceRevision'] == 18
    fixture = Path(package['fixture']); source = fixture.with_name('studio.circlr')
    assert hashlib.sha256((source / 'manifest.json').read_bytes()).hexdigest() == package['sourceSHA256'] == '12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d'
    assert len(initial['assets']) == 2
    for asset in initial['assets']:
        path = Path(asset['path'])
        assert not path.is_absolute() and '..' not in path.parts
        for directory in [fixture, source]:
            assert hashlib.sha256((directory / path).read_bytes()).hexdigest() == asset['checksum']
    native(initial, package)


def music(value):
    value = copy.deepcopy(value)
    value.pop('hierarchyView', None); value.pop('musicRevision', None)
    colors = value.get('circleColors')
    if colors is not None:
        assert len(colors) % 2 == 0
        value['circleColors'] = {json.dumps(colors[i], sort_keys=True): colors[i+1]
                                 for i in range(0, len(colors), 2)}
        assert len(value['circleColors']) * 2 == len(colors)
    return value


def native(initial, baseline_package):
    revisions = {'effect': 18, 'effect-minus6': 19, 'effect-undone': 20, 'effect-silent': 21,
                 'effect-unity': 22, 'effect-noop': 22, 'effect-invalid': 22, 'effect-cancelled': 22,
                 'router': 22, 'router-minus6': 23, 'router-undone': 24,
                 'mix': 24, 'mix-minus6': 25, 'mix-undone': 26, 'saved': 26, 'reopened': 26}
    names = ['baseline/' + n for n in ['effect', 'mix', 'router']]
    names += ['final/' + n for n in revisions]
    missing = [name for name in names if not (OUT / (name + '.json')).is_file()]
    if missing:
        print(json.dumps({'status': 'native-pending', 'missing': missing, 'preservedAssets': 2}))
        return
    captures = {n: json.loads((OUT / (n + '.json')).read_text()) for n in names}
    package = json.loads((OUT / 'final/package.json').read_text())
    assert package['projectID'] == baseline_package['projectID']
    assert '15CEA7CC-4CF4-3A69-BA1F-48069D8EC81C' in package['uuid']
    original = music(initial)
    use = original['arrangements'][0]['uses'][0]
    node_ids = {'effect': '68739BD0-1D0A-479E-AE10-F08DF24C2FA2',
                'router': 'FC5544DC-54E1-5CBB-80C3-514C5087D9C1',
                'mix': 'mix:F721593D-465E-5D53-9C7D-435D0DEC7748'}
    for name, capture in captures.items():
        state = capture['state']; phase, label = name.split('/')
        assert state['runtime']['bundleID'] == 'com.circlr.integrationqa'
        assert state['runtime']['build'] == ('90' if phase == 'baseline' else '91')
        assert state['projectID'] == capture['manifest']['id'] == package['projectID']
        assert state['path'] == package['fixture'] and not state['dirty']
        assert state['revision'] == capture['manifest']['musicRevision'] == (18 if phase == 'baseline' else revisions[label])
        assert state['output']['attempts'] == state['audition']['attempts'] == 0
        assert not state['playback']['playing'] and not any(state['recording'][k] for k in ['audio', 'midi', 'busy'])
        expected = copy.deepcopy(original)
        if phase == 'final' and (label.endswith('-minus6') or label == 'effect-silent'):
            role = label.split('-')[0]; node_id = node_ids[role]
            edits = expected['arrangements'][0]['uses'][0]['graphEdits']
            if role == 'router':
                section = next(s for s in expected['sections'] if s['id'] == use['sectionID'])
                node = copy.deepcopy(next(n for n in section['graph']['nodes'] if n['id'] == node_id))
                assert node_id not in edits['nodeOverrides']
                edits['nodeOverrides'][node_id] = node
            else:
                node = next(n for n in edits['addedNodes'] if n['id'] == node_id)
            assert node['gain'] == 1
            node['gain'] = 0 if label == 'effect-silent' else math.pow(10, -6 / 20)
        assert music(capture['manifest']) == expected, name
        if label not in ['saved', 'reopened']:
            assert state['selection'] == {'music': {'arrangementID': original['arrangements'][0]['id'],
                'useID': use['id'], 'nodeID': node_ids[label.split('-')[0]]}}, name
    job = json.loads((OUT / 'final/reopen-job.json').read_text())
    assert job['revision'] == 26 and job['job']['kind'] == 'open'
    assert job['job']['state'] == 'completed' and job['job']['path'] == package['fixture']
    # No hierarchy/revision/color normalization exceptions in save/reopen comparison.
    assert captures['final/saved']['manifest'] == captures['final/reopened']['manifest']
    assert music(json.loads((Path(package['fixture']) / 'manifest.json').read_text())) == original
    ax_checks = {}
    for role in node_ids:
        ax_checks['baseline/' + role] = ['Description: 출력 볼륨,', 'Value: 1']
    display = {'effect': '0.00', 'effect-minus6': '-6.00', 'effect-silent': '−∞',
               'effect-unity': '0.00', 'effect-invalid': '20', 'effect-cancelled': '0.00',
               'router': '0.00', 'router-minus6': '-6.00', 'mix': '0.00',
               'mix-minus6': '-6.00', 'mix-undone': '0.00', 'router-returned': '0.00', 'reopened': '0.00'}
    for label, value in display.items():
        ax_checks['final/' + label] = ['Description: 출력 볼륨 dB, Help: 0 dB 원래 레벨 · −∞ 무음, Value: ' + value]
    ax_checks['final/effect-invalid'].append('입력 범위: −∞–12.04 dB')
    for name, strings in ax_checks.items():
        text = (OUT / (name + '.ax.txt')).read_text()
        for string in strings:
            assert string in text, (name, string)
    scroll_result = scroll_native(original, package)
    print(json.dumps({'status': 'passed', 'firstCandidateSnapshots': len(captures),
                      'firstCandidateAX': len(ax_checks), 'preservedAssets': 2,
                      'physicalAudioAttempts': 0, 'firstCandidateUUID': package['uuid'],
                      'scrollCandidate': scroll_result}, ensure_ascii=False))


def scroll_native(original, first_package):
    directory = OUT / 'final-scroll'
    package = json.loads((directory / 'package.json').read_text())
    assert package['projectID'] == first_package['projectID']
    assert package['fixture'] == first_package['fixture'] and package['build'] == '91'
    assert '05742A9A-97FE-31C5-B729-A1109FE9A083' in package['uuid']
    revisions = {'before': 26, 'bottom': 26, 'returned': 26, 'minus6': 27,
                 'undone': 28, 'saved': 28, 'reopened': 28}
    captures = {n: json.loads((directory / (n + '.json')).read_text()) for n in revisions}
    router_id = 'FC5544DC-54E1-5CBB-80C3-514C5087D9C1'
    use = original['arrangements'][0]['uses'][0]
    selection = {'music': {'arrangementID': original['arrangements'][0]['id'],
                           'useID': use['id'], 'nodeID': router_id}}
    for name, capture in captures.items():
        state = capture['state']; manifest = capture['manifest']
        assert state['runtime']['bundleID'] == 'com.circlr.integrationqa'
        assert state['runtime']['build'] == '91'
        assert state['projectID'] == manifest['id'] == package['projectID']
        assert state['path'] == package['fixture'] and not state['dirty']
        assert state['revision'] == manifest['musicRevision'] == revisions[name]
        assert state['selection'] == selection
        assert state['output']['attempts'] == state['audition']['attempts'] == 0
        assert not state['playback']['playing'] and not any(state['recording'][k] for k in ['audio', 'midi', 'busy'])
        expected = copy.deepcopy(original)
        if name == 'minus6':
            section = next(s for s in expected['sections'] if s['id'] == use['sectionID'])
            node = copy.deepcopy(next(n for n in section['graph']['nodes'] if n['id'] == router_id))
            assert node['gain'] == 1
            node['gain'] = math.pow(10, -6 / 20)
            expected['arrangements'][0]['uses'][0]['graphEdits']['nodeOverrides'][router_id] = node
        assert music(manifest) == expected, name
        if name != 'before':
            assert manifest['hierarchyView']['workspace']['editor']['scrolls']['router'] == {'x': 0, 'y': 169}, name
    assert captures['saved']['manifest'] == captures['reopened']['manifest']
    job = json.loads((directory / 'reopen-job.json').read_text())
    assert job['revision'] == 28 and job['job']['kind'] == 'open'
    assert job['job']['state'] == 'completed' and job['job']['path'] == package['fixture']
    ax_names = ['bottom', 'returned', 'undone', 'reopened']
    for name in ax_names:
        lines = (directory / (name + '.ax.txt')).read_text().splitlines()
        # The first (nested router editor) scrollbar, not the outer console scrollbar.
        bars = [line for line in lines if 'scroll bar (settable, float)' in line]
        assert bars and bars[0].rstrip().endswith('scroll bar (settable, float) 1'), name
        assert any('Description: 출력 볼륨 dB,' in line and 'Value: 0.00' in line for line in lines), name
    assert json.loads((Path(package['fixture']) / 'manifest.json').read_text()) == captures['reopened']['manifest']
    return {'status': 'passed', 'nativeSnapshots': len(captures), 'axCaptures': len(ax_names),
            'packageUUID': package['uuid'], 'routerScroll': {'x': 0, 'y': 169}}



if __name__ == '__main__':
    main()
