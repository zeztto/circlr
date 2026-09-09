#!/usr/bin/env python3
"""Read-only build93 preparation checks; no app calls."""
import copy
import hashlib
import math
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'qa/generated/music-scope'


def main():
    load = lambda name: json.loads((OUT / 'baseline' / (name + '.json')).read_text())
    package = load('package'); origin = load('fixture-origin'); initial = load('fixture-initial')
    evidence = Path(origin['sourceEvidence'])
    assert hashlib.sha256(evidence.read_bytes()).hexdigest() == origin['sourceEvidenceSHA256']
    original = json.loads(evidence.read_text())['manifest']
    assert original['id'] == origin['sourceProjectID'] != initial['id'] == package['projectID']
    original['id'] = initial['id']
    assert original == initial and initial['musicRevision'] == origin['sourceRevision'] == 54
    fixture = Path(package['fixture']); source = fixture.with_name('studio.circlr')
    assert hashlib.sha256((source / 'manifest.json').read_bytes()).hexdigest() == package['sourceSHA256'] == '12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d'
    assert len(initial['assets']) == 2
    for asset in initial['assets']:
        path = Path(asset['path'])
        assert not path.is_absolute() and '..' not in path.parts
        for directory in [fixture, source]:
            assert hashlib.sha256((directory / path).read_bytes()).hexdigest() == asset['checksum']
    baseline(initial, package)
    candidate(initial, package)



def music(value):
    value = copy.deepcopy(value)
    value.pop('hierarchyView', None); value.pop('musicRevision', None)
    colors = value.get('circleColors')
    if colors is not None:
        assert len(colors) % 2 == 0
        value['circleColors'] = {json.dumps(colors[i], sort_keys=True): colors[i+1] for i in range(0, len(colors), 2)}
        assert len(value['circleColors']) * 2 == len(colors)
    return value


def baseline(initial, package):
    assert '원본에서 변경·삭제된 음악 서클 또는 연결의 변형이 있습니다' in (OUT / 'baseline/rename-rejected.ax.txt').read_text()
    for name in ['before', 'rename-rejected']:
        capture = json.loads((OUT / 'baseline' / (name + '.json')).read_text())
        state = capture['state']
        assert state['runtime']['bundleID'] == 'com.circlr.integrationqa' and state['runtime']['build'] == '92'
        assert state['projectID'] == capture['manifest']['id'] == package['projectID']
        assert state['path'] == package['fixture'] and not state['dirty']
        assert state['revision'] == capture['manifest']['musicRevision'] == 54
        assert state['output']['attempts'] == state['audition']['attempts'] == 0
        assert not state['playback']['playing'] and not any(state['recording'][k] for k in ['audio', 'midi', 'busy'])
        assert music(capture['manifest']) == music(initial), name
        assert capture['manifest']['hierarchyView']['workspace']['original'] == (name == 'rename-rejected')


def candidate(initial, package):
    directory = OUT / 'final'
    revisions = {'before': 54, 'original-renamed': 55, 'rename-undone': 56,
                 'use-only-blocked': 56, 'use-recovered': 56, 'numeric-scope-switched': 57,
                 'numeric-undone': 58, 'group-before': 58, 'group-router-added': 59, 'group-undone': 60,
                 'stale-switched': 60, 'name-scope-switched': 61, 'original-name-noop': 61,
                 'name-scope-undone': 62, 'saved': 62, 'reopened': 62}
    captures = {n: json.loads((directory / (n + '.json')).read_text()) for n in revisions}
    candidate_package = json.loads((directory / 'package.json').read_text())
    assert '6DAA541E-9E77-3F78-B1D3-54F72BFADFF2' in candidate_package['uuid']
    original = music(initial)
    for name, capture in captures.items():
        state = capture['state']
        assert state['runtime']['bundleID'] == 'com.circlr.integrationqa' and state['runtime']['build'] == '93'
        assert state['projectID'] == capture['manifest']['id'] == package['projectID'] == candidate_package['projectID']
        assert state['path'] == package['fixture'] and not state['dirty']
        assert state['revision'] == capture['manifest']['musicRevision'] == revisions[name]
        assert state['output']['attempts'] == state['audition']['attempts'] == 0
        assert not state['playback']['playing'] and not any(state['recording'][k] for k in ['audio', 'midi', 'busy'])
        expected = copy.deepcopy(original)
        if name == 'original-renamed':
            node = next(n for n in expected['sections'][0]['graph']['nodes'] if n['id'] == 'DDB48BA6-04EC-5F78-8AB1-7CC61F46EAC7')
            node['name'] = '공유 원본 이름 검증'
        elif name == 'numeric-scope-switched':
            node = next(n for n in expected['arrangements'][0]['uses'][0]['graphEdits']['addedNodes'] if n['id'] == '68739BD0-1D0A-479E-AE10-F08DF24C2FA2')
            assert node['content']['effect']['_0']['amount'] == 0.5
            node['content']['effect']['_0']['amount'] = math.pow(10, -9 / 20)
        elif name in ['name-scope-switched', 'original-name-noop']:
            expected['arrangements'][0]['uses'][0]['graphEdits']['nodeOverrides']['FC5544DC-54E1-5CBB-80C3-514C5087D9C1']['name'] = '이번 사용 라우터 이름'
        elif name == 'group-router-added':
            edits = expected['arrangements'][0]['uses'][0]['graphEdits']
            node_id = 'FFE0C2BF-9732-48AF-9792-B2D0F0050D91'
            router = copy.deepcopy(next(n for n in expected['sections'][0]['graph']['nodes'] if 'router' in n['content']))
            router['id'] = node_id; router['name'] = '오디오 라우터'
            edits['addedNodes'].append(router)
            edits['layout']['positions'][node_id] = {'x': -216, 'y': -72}
        assert music(capture['manifest']) == expected, name


    assert captures['saved']['manifest'] == captures['reopened']['manifest']
    assert json.loads((Path(package['fixture']) / 'manifest.json').read_text()) == captures['reopened']['manifest']
    job = json.loads((directory / 'reopen-job.json').read_text())
    assert job['revision'] == 62 and job['job']['kind'] == 'open'
    assert job['job']['state'] == 'completed' and job['job']['path'] == package['fixture']
    for name in ['use-only-blocked', 'numeric-scope-switched', 'name-scope-switched', 'original-name-noop', 'reopened']:
        assert captures[name]['manifest']['hierarchyView']['workspace']['original']
    assert not captures['use-recovered']['manifest']['hierarchyView']['workspace']['original']
    assert not captures['stale-switched']['manifest']['hierarchyView']['workspace']['original']
    checks = {
        'original-renamed': ['공유 원본 이름 검증'],
        'use-only-blocked': ['text field (disabled) Description: 서클 이름', '공유 원본에 없는 서클입니다', '이번 사용 편집'],
        'use-recovered': ['Description: 서클 이름', '첫 번째 게인'],
        'scope-numeric-draft': ['Value: -9'],
        'stale-draft': ['Value: -3'],
        'name-scope-draft': ['이번 사용 라우터 이름'],
        'name-scope-switched': ['Value: 독립 스테레오 출력', '서클 · 공유 원본'],
        'reopened': ['독립 스테레오 출력', '서클 · 공유 원본'],
    }
    for name, strings in checks.items():
        text = (directory / (name + '.ax.txt')).read_text()
        for string in strings: assert string in text, (name, string)
    print(json.dumps({'status': 'passed', 'baselineRegression': 'reproduced', 'baselineSnapshots': 2,
                      'candidateSnapshots': len(captures), 'baselineAXChecked': 1, 'candidateAXChecked': len(checks),
                      'preservedAssets': 2, 'physicalAudioAttempts': 0, 'packageUUID': candidate_package['uuid']}, ensure_ascii=False))


if __name__ == "__main__":
    main()
