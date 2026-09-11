#!/usr/bin/env python3
"""Check captured build84 route summaries and edit preservation; never runs audio."""
import copy
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'qa/generated/arrangement-route'


def load(name):
    return json.loads((OUT / (name + '.json')).read_text())


def normalized(value, history=False):
    value = copy.deepcopy(value)
    if 'circleColors' in value:
        colors = value['circleColors']; assert len(colors) % 2 == 0
        pairs = {json.dumps(colors[i], sort_keys=True): colors[i+1] for i in range(0, len(colors), 2)}
        assert len(pairs) * 2 == len(colors)
        value['circleColors'] = pairs
    if history:
        value.pop('musicRevision', None)
        value.pop('hierarchyView', None)  # Navigation restoration is separate from music history.
    return value


def walk(arrangement):
    if not arrangement['uses']:
        return []
    uses = {u['id']: u for u in arrangement['uses']}
    route = []; current = arrangement['startID']
    while current:
        assert current not in [u['id'] for u in route], 'unexpected cycle in evidence'
        use = uses[current]; route.append(use)
        if use['isEnd']:
            break
        edges = [e for e in arrangement['edges'] if e['from'] == current]
        assert len(edges) == 1, 'not a resolved linear evidence route'
        current = edges[0]['to']
    return route


def main():
    names = ['before', 'selected', 'renamed', 'reorder-rejected', 'reordered',
             'source-selected', 'alternative-selected', *['undo-' + str(i) for i in range(1, 6)],
             'restored', 'reopened', 'cancelled']
    captures = {n: load(n) for n in names}; package = load('package')
    manifest = lambda n: captures[n]['manifest']
    for name, capture in captures.items():
        s = capture['state']; m = capture['manifest']
        assert s['projectID'] == package['projectID'] == m['id'], name
        assert s['runtime']['build'] == '84' and s['runtime']['bundleID'] == 'com.circlr.integrationqa'
        assert s['revision'] == m['musicRevision'] and not s['dirty']
        assert s['output']['attempts'] == s['audition']['attempts'] == 0
        assert not s['playback']['playing']
        assert not any(s['recording'][k] for k in ['midi', 'audio', 'busy'])
    before = normalized(manifest('before'), True)
    assert before == normalized(load('fixture-initial'), True)
    alternatives = before['arrangements']; assert len(alternatives) == 4
    assert alternatives[0]['name'] == alternatives[1]['name'] == '도시의 밤'
    for index, expected in [(0, [('도입', 1), ('주제', 1), ('마무리', 1)]),
                            (1, [('마무리', 1), ('도입', 2), ('주제', 3)])]:
        route = walk(alternatives[index])
        assert [(u['name'], u['repeatCount']) for u in route] == expected
        assert len(alternatives[index]['uses']) - len(route) == 1
    unresolved = alternatives[2]
    assert not unresolved['chosenEdges']
    assert len([e for e in unresolved['edges'] if e['from'] == unresolved['startID']]) == 2
    assert not next(u for u in unresolved['uses'] if u['id'] == unresolved['startID'])['isEnd']
    assert alternatives[3]['uses'] == []

    def selected(source, target, index):
        expected = normalized(manifest(source), True)
        chosen = expected['arrangements'][index]['id']
        expected['activeArrangementID'] = chosen
        expected['album']['compositions'][0]['selectedArrangementID'] = chosen
        assert expected == normalized(manifest(target), True), (source, target)
    selected('before', 'selected', 1)
    selected('reordered', 'source-selected', 0)
    selected('source-selected', 'alternative-selected', 1)
    expected = normalized(manifest('selected'))
    expected['arrangements'][1]['name'] = manifest('renamed')['arrangements'][1]['name']
    assert len(expected['arrangements'][1]['name']) > 80
    assert expected == normalized(manifest('renamed'))
    assert normalized(manifest('renamed')) == normalized(manifest('reorder-rejected'))

    old = normalized(manifest('renamed'), True); new = normalized(manifest('reordered'), True)
    changed = new['arrangements'][1]
    route = walk(changed)
    assert [(u['name'], u['repeatCount']) for u in route] == [('주제', 3), ('마무리', 1), ('도입', 4), ('경로 밖 보관', 1)]
    expected_arrangement = copy.deepcopy(old['arrangements'][1])
    expected_arrangement['startID'] = changed['startID']
    expected_arrangement['edges'] = copy.deepcopy(changed['edges'])
    for use in expected_arrangement['uses']:
        if use['name'] == '도입': use['repeatCount'] = 4
        if use['name'] == '주제': use['isEnd'] = False
    assert expected_arrangement == changed
    old['arrangements'][1] = expected_arrangement
    assert old == new  # All other arrangements, sections, notes, assets and fields are unchanged.
    for undo, original in [('undo-1', 'source-selected'), ('undo-2', 'reordered'),
                            ('undo-3', 'renamed'), ('undo-4', 'selected'), ('undo-5', 'before'),
                            ('restored', 'before')]:
        assert normalized(manifest(undo), True) == normalized(manifest(original), True), undo
    assert normalized(manifest('restored')) == normalized(manifest('reopened'))
    assert normalized(manifest('reopened')) == normalized(manifest('cancelled'))

    full = (OUT / 'list-full.ax.txt').read_text()
    for text in ['총 3회', '도입 → 주제 → 마무리', '총 6회', '마무리 → 도입 ×2 → 주제 ×3',
                 '경로 제외 1개', '도입: 다음 연결을 선택하거나 끝으로 지정하세요', '빈 편곡 · 섹션을 추가하세요']:
        assert text in full, text
    updated = (OUT / 'reordered.ax.txt').read_text()
    for text in ['총 9회', '경로 제외 0개', '주제 ×3 → 마무리 → 도입 ×4 → 경로 밖 보관']:
        assert text in updated, text
    assert manifest('renamed')['arrangements'][1]['name'] in (OUT / 'long-name.ax.txt').read_text()
    empty = (OUT / 'empty.ax.txt').read_text()
    assert 'Value: #4' in empty and '1개 결과' in empty and '#4 · 빈 편곡 · 0개 섹션' in empty
    form = (OUT / 'clone-form.ax.txt').read_text()
    assert '새 편곡안 이름' in form and '이름 입력 취소 · Esc' in form
    fixture = Path(package['fixture']); source = fixture.with_name('studio.circlr')
    digest = hashlib.sha256((source / 'manifest.json').read_bytes()).hexdigest()
    assert digest == package['sourceSHA256'] == '12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d'
    assert len(before['assets']) == 2
    for asset in before['assets']:
        for folder in [fixture, source]:
            assert hashlib.sha256((folder / asset['path']).read_bytes()).hexdigest() == asset['checksum']
    assert '5DD60BB7-2B17-3708-8485-D9E2B748FBA9' in package['uuid']
    print(json.dumps({'status': 'passed', 'nativeSnapshots': len(names), 'preservedAssets': 2,
                      'physicalAudioAttempts': 0, 'sourceSHA256': digest, 'packageUUID': package['uuid']}, ensure_ascii=False))


if __name__ == '__main__':
    main()
