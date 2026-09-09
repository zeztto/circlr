#!/usr/bin/env python3
"""Read-only build92 fixture preparation checks; no app calls."""
import copy
import hashlib
import math
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'qa/generated/router-level'


def main():
    load = lambda name: json.loads((OUT / 'baseline' / (name + '.json')).read_text())
    package = load('package'); origin = load('fixture-origin'); initial = load('fixture-initial')
    evidence = Path(origin['sourceEvidence'])
    assert hashlib.sha256(evidence.read_bytes()).hexdigest() == origin['sourceEvidenceSHA256']
    original = json.loads(evidence.read_text())['manifest']
    assert original['id'] == origin['sourceProjectID'] != initial['id'] == package['projectID']
    original['id'] = initial['id']
    use = original['arrangements'][0]['uses'][0]
    section = next(s for s in original['sections'] if s['id'] == use['sectionID'])
    router_id = 'FC5544DC-54E1-5CBB-80C3-514C5087D9C1'
    assert router_id not in use['graphEdits']['nodeOverrides']
    router = copy.deepcopy(next(n for n in section['graph']['nodes'] if n['id'] == router_id))
    route = next(r for r in router['content']['router']['_0']['routes']
                 if r['input'] == 'in.audio.bus1' and r['output'] == 'out.audio.bus1')
    assert route['gain'] == 1
    route['gain'] = math.pow(10, -6 / 20)
    use['graphEdits']['nodeOverrides'][router_id] = router
    assert original == initial and initial['musicRevision'] == origin['sourceRevision'] == 28
    fixture = Path(package['fixture']); source = fixture.with_name('studio.circlr')
    assert hashlib.sha256((source / 'manifest.json').read_bytes()).hexdigest() == package['sourceSHA256'] == '12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d'
    assert len(initial['assets']) == 2
    for asset in initial['assets']:
        path = Path(asset['path'])
        assert not path.is_absolute() and '..' not in path.parts
        for directory in [fixture, source]:
            assert hashlib.sha256((directory / path).read_bytes()).hexdigest() == asset['checksum']
    baseline(initial, package)
    candidate_partial(initial, package)


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
    original = music(initial)
    for name, revision in [('before', 28), ('untouched-return', 29), ('restored', 30)]:
        capture = json.loads((OUT / 'baseline' / (name + '.json')).read_text())
        state = capture['state']
        assert state['runtime']['bundleID'] == 'com.circlr.integrationqa' and state['runtime']['build'] == '91'
        assert state['projectID'] == capture['manifest']['id'] == package['projectID']
        assert state['path'] == package['fixture'] and not state['dirty']
        assert state['revision'] == capture['manifest']['musicRevision'] == revision
        assert state['output']['attempts'] == state['audition']['attempts'] == 0
        assert not state['playback']['playing'] and not any(state['recording'][k] for k in ['audio', 'midi', 'busy'])
        expected = copy.deepcopy(original)
        if name == 'untouched-return':
            routes = expected['arrangements'][0]['uses'][0]['graphEdits']['nodeOverrides']['FC5544DC-54E1-5CBB-80C3-514C5087D9C1']['content']['router']['_0']['routes']
            assert routes[0]['gain'] == math.pow(10, -6 / 20)
            routes[0]['gain'] = 0.5
            routes.reverse()
        assert music(capture['manifest']) == expected, name


def candidate_partial(initial, package):
    directory = OUT / 'final'
    candidate = json.loads((directory / 'package.json').read_text())
    assert 'F09EA2C6-0219-3705-A78B-7094AD718D6C' in candidate['uuid']
    revisions = {'before': 30, 'untouched-return': 30, 'untouched-return-confirmed': 30,
                 'four-routes': 34, 'four-undone': 38, 'route-removed': 39, 'route-added': 40,
                 'removal-undone': 42, 'slider-click': 43, 'slider-right': 44, 'slider-undone': 46,
                 'original-view': 46, 'original-edit': 47, 'original-undone': 48,
                 'invalid': 48, 'cancelled': 48, 'stale-switched': 48, 'stale-returned': 48,
                 'named-preset': 50, 'preset-undone': 52, 'numeric-preset': 53,
                 'numeric-preset-late-return': 53, 'numeric-preset-undone': 54, 'saved': 54, 'reopened': 54}
    original = music(initial)
    router_id = 'FC5544DC-54E1-5CBB-80C3-514C5087D9C1'
    def routes(model):
        return model['arrangements'][0]['uses'][0]['graphEdits']['nodeOverrides'][router_id]['content']['router']['_0']['routes']
    gain = lambda db: math.pow(10, db / 20)
    captures = {n: json.loads((directory / (n + '.json')).read_text()) for n in revisions}
    for name, capture in captures.items():
        state = capture['state']
        assert state['runtime']['bundleID'] == 'com.circlr.integrationqa' and state['runtime']['build'] == '92'
        assert state['projectID'] == capture['manifest']['id'] == package['projectID'] == candidate['projectID']
        assert state['path'] == package['fixture'] and not state['dirty']
        assert state['revision'] == capture['manifest']['musicRevision'] == revisions[name]
        assert state['output']['attempts'] == state['audition']['attempts'] == 0
        assert not state['playback']['playing'] and not any(state['recording'][k] for k in ['audio', 'midi', 'busy'])
        expected = copy.deepcopy(original); row = routes(expected)
        if name == 'four-routes':
            row[0]['gain'] = gain(-3); row[1]['gain'] = gain(-6)
            row.extend([{'input': 'in.audio.bus1', 'output': 'out.audio.bus2', 'gain': gain(-12)},
                        {'input': 'in.audio.bus2', 'output': 'out.audio.bus1', 'gain': gain(-18)}])
        elif name in ['route-removed', 'route-added']:
            row.pop(0)
            if name == 'route-added': row.append({'input': 'in.audio.bus1', 'output': 'out.audio.bus1', 'gain': 1})
        elif name in ['slider-click', 'slider-right']:
            click_gain = routes(captures['slider-click']['manifest'])[0]['gain']
            assert math.isclose(20 * math.log10(click_gain), -30, abs_tol=0.01)
            actual_gain = routes(capture['manifest'])[0]['gain']
            if name == 'slider-right':
                assert math.isclose(20 * math.log10(actual_gain / click_gain), 0.5, abs_tol=1e-12)
            row[0]['gain'] = actual_gain
        elif name in ['numeric-preset', 'numeric-preset-late-return']:
            expected['arrangements'][0]['uses'][0]['graphEdits']['nodeOverrides'].pop(router_id)
        elif name == 'named-preset':
            node = expected['arrangements'][0]['uses'][0]['graphEdits']['nodeOverrides'][router_id]
            node['name'] = '라우터 프리셋 검증'
            row[:] = [{'input': 'in.audio.bus1', 'output': 'out.audio.bus2', 'gain': 1},
                      {'input': 'in.audio.bus2', 'output': 'out.audio.bus1', 'gain': 1}]
        elif name == 'original-edit':
            use = expected['arrangements'][0]['uses'][0]
            section = next(s for s in expected['sections'] if s['id'] == use['sectionID'])
            node = next(n for n in section['graph']['nodes'] if n['id'] == router_id)
            node['content']['router']['_0']['routes'][1]['gain'] = gain(-3)
        assert music(capture['manifest']) == expected, name
        assert capture['manifest']['hierarchyView']['workspace']['original'] == name.startswith('original-')

    assert captures['saved']['manifest'] == captures['reopened']['manifest']
    assert json.loads((Path(package['fixture']) / 'manifest.json').read_text()) == captures['reopened']['manifest']
    job = json.loads((directory / 'reopen-job.json').read_text())
    assert job['revision'] == 54 and job['job']['kind'] == 'open'
    assert job['job']['state'] == 'completed' and job['job']['path'] == package['fixture']
    checks = {
        'numeric-entry-recheck': ['Description: IN 1 OUT 1 전송량 dB', 'Value: -6.00'],
        'four-routes': ['Value: -3.00', 'Value: -12.00', 'Value: -18.00', 'Value: -6.00'],
        'tab-second': ['Selected text:', 'Description: IN 1 OUT 2 전송량 dB'],
        'tab-third': ['Selected text:', 'Description: IN 2 OUT 1 전송량 dB'],
        'tab-fourth': ['Selected text:', 'Description: IN 2 OUT 2 전송량 dB'],
        'invalid': ['입력 범위: −∞–12.04 dB', 'Value: 20'],
        'stale-draft': ['Value: -9'],
        'preset-name-draft': ['라우터 프리셋 검증'],
        'named-preset': ['라우터 프리셋 검증'],
        'preset-number-draft': ['Value: -9'],
        'numeric-preset-late-return': ['편집 대상이 변경되었습니다. Esc로 취소한 뒤 다시 입력하세요', 'Value: -9'],
        'reopened': ['Value: -6.00', 'scroll bar (settable, float) 1'],
    }
    for name, strings in checks.items():
        text = (directory / (name + '.ax.txt')).read_text()
        for string in strings: assert string in text, (name, string)
    print(json.dumps({'status': 'passed', 'baselineRegression': 'reproduced', 'baselineSnapshots': 3,
                      'candidateSnapshots': len(captures), 'candidateAXChecked': len(checks),
                      'preservedAssets': 2, 'physicalAudioAttempts': 0, 'packageUUID': candidate['uuid']}, ensure_ascii=False))


if __name__ == '__main__':
    main()
