#!/usr/bin/env python3
"""Read-only build95 preparation checks; no app calls."""
import copy
import hashlib
import math
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'qa/generated/route-density'


def main():
    load = lambda name: json.loads((OUT / 'baseline' / (name + '.json')).read_text())
    package = load('package'); origin = load('fixture-origin'); initial = load('fixture-initial')
    evidence = Path(origin['sourceEvidence'])
    assert hashlib.sha256(evidence.read_bytes()).hexdigest() == origin['sourceEvidenceSHA256']
    original = json.loads(evidence.read_text())['manifest']
    assert original['id'] == origin['sourceProjectID'] != initial['id'] == package['projectID']
    original['id'] = initial['id']
    assert original == initial and initial['musicRevision'] == origin['sourceRevision'] == 62
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
        value['circleColors'] = {json.dumps(colors[i], sort_keys=True): colors[i+1] for i in range(0, len(colors), 2)}
        assert len(value['circleColors']) * 2 == len(colors)
    return value


def native(initial, package):
    final = OUT / 'final'
    candidate = json.loads((final / 'package.json').read_text())
    assert '59D93FC8-5A1C-3898-9FB3-42B37997255F' in candidate['uuid']
    nodes = {'router': 'FC5544DC-54E1-5CBB-80C3-514C5087D9C1',
             'settings-returned': 'FC5544DC-54E1-5CBB-80C3-514C5087D9C1',
             'connections-returned': 'FC5544DC-54E1-5CBB-80C3-514C5087D9C1',
             'audio-selected': 'DDB48BA6-04EC-5F78-8AB1-7CC61F46EAC7',
             'effect-selected': '68739BD0-1D0A-479E-AE10-F08DF24C2FA2',
             'midi-selected': 'midi:36BF676A-F02A-42AA-9309-106A42AD8527',
             'router-returned': 'FC5544DC-54E1-5CBB-80C3-514C5087D9C1'}
    names = ['baseline/router'] + ['final/' + n for n in nodes]
    if not all((final / (n + '.json')).exists() for n in ['saved', 'reopened']):
        print(json.dumps({'status': 'native-pending', 'pending': 'saved/reopened'})); return
    names += ['final/saved', 'final/reopened']
    captures = {n: json.loads((OUT / (n + '.json')).read_text()) for n in names}
    for name, capture in captures.items():
        state = capture['state']
        assert state['runtime']['bundleID'] == 'com.circlr.integrationqa'
        assert state['runtime']['build'] == ('94' if name.startswith('baseline/') else '95')
        assert state['projectID'] == capture['manifest']['id'] == package['projectID'] == candidate['projectID']
        assert state['path'] == package['fixture'] and not state['dirty']
        assert state['revision'] == capture['manifest']['musicRevision'] == 62
        assert state['output']['attempts'] == state['audition']['attempts'] == 0
        assert not state['playback']['playing'] and not any(state['recording'][k] for k in ['audio', 'midi', 'busy'])
        assert music(capture['manifest']) == music(initial), name
        label = name.split('/')[1]
        if label in nodes:
            assert state['selection'] == {'music': {'arrangementID': initial['arrangements'][0]['id'],
                'useID': initial['arrangements'][0]['uses'][0]['id'], 'nodeID': nodes[label]}}, name
    assert captures['final/saved']['manifest'] == captures['final/reopened']['manifest']
    assert json.loads((Path(package['fixture']) / 'manifest.json').read_text()) == captures['final/reopened']['manifest']
    job = json.loads((final / 'reopen-job.json').read_text())
    assert job['revision'] == 62 and job['job']['kind'] == 'open'
    assert job['job']['state'] == 'completed' and job['job']['path'] == package['fixture']
    ax = lambda name: (OUT / (name + '.ax.txt')).read_text()
    assert 'Description: 출력 1 · 라우터,' in ax('baseline/router')
    for name in ['router', 'settings-returned', 'connections-returned', 'router-returned', 'reopened']:
        text = ax('final/' + name)
        assert 'Description: 출력 1 · 라우터,' not in text
        assert 'Description: 독립 스테레오 출력,' in text
    assert 'Description: 출력 1 · MIDI,' not in ax('final/midi-selected')
    assert 'Description: 출력 1 MIDI,' in ax('final/midi-selected')
    assert 'Description: 출력 1 · MIDI,' in ax('final/router-returned')
    for name, string in [('audio-search', '2개 결과'), ('effect-shortcut', '2개 결과'),
                         ('source-shortcut', '3개 결과'), ('audio-selected', '오디오 검색 · 2개'),
                         ('effect-selected', '이펙트 검색 · 2개')]:
        assert string in ax('final/' + name), name
    print(json.dumps({'status': 'passed', 'nativeSnapshots': len(captures), 'axChecked': 12,
                      'preservedAssets': 2, 'physicalAudioAttempts': 0, 'packageUUID': candidate['uuid']}, ensure_ascii=False))


if __name__ == "__main__":
    main()
