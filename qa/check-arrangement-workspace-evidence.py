#!/usr/bin/env python3
"""Read-only semantic checks for the captured build83 arrangement workspace."""
import copy
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'qa/generated/arrangement-workspace'


def load(name):
    return json.loads((OUT / (name + '.json')).read_text())


def normalized(value, history=False):
    value = copy.deepcopy(value)
    colors = value.get('circleColors')
    if colors is not None:
        assert len(colors) % 2 == 0
        pairs = {json.dumps(colors[i], sort_keys=True): colors[i + 1] for i in range(0, len(colors), 2)}
        assert len(pairs) * 2 == len(colors), 'duplicate circle color address'
        value['circleColors'] = pairs
    if history:
        # Undo/Redo advances revision and can restore a different navigation camera.
        value.pop('musicRevision', None)
        value.pop('hierarchyView', None)
    return value


def main():
    names = ['before', 'cancelled', 'cloned', 'renamed', 'same-name', 'rename-undo',
             'rename-redo', 'clone-undo', 'clone-redo', 'automated', 'external-renamed',
             'stale-rejected', 'external-undo', 'agent-cloned', 'source-selected',
             'selected-final', 'reopened', 'keyboard-before', 'keyboard-renamed',
             'keyboard-cloned', 'keyboard-restored', 'keyboard-reopened']
    names += ['same-owner-before', 'same-owner-cloned', 'same-owner-restored',
              'background-before', 'background-same', 'background-other',
              'background-select-other', 'background-select-same',
              'background-select-current-before', 'background-select-current',
              'background-restored', 'background-reopened']
    captures = {n: load(n) for n in names}
    manifest = lambda n: captures[n]['manifest']
    package = load('package')
    for name, capture in captures.items():
        state = capture['state']
        assert state['projectID'] == package['projectID'], name
        assert state['runtime']['build'] == '83', name
        assert state['runtime']['bundleID'] == 'com.circlr.integrationqa', name
        assert state['revision'] == capture['manifest']['musicRevision'], name
        assert state['output']['attempts'] == state['audition']['attempts'] == 0, name
        assert not any(state['recording'][k] for k in ['busy', 'midi', 'audio']), name
        assert not state['playback']['playing'] and not state['dirty'], name

    before = normalized(manifest('before'))
    cancelled = normalized(manifest('cancelled'))
    a = before['hierarchyView']['camera']; b = cancelled['hierarchyView']['camera']
    assert abs(a['zoom'] - b['zoom']) < 1e-10
    assert all(abs(a['pan'][k] - b['pan'][k]) < 1e-10 for k in ['x', 'y'])
    cancelled['hierarchyView']['camera'] = copy.deepcopy(a)
    assert before == cancelled
    assert normalized(load('fixture-initial'), True) == normalized(manifest('before'), True)

    cloned = normalized(manifest('cloned'))
    assert len(before['arrangements']) == 2 and len(cloned['arrangements']) == 3
    assert cloned['arrangements'][:2] == before['arrangements']
    assert cloned['album']['compositions'][1] == before['album']['compositions'][1]
    source = before['arrangements'][0]; clone = cloned['arrangements'][2]
    assert clone['id'] not in {a['id'] for a in before['arrangements']}
    assert len(clone['uses']) == len(source['uses'])
    use_map = dict(zip((u['id'] for u in source['uses']), (u['id'] for u in clone['uses'])))
    assert not set(use_map).intersection(use_map.values())
    for old, new in zip(source['uses'], clone['uses']):
        expected = copy.deepcopy(old); expected['id'] = new['id']
        assert new == expected
    expected_album = copy.deepcopy(before['album'])
    expected_album['compositions'][0]['arrangementIDs'].append(clone['id'])
    expected_album['compositions'][0]['selectedArrangementID'] = clone['id']
    assert cloned['album'] == expected_album and cloned['activeArrangementID'] == clone['id']
    for key, color in before['circleColors'].items():
        address = json.loads(key)
        copied = copy.deepcopy(address)
        copied['section']['arrangementID'] = clone['id']
        copied['section']['useID'] = use_map[address['section']['useID']]
        assert cloned['circleColors'][key] == color
        assert cloned['circleColors'][json.dumps(copied, sort_keys=True)] == color
    for key in before.keys() - {'arrangements', 'album', 'activeArrangementID', 'circleColors', 'musicRevision', 'hierarchyView'}:
        assert before[key] == cloned[key], key

    renamed = normalized(manifest('renamed'))
    expected = copy.deepcopy(cloned)
    expected['arrangements'][2]['name'] = renamed['arrangements'][2]['name']
    assert expected == renamed and renamed == normalized(manifest('same-name'))
    for left, right in [('cloned', 'rename-undo'), ('renamed', 'rename-redo'),
                        ('before', 'clone-undo'), ('renamed', 'clone-redo'),
                        ('automated', 'external-undo')]:
        assert normalized(manifest(left), True) == normalized(manifest(right), True), (left, right)
    assert normalized(manifest('external-renamed')) == normalized(manifest('stale-rejected'))

    isolation_before = load('isolation-before'); isolation_after = load('isolation-after')
    for key in ['use', 'graph', 'lanes']:
        assert isolation_before['source'][key] == isolation_after['source'][key], key
    old = isolation_before['clone']; new = isolation_after['clone']
    assert old['lanes'] == new['lanes']
    assert len(old['graph']['nodes']) == len(new['graph']['nodes'])
    changed = [(a, b) for a, b in zip(old['graph']['nodes'], new['graph']['nodes']) if a != b]
    assert len(changed) == 1
    old_node, new_node = changed[0]
    assert not old_node.get('automation')
    expected_node = copy.deepcopy(new_node); lane = expected_node.pop('automation')
    assert expected_node == old_node and len(lane) == 1
    assert lane[0]['parameter'] == 'gain' and lane[0]['enabled']
    assert [(p['beat'], p['value']) for p in lane[0]['points']] == [(0, .4), (64, .9)]
    restored = copy.deepcopy(new)
    for node in restored['graph']['nodes'] + restored['use']['graphEdits']['addedNodes']:
        if node['id'] == new_node['id']: node.pop('automation', None)
    restored['revision'] = old['revision']
    assert restored == old
    expected_automated = normalized(manifest('clone-redo'), True)
    automated = normalized(manifest('automated'), True)
    target_use = next(u for u in expected_automated['arrangements'][2]['uses'] if u['id'] == new['use']['id'])
    target_use['graphEdits'] = copy.deepcopy(new['use']['graphEdits'])
    assert expected_automated == automated

    agent_before = manifest('external-undo'); agent_after = manifest('agent-cloned')
    assert len(agent_after['arrangements']) == len(agent_before['arrangements']) + 1
    assert agent_after['arrangements'][:-1] == agent_before['arrangements']
    assert agent_after['album']['compositions'][0] == agent_before['album']['compositions'][0]
    other_before = agent_before['album']['compositions'][1]
    other_after = agent_after['album']['compositions'][1]
    new_id = agent_after['arrangements'][-1]['id']
    expected_other = copy.deepcopy(other_before)
    expected_other['arrangementIDs'].append(new_id)
    expected_other['selectedArrangementID'] = new_id
    assert other_after == expected_other
    assert agent_before['activeArrangementID'] == agent_after['activeArrangementID']
    assert captures['external-undo']['state']['selection'] == captures['agent-cloned']['state']['selection']
    expected_agent = normalized(agent_before, True)
    expected_agent['arrangements'].append(copy.deepcopy(agent_after['arrangements'][-1]))
    expected_agent['album']['compositions'][1] = expected_other
    assert expected_agent == normalized(agent_after, True)

    assert normalized(manifest('selected-final')) == normalized(manifest('reopened'))
    keyboard_before = normalized(manifest('keyboard-before'))
    keyboard_renamed = normalized(manifest('keyboard-renamed'))
    expected_keyboard = copy.deepcopy(keyboard_before)
    expected_keyboard['arrangements'][2]['name'] = 'Keyboard rename'
    assert expected_keyboard == keyboard_renamed
    keyboard_cloned = normalized(manifest('keyboard-cloned'))
    assert keyboard_cloned['arrangements'][:-1] == keyboard_renamed['arrangements']
    keyboard_copy = keyboard_cloned['arrangements'][-1]
    assert keyboard_copy['name'] == 'Keyboard alternative'
    assert keyboard_copy['id'] not in {a['id'] for a in keyboard_renamed['arrangements']}
    assert keyboard_cloned['activeArrangementID'] == keyboard_copy['id']
    assert keyboard_cloned['album']['compositions'][0]['selectedArrangementID'] == keyboard_copy['id']
    for old_use, new_use in zip(keyboard_renamed['arrangements'][2]['uses'], keyboard_copy['uses']):
        assert old_use['id'] != new_use['id']
        expected_use = copy.deepcopy(old_use); expected_use['id'] = new_use['id']
        assert expected_use == new_use
    keyboard_restored = normalized(manifest('keyboard-restored'))
    # This settled pair has identical navigation too; ignore only Undo's revision.
    keyboard_restored['musicRevision'] = keyboard_before['musicRevision']
    assert keyboard_restored == keyboard_before
    assert normalized(manifest('keyboard-restored')) == normalized(manifest('keyboard-reopened'))
    for name, label in [('keyboard-rename', '현재 편곡안 이름'), ('keyboard-clone', '새 편곡안 이름')]:
        text = (OUT / (name + '.ax.txt')).read_text()
        assert label in text and 'Return 이름 적용' in text
    keyboard_list = (OUT / 'keyboard-list.ax.txt').read_text()
    assert '이름 변경 · ⇧⌘N' in keyboard_list and '이름 정해 복제 · ⇧⌘D' in keyboard_list
    keyboard_package = load('keyboard/package')
    assert '32A66A38-2CEF-32D4-A168-FAB4BDD51754' in keyboard_package['uuid']

    # Historical failure: an implicit background clone changed playback choice and
    # collapsed music selection. The old before capture has no editorAddress proof.
    old_before = manifest('same-owner-before'); old_failed = manifest('same-owner-cloned')
    assert old_before['activeArrangementID'] != old_failed['activeArrangementID']
    assert 'music' in captures['same-owner-before']['state']['selection']
    assert 'composition' in captures['same-owner-cloned']['state']['selection']
    assert normalized(old_before, True) == normalized(manifest('same-owner-restored'), True)

    # Final background contract: clone adds an alternative without choosing it.
    for earlier, later, owner in [('background-before', 'background-same', 0),
                                  ('background-same', 'background-other', 1)]:
        old = normalized(manifest(earlier)); new = normalized(manifest(later))
        assert len(new['arrangements']) == len(old['arrangements']) + 1
        assert new['arrangements'][:-1] == old['arrangements']
        copied = new['arrangements'][-1]
        assert copied['id'] not in {a['id'] for a in old['arrangements']}
        expected = copy.deepcopy(old)
        expected['musicRevision'] = new['musicRevision']
        expected['arrangements'].append(copy.deepcopy(copied))
        expected['album']['compositions'][owner]['arrangementIDs'].append(copied['id'])
        # New per-use color addresses are expected for copies of a colored source.
        source_id = old['album']['compositions'][owner]['selectedArrangementID']
        source_arrangement = next(a for a in old['arrangements'] if a['id'] == source_id)
        assert len(copied['uses']) == len(source_arrangement['uses'])
        mapping = {}
        for a, b in zip(source_arrangement['uses'], copied['uses']):
            assert a['id'] != b['id']
            expected_use = copy.deepcopy(a); expected_use['id'] = b['id']
            assert b == expected_use
            mapping[a['id']] = b['id']
        for key, color in old.get('circleColors', {}).items():
            address = json.loads(key)
            if address.get('section', {}).get('arrangementID') == source_id:
                address['section']['arrangementID'] = copied['id']
                address['section']['useID'] = mapping[address['section']['useID']]
                expected['circleColors'][json.dumps(address, sort_keys=True)] = color
        assert expected == new, (earlier, later)
        a = captures[earlier]['state']; b = captures[later]['state']
        assert a['activeArrangementID'] == b['activeArrangementID']
        assert a['selection'] == b['selection']
        assert a['playback']['editorAddress'] is not None
        assert a['playback']['editorAddress'] == b['playback']['editorAddress']

    for earlier, later, owner in [('background-other', 'background-select-other', 1),
                                  ('background-select-other', 'background-select-same', 0),
                                  ('background-select-current-before', 'background-select-current', 0)]:
        old = normalized(manifest(earlier), True); new = normalized(manifest(later), True)
        expected = copy.deepcopy(old)
        chosen = new['album']['compositions'][owner]['selectedArrangementID']
        assert chosen != old['album']['compositions'][owner]['selectedArrangementID']
        expected['album']['compositions'][owner]['selectedArrangementID'] = chosen
        expected['activeArrangementID'] = chosen
        assert expected == new
        assert captures[later]['state']['selection'] == {'composition': {'_0': new['album']['compositions'][owner]['id']}}
    assert captures['background-select-current-before']['state']['playback']['editorAddress'] is not None
    assert normalized(manifest('background-before'), True) == normalized(manifest('background-restored'), True)
    assert normalized(manifest('background-restored')) == normalized(manifest('background-reopened'))
    final_package = load('background/package')
    assert '4CFB513F-26F5-3FCB-AC28-A6E18054A112' in final_package['uuid']
    fixture = Path(package['fixture'])
    source_path = fixture.with_name('studio.circlr') / 'manifest.json'
    digest = hashlib.sha256(source_path.read_bytes()).hexdigest()
    assert digest == package['sourceSHA256'] == '12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d'
    assets = manifest('background-reopened')['assets']
    assert len(assets) == 2
    for asset in assets:
        for folder in [source_path.parent, fixture]:
            assert hashlib.sha256((folder / asset['path']).read_bytes()).hexdigest() == asset['checksum'], asset['path']
    print(json.dumps({'status': 'passed', 'nativeSnapshots': len(names),
                      'physicalAudioAttempts': 0, 'sourceSHA256': digest,
                      'preservedAssets': len(assets),
                      'historicalBackgroundRegressionReproduced': True,
                      'backgroundClonePreservesEditor': True,
                      'finalPackageUUID': final_package['uuid'],
                      'packageUUID': package['uuid'],
                      'keyboardPackageUUID': keyboard_package['uuid']}, ensure_ascii=False))


if __name__ == '__main__':
    main()
