#!/usr/bin/env python3
"""Read-only arrangement continuation evidence checks; native contract pending."""
import argparse
import hashlib
import copy
import importlib.util
import json
from pathlib import Path
import uuid

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'qa/generated/arrangement-continuation'
spec = importlib.util.spec_from_file_location('compact_checks', Path(__file__).with_name('check-midi-compact-evidence.py'))
c = importlib.util.module_from_spec(spec)
spec.loader.exec_module(c)


def load(path):
    return json.loads(path.read_text())


def fresh_ids(before, after):
    assert len(before) == len(after) and len(set(after)) == len(after)
    assert not set(before).intersection(after)
    for value in after:
        uuid.UUID(value)
    return dict(zip(before, after))


def duplicate_expected(seed, actual, source_id, owner_id, name):
    """Reconstruct the full permitted delta, borrowing only fresh UUIDs from native."""
    expected = c.music(seed)
    source = next(a for a in expected['arrangements'] if a['id'] == source_id)
    assert len(actual['arrangements']) == len(seed['arrangements']) + 1
    clone = actual['arrangements'][-1]
    uuid.UUID(clone['id'])
    assert clone['id'] not in {a['id'] for a in expected['arrangements']}
    assert clone['name'] == name
    uses = fresh_ids([u['id'] for u in source['uses']], [u['id'] for u in clone['uses']])
    assert not set(uses.values()).intersection(u['id'] for a in seed['arrangements'] for u in a['uses'])
    edges = fresh_ids([e['id'] for e in source['edges']], [e['id'] for e in clone['edges']])
    groups = fresh_ids([g['id'] for g in source['layout']['groups']], [g['id'] for g in clone['layout']['groups']])
    copied = copy.deepcopy(source)
    copied.update(id=clone['id'], name=name)
    for use in copied['uses']:
        use['id'] = uses[use['id']]
    for edge in copied['edges']:
        edge.update(id=edges[edge['id']], **{'from': uses[edge['from']], 'to': uses[edge['to']]})
    copied['chosenEdges'] = {uses[key]: edges[value] for key, value in copied['chosenEdges'].items()}
    if copied.get('startID'):
        copied['startID'] = uses[copied['startID']]
    copied['layout']['positions'] = {uses.get(key, key): value for key, value in copied['layout']['positions'].items()}
    for group in copied['layout']['groups']:
        group['id'] = groups[group['id']]
        group['members'] = [uses[value] for value in group['members']]
    assert clone == copied, 'Clone has changes beyond exact address remapping'
    expected['arrangements'].append(copied)
    expected['activeArrangementID'] = copied['id']
    owner = next(item for item in expected['album']['compositions'] if item['id'] == owner_id)
    owner['arrangementIDs'].append(copied['id'])
    owner['selectedArrangementID'] = copied['id']

    def remap(address):
        key = next(iter(address))
        value = address[key]
        if key in ['section', 'music'] and value['arrangementID'] == source_id and value['useID'] in uses:
            result = copy.deepcopy(address)
            result[key].update(arrangementID=copied['id'], useID=uses[value['useID']])
            return result
        if key == 'group':
            parent = remap(value['parent'])
            if parent is not None:
                return {'group': dict(value, parent=parent)}
            if value['parent'] == {'composition': {'id': owner_id}} and value['id'] in groups:
                return {'group': dict(value, id=groups[value['id']])}
        return None

    colors = expected.get('circleColors') or {}
    for address, color in list(colors.items()):
        mapped = remap(json.loads(address))
        if mapped is not None:
            colors[json.dumps(mapped, sort_keys=True)] = color
    return expected, uses


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--candidate', default='final')
    args = parser.parse_args()
    assert args.candidate == 'final'
    final = OUT / args.candidate
    scenario = load(OUT / 'baseline/scenario.json')
    seed = load(OUT / 'baseline/fixture-initial.json')
    package = load(final / 'package.json')
    assert package['build'] == '112' and seed['musicRevision'] == scenario['initialRevision'] == 14
    injection = load(final / 'qa-injection.json')
    assert injection['qaOnlyMock'] is True and injection['denyOutput'] is True
    assert injection['candidate'] == args.candidate and injection['outputWorkerExit'] == 78
    assert injection['strictSignatureVerified'] is True
    helpers = {'circlr-output-worker', 'circlr-au-effect-worker', 'circlr-au-instrument-worker', 'circlr-output-device-catalog'}
    assert set(injection['productionHelperSHA256']) == set(injection['packagedHelperSHA256']) == helpers
    for helper in helpers:
        binary = Path(package['app']) / 'Contents/MacOS' / helper
        assert hashlib.sha256(binary.read_bytes()).hexdigest() == injection['packagedHelperSHA256'][helper]
        if helper != 'circlr-output-worker':
            assert injection['productionHelperSHA256'][helper] == injection['packagedHelperSHA256'][helper]
    assert hashlib.sha256(Path(injection['preservedOutputWorker']).read_bytes()).hexdigest() == injection['productionHelperSHA256']['circlr-output-worker']
    stub = final / 'deny-output.c'
    assert hashlib.sha256(stub.read_bytes()).hexdigest() == injection['stubSourceSHA256']
    assert stub.read_text().strip() == 'int main(void){return 78;}'
    original = c.music(seed)
    source_id = scenario['currentArrangementID']
    owner_id = next(o['id'] for o in seed['album']['compositions'] if source_id in o['arrangementIDs'])
    revisions = {'before':14, 'audio-cloned':15, 'audio-continued':15, 'audio-edited':16,
        'audio-edit-undo':17, 'audio-clone-undo':18, 'automation-before':18,
        'automation-cloned':19, 'automation-continued':19, 'automation-clone-undo':20,
        'other-cloned':21, 'other-clone-undo':22, 'restored':22, 'reopened':22}
    captures = {name: load(final / (name + '.json')) for name in revisions}
    expected_clones = {}
    for kind, arrangement in [('audio', source_id), ('automation', source_id), ('other', scenario['candidateArrangementID'])]:
        actual = captures[kind + '-cloned']['manifest']
        # Native clone names are validated as nonempty; only UUIDs and the user-entered
        # name vary. Every musical field is reconstructed from the source seed.
        name = actual['arrangements'][-1]['name']
        assert isinstance(name, str) and name.strip() == name and 1 <= len(name) <= 120
        expected_clones[kind] = duplicate_expected(seed, actual, arrangement, owner_id, name)
    for name, capture in captures.items():
        c.guard(capture, package, revisions[name])
        expected = original
        if name in ['audio-cloned', 'audio-continued', 'audio-edited', 'audio-edit-undo']:
            expected = copy.deepcopy(expected_clones['audio'][0])
            if name == 'audio-edited':
                use_id = expected_clones['audio'][1][scenario['targetUseID']]
                use = next(u for u in expected['arrangements'][-1]['uses'] if u['id'] == use_id)
                section = next(item for item in expected['sections'] if item['id'] == use['sectionID'])
                lane = copy.deepcopy(use['laneOverrides'].get(scenario['laneID']) or next(l for l in section['lanes'] if l['id'] == scenario['laneID']))
                clip = next(item for item in lane['audio'] if item['id'] == scenario['clipID'])
                assert clip['gain'] == 1
                clip['gain'] = 10 ** (-6 / 20)
                use['laneOverrides'][lane['id']] = lane
        elif name in ['automation-cloned', 'automation-continued']:
            expected = expected_clones['automation'][0]
        elif name == 'other-cloned':
            expected = expected_clones['other'][0]
        assert c.music(capture['manifest']) == expected, name
    for kind in ['audio', 'automation']:
        continued = captures[kind + '-continued']
        copied, use_map = expected_clones[kind]
        destination = dict(arrangementID=copied['activeArrangementID'], useID=use_map[scenario['targetUseID']], nodeID=scenario['nodeID'])
        assert continued['state']['selection']['music'] == destination
        assert continued['manifest']['hierarchyView']['selection'] == {'music': destination}
        workspace = continued['manifest']['hierarchyView']['workspace']
        before = captures['before' if kind == 'audio' else 'automation-before']['manifest']['hierarchyView']['workspace']
        expected_workspace = copy.deepcopy(before)
        expected_workspace['original'] = False
        expected_workspace.pop('connection', None)
        expected_workspace.pop('transitionID', None)
        assert workspace == expected_workspace, kind
        assert workspace['page'] == ('content' if kind == 'audio' else 'automation')
        if kind == 'automation':
            assert workspace['automationParameter'] == scenario['automationParameter']
            assert scenario['targetPointID'] in json.dumps(workspace['selection'])
    for kind in ['audio', 'automation']:
        text = (final / (kind + '-cloned.ax.txt')).read_text()
        assert '복제한 오디오 계속 편집 · ⇧⌘E' in text
        assert '복제한 이번 사용' in text
    edited_ax = (final / 'audio-edited.ax.txt').read_text()
    assert any('Description: 오디오 볼륨 dB' in line and 'Value: -6.00' in line for line in edited_ax.splitlines())
    other_ax = (final / 'other-cloned.ax.txt').read_text()
    assert '계속 편집 · ⇧⌘E' not in other_ax
    extra = {name: load(final / (name + '.json')) for name in
             ['original-before', 'rename-confirmed', 'original-continued']}
    for name, revision in [('original-before', 22), ('rename-confirmed', 23), ('original-continued', 23)]:
        c.guard(extra[name], package, revision)
    assert c.music(extra['original-before']['manifest']) == original
    original_workspace = extra['original-before']['manifest']['hierarchyView']['workspace']
    assert original_workspace['original'] is True
    renamed, original_map = duplicate_expected(seed, extra['rename-confirmed']['manifest'], source_id,
                                               owner_id, '원본 보호 이름 변경')
    assert c.music(extra['rename-confirmed']['manifest']) == renamed
    assert c.music(extra['original-continued']['manifest']) == renamed
    protected_workspace = copy.deepcopy(original_workspace)
    protected_workspace['original'] = False
    # The MCP-seeded original-mode workspace omitted editor state. Continuation
    # restores the already-observed audio editor; do not accept arbitrary fields.
    assert 'editor' not in original_workspace
    protected_workspace['editor'] = copy.deepcopy(captures['before']['manifest']['hierarchyView']['workspace']['editor'])
    protected_workspace.pop('connection', None)
    protected_workspace.pop('transitionID', None)
    assert extra['original-continued']['manifest']['hierarchyView']['workspace'] == protected_workspace
    assert extra['original-continued']['state']['selection']['music'] == dict(
        arrangementID=renamed['activeArrangementID'], useID=original_map[scenario['targetUseID']], nodeID=scenario['nodeID'])
    tail_revisions = {'stale-before':24, 'stale-deleted':25, 'stale-rejected':25,
                      'original-undo-name':26, 'original-undo-clone':27,
                      'final-restored':27, 'final-reopened':27}
    tail = {name: load(final / (name + '.json')) for name in tail_revisions}
    stale_expected, _ = duplicate_expected(extra['rename-confirmed']['manifest'],
        tail['stale-before']['manifest'], renamed['activeArrangementID'], owner_id, '삭제될 편곡')
    name_undone = copy.deepcopy(renamed)
    name_undone['arrangements'][-1]['name'] = '원본 보호 대안'
    for name, capture in tail.items():
        c.guard(capture, package, tail_revisions[name])
        expected = original
        if name == 'stale-before': expected = stale_expected
        elif name in ['stale-deleted', 'stale-rejected']: expected = renamed
        elif name == 'original-undo-name': expected = name_undone
        assert c.music(capture['manifest']) == expected, name
    assert tail['stale-deleted']['manifest'] == tail['stale-rejected']['manifest']
    assert tail['stale-deleted']['state']['selection'] == tail['stale-rejected']['state']['selection']
    stale_ax = (final / 'stale-rejected.ax.txt').read_text()
    assert 'button (disabled) Description: 복제한 오디오 계속 편집 · ⇧⌘E' in stale_ax
    assert '대상이나 음악이 바뀌었거나 다른 작업 중입니다. 닫은 뒤 다시 열어주세요.' in stale_ax
    fixture = Path(package['fixture'])
    source = Path(scenario['source'])
    assert hashlib.sha256((source / 'manifest.json').read_bytes()).hexdigest() == scenario['sourceSHA256']
    for asset in seed['assets']:
        relative = Path(asset['path'])
        assert relative.parts and not relative.is_absolute() and '..' not in relative.parts
        for root in [fixture, source]:
            assert hashlib.sha256((root / relative).read_bytes()).hexdigest() == asset['checksum']
    assert captures['restored']['manifest'] == captures['reopened']['manifest']
    assert tail['final-restored']['manifest'] == tail['final-reopened']['manifest'] == load(fixture / 'manifest.json')
    job = tail['final-reopened']['state']['job']
    assert job['kind'] == 'open' and job['state'] == 'completed' and job['path'] == str(fixture) and job['progress'] == 1
    print(json.dumps(dict(status='passed', candidate=args.candidate, snapshots=len(captures) + len(extra) + len(tail), sharedOriginalModeForcedOff=True,
        exactCloneMusic=True, exactAudioAndAutomationReturn=True, sourceArrangementPreserved=True,
        strictUndoMusic=True, strictReopenEquality=True, physicalAudioAttempts=0,
        staleDisabledNoOpVerified=True, staleHandlerInvocationVerified=False, nonemptyArrangementGroupColorRemapVerified=False)))


if __name__ == '__main__':
    main()
