#!/usr/bin/env python3
"""Read-only build90 native evidence checks; no application or audio calls."""
import copy
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'qa/generated/port-navigation'


def load(name):
    return json.loads((OUT / (name + '.json')).read_text())


def music(value):
    value = copy.deepcopy(value)
    value.pop('hierarchyView', None)
    value.pop('musicRevision', None)
    colors = value.get('circleColors')
    if colors is not None:
        assert len(colors) % 2 == 0
        value['circleColors'] = {json.dumps(colors[i], sort_keys=True): colors[i + 1]
                                 for i in range(0, len(colors), 2)}
        assert len(value['circleColors']) * 2 == len(colors)
    return value


def main():
    names = ['baseline/' + n for n in ['before', 'track2-effects', 'track2-effect-source']]
    names += ['final/' + n for n in ['before', 'track2-effects', 'effect-track-inference',
                                    'crossed', 'undone', 'saved', 'reopened']]
    captures = {n: load(n) for n in names}
    package = load('final/package')
    before = captures['final/before']['manifest']
    expected = music(before)
    for name, capture in captures.items():
        state = capture['state']
        assert state['projectID'] == package['projectID'] == capture['manifest']['id'], name
        assert state['runtime']['build'] == ('89' if name.startswith('baseline/') else '90'), name
        assert state['runtime']['bundleID'] == 'com.circlr.integrationqa'
        revision = 17 if name == 'final/crossed' else (18 if name in ['final/undone', 'final/saved', 'final/reopened'] else 16)
        assert state['revision'] == capture['manifest']['musicRevision'] == revision and not state['dirty'], name
        assert state['output']['attempts'] == state['audition']['attempts'] == 0
        assert not state['playback']['playing'] and not any(state['recording'][k] for k in ['audio', 'midi', 'busy'])
        if name != 'final/crossed':
            assert music(capture['manifest']) == expected, name
    # Exactly one use-local router override; source section, other use, assets and all other music stay exact.
    use = before['arrangements'][0]['uses'][0]
    section = next(s for s in before['sections'] if s['id'] == use['sectionID'])
    router_id = 'FC5544DC-54E1-5CBB-80C3-514C5087D9C1'
    router = copy.deepcopy(next(n for n in section['graph']['nodes'] if n['id'] == router_id))
    routes = router['content']['router']['_0']['routes']
    assert routes == [{'gain': 1, 'input': 'in.audio.bus1', 'output': 'out.audio.bus1'},
                      {'gain': 1, 'input': 'in.audio.bus2', 'output': 'out.audio.bus2'}]
    routes[0]['output'] = 'out.audio.bus2'; routes[1]['output'] = 'out.audio.bus1'
    crossed = copy.deepcopy(expected)
    assert crossed['arrangements'][0]['uses'][0]['graphEdits']['nodeOverrides'] == {}
    crossed['arrangements'][0]['uses'][0]['graphEdits']['nodeOverrides'][router_id] = router
    assert music(captures['final/crossed']['manifest']) == crossed
    assert captures['final/saved']['manifest'] == captures['final/reopened']['manifest']
    origin = load('baseline/fixture-origin')
    source_evidence = Path(origin['sourceEvidence'])
    assert hashlib.sha256(source_evidence.read_bytes()).hexdigest() == origin['sourceEvidenceSHA256']
    prepared = json.loads(source_evidence.read_text())['manifest']
    assert prepared['id'] == origin['sourceProjectID'] != package['projectID'] == origin['newProjectID']
    assert prepared['musicRevision'] == origin['sourceRevision'] == 16
    prepared['id'] = package['projectID']
    assert music(prepared) == expected
    nodes = {'baseline/track2-effects': '8E30C634-08A5-5F38-9135-26EF84C21DB5',
             'baseline/track2-effect-source': '8E30C634-08A5-5F38-9135-26EF84C21DB5',
             'final/track2-effects': '8E30C634-08A5-5F38-9135-26EF84C21DB5',
             'final/effect-track-inference': '68739BD0-1D0A-479E-AE10-F08DF24C2FA2',
             'final/crossed': router_id,
             'final/undone': 'DDB48BA6-04EC-5F78-8AB1-7CC61F46EAC7'}
    for name, node in nodes.items():
        assert captures[name]['state']['selection'] == {'music': {
            'arrangementID': before['arrangements'][0]['id'], 'useID': use['id'], 'nodeID': node}}, name
    ax_checks = {
        'baseline/track2-effects': ['2 · 출력 2', '2개 결과', '첫 번째 게인', '두 번째 게인'],
        'baseline/track2-effect-source': ['(selected) Description: 출력 2 · 오디오', 'Help: 검증 톤 2'],
        'final/track2-effects': ['2 · 출력 2', '0개 결과'],
        'final/track1-effects': ['1 · 출력 1', '2개 결과', '첫 번째 게인', '두 번째 게인'],
        'final/effect-track-inference': ['1 · 출력 1', '3개 결과', '검증 톤 1 · 복제', '미연결', '출력 1 MIDI'],
        'final/crossed-track2-effects': ['2 · 출력 2', '2개 결과', '첫 번째 게인', '두 번째 게인'],
        'final/crossed-track1-effects': ['1 · 출력 1', '0개 결과'],
    }
    for name, strings in ax_checks.items():
        text = (OUT / (name + '.ax.txt')).read_text()
        for string in strings:
            assert string in text, (name, string)
    fixture = Path(package['fixture']); source = fixture.with_name('studio.circlr')
    assert music(json.loads((fixture / 'manifest.json').read_text())) == expected
    assert hashlib.sha256((source / 'manifest.json').read_bytes()).hexdigest() == package['sourceSHA256'] == '12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d'
    assert len(expected['assets']) == 2
    for asset in expected['assets']:
        for folder in [fixture, source]:
            assert hashlib.sha256((folder / asset['path']).read_bytes()).hexdigest() == asset['checksum']
    print(json.dumps({'status': 'passed', 'nativeSnapshots': len(names), 'axCaptures': len(ax_checks),
                      'preservedAssets': 2, 'physicalAudioAttempts': 0,
                      'packageUUID': package['uuid']}, ensure_ascii=False))


if __name__ == '__main__':
    main()
