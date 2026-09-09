#!/usr/bin/env python3
"""Check explicit candidate clone evidence without controlling the app."""
import copy
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'qa/generated/arrangement-candidate'


def load(name):
    return json.loads((OUT / (name + '.json')).read_text())


def music(value):
    value = copy.deepcopy(value)
    value.pop('hierarchyView', None); value.pop('musicRevision', None)
    colors = value.get('circleColors')
    if colors is not None:
        assert len(colors) % 2 == 0
        value['circleColors'] = {json.dumps(colors[i], sort_keys=True): colors[i+1] for i in range(0, len(colors), 2)}
        assert len(value['circleColors']) * 2 == len(colors)
    return value


def main():
    scenario = load('scenario'); package = load('package')
    revisions = {'before':14, 'cancelled':14, 'row-cloned':15, 'row-undo':16,
                 'keyboard-cloned':17, 'keyboard-undo':18, 'search-rename-cancelled':18, 'external-before':18,
                 'external-edited':19, 'stale-rejected':19, 'restored':20, 'reopened':20,
                 'final-cloned':21, 'final-reopened':21}
    captures = {n:load(n) for n in revisions}
    before = music(captures['before']['manifest'])
    assert len(before['arrangements']) == 3 and before['activeArrangementID'] == scenario['currentA']
    source = next(a for a in before['arrangements'] if a['id'] == scenario['candidateB'])
    assert source['uses'][0]['repeatCount'] == 3
    for name, capture in captures.items():
        state = capture['state']
        assert state['runtime']['bundleID'] == 'com.circlr.integrationqa' and state['runtime']['build'] == '99'
        assert state['projectID'] == capture['manifest']['id'] == package['projectID'] == scenario['projectID']
        assert state['path'] == package['fixture'] and not state['dirty']
        assert state['revision'] == capture['manifest']['musicRevision'] == revisions[name]
        assert state['output']['attempts'] == state['audition']['attempts'] == 0
        assert not state['playback']['playing'] and not any(state['recording'][k] for k in ['audio','midi','busy'])
        expected = copy.deepcopy(before); actual = music(capture['manifest'])
        if name.endswith('-cloned') or name == 'final-reopened':
            clone = actual['arrangements'][-1]
            assert clone['id'] not in {a['id'] for a in before['arrangements']}
            assert clone['name'] == {'row-cloned':'후보 B 직접 복제','keyboard-cloned':'후보 B 키보드 복제','final-cloned':'후보 B 저장 검증','final-reopened':'후보 B 저장 검증'}[name]
            assert len(clone['uses']) == len(source['uses'])
            use_map = dict(zip((u['id'] for u in source['uses']), (u['id'] for u in clone['uses'])))
            assert len(set(use_map.values())) == len(use_map)
            assert not set(use_map.values()).intersection(u['id'] for a in before['arrangements'] for u in a['uses'])
            normalized = copy.deepcopy(source); normalized['id'] = clone['id']; normalized['name'] = clone['name']
            assert normalized['edges'] == [] and normalized['chosenEdges'] == {} and normalized['layout']['groups'] == []
            for use in normalized['uses']: use['id'] = use_map[use['id']]
            if normalized.get('startID'): normalized['startID'] = use_map[normalized['startID']]
            normalized['layout']['positions'] = {use_map.get(k,k):v for k,v in normalized['layout']['positions'].items()}
            assert clone == normalized
            expected['arrangements'].append(clone); expected['activeArrangementID'] = clone['id']
            owner = next(c for c in expected['album']['compositions'] if c['id'] == scenario['ownerID'])
            owner['arrangementIDs'].append(clone['id']); owner['selectedArrangementID'] = clone['id']
            for address, color in before['circleColors'].items():
                key = json.loads(address); key['section']['arrangementID'] = clone['id']
                key['section']['useID'] = use_map[key['section']['useID']]
                expected['circleColors'][json.dumps(key, sort_keys=True)] = color
        if name in ['external-edited', 'stale-rejected']:
            target = next(a for a in expected['arrangements'] if a['id'] == scenario['currentA'])
            assert target['uses'][0]['repeatCount'] == 1
            target['uses'][0]['repeatCount'] = 2
        assert actual == expected, name
    fixture = Path(package['fixture']); source_path = fixture.with_name('studio.circlr')
    assert hashlib.sha256((source_path / 'manifest.json').read_bytes()).hexdigest() == package['sourceSHA256'] == scenario['sourceSHA256']
    assert len(before['assets']) == 2
    for asset in before['assets']:
        path = Path(asset['path']); assert not path.is_absolute() and '..' not in path.parts
        for directory in [fixture, source_path]:
            assert hashlib.sha256((directory / path).read_bytes()).hexdigest() == asset['checksum']
    for left, right in [('external-edited','stale-rejected'), ('restored','reopened'), ('final-cloned','final-reopened')]:
        assert captures[left]['manifest'] == captures[right]['manifest'], (left, right)
    assert json.loads((fixture / 'manifest.json').read_text()) == captures['final-reopened']['manifest']
    checks = {'row-form': ['현재 · #1 · 현재 편곡 A', '복제 원본 · #2 · 세 번 반복하는 후보 B'],
              'keyboard-form': ['현재 · #1 · 현재 편곡 A', '복제 원본 · #2 · 세 번 반복하는 후보 B'],
              'empty-search': ['0개 결과', 'button (disabled) Description: 강조한 편곡 복제'],
              'current-rename': ['이름 변경 대상 · #1 · 현재 편곡 A', 'Description: 현재 편곡안 이름, Value: 현재 편곡 A'],
              'stale-rejected': ['button (disabled) 적용', '대상이나 음악이 바뀌었거나 다른 작업 중입니다. 닫은 뒤 다시 열어주세요.']}
    for name, strings in checks.items():
        text = (OUT / (name + '.ax.txt')).read_text()
        for string in strings: assert string in text, (name,string)
    print(json.dumps({'status':'passed','nativeSnapshots':len(captures),'axChecked':len(checks),'preservedAssets':2,'physicalAudioAttempts':0}))


if __name__ == '__main__':
    main()
