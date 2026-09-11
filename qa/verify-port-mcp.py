#!/usr/bin/env python3
"""Exercise explicit port MCP only against the isolated, stopped playback QA fixture."""
import argparse
import copy
import importlib.util
import json
from pathlib import Path
import re
import time

spec = importlib.util.spec_from_file_location('ports_native', Path(__file__).with_name('verify-ports-native.py'))
qa = importlib.util.module_from_spec(spec)
spec.loader.exec_module(qa)
from mcp.server import call_tool


def run(path):
    evidence = []
    def state():
        s = qa.state()
        assert s['path'] == str(qa.PROJECT.with_name('ports-playback.circlr'))
        assert s['projectID'] == 'A727DC35-BB4D-5C79-AEB1-004A2F0CC2B0'
        assert not s['recording']['permissionPending'] and not s['playback']['playing']
        return s

    def call(name, args=None):
        state()
        result = qa.call(name, args)
        evidence.append({'method': name, 'arguments': args or {}, 'result': result})
        return result

    def revisions(s):
        return {'projectID': s['projectID'], 'expectedRevision': s['revision'], 'expectedLayoutRevision': s['layoutRevision']}

    def write(name, args=None):
        return call(name, {**revisions(state()), **(args or {})})

    def wait_minimized():
        deadline = time.monotonic() + 5
        while True:
            windows = state()['runtime']['windows']
            if windows and all(w['minimized'] for w in windows):
                return
            assert time.monotonic() < deadline, 'Window did not finish minimizing'
            time.sleep(0.2)

    def reject(name, args, message):
        before = state()
        result = call_tool(str(qa.SOCKET), 'circlr_' + name, args)['structuredContent']
        evidence.append({'method': name, 'arguments': args, 'rejected': result})
        assert not result['ok'] and message in result['error'], result
        after = state()
        assert (after['revision'], after['layoutRevision']) == (before['revision'], before['layoutRevision'])

    before = state()
    use = before['arrangements'][0]['uses'][0]['id']
    arrangement = before['arrangements'][0]['id']
    scope = {'arrangementID': arrangement, 'useID': use}
    inspection = call('inspect', scope)
    graph = inspection['graph']
    router = next(n for n in graph['nodes'] if 'router' in n['content'])
    sources = [n for n in graph['nodes'] if 'audio' in n['content']]
    assert len(sources) == 2 and len(graph['edges']) == 4
    def address(node):
        return {'music': {**scope, 'nodeID': node['id']}}
    router_address = address(router)
    initial = call('ports', {'node': router_address})
    assert [p['id'] for p in initial['ports']] == ['in.audio.bus1', 'in.audio.bus2', 'out.audio.bus1', 'out.audio.bus2']
    assert len(initial['connections']) == 4
    assert all(c['canReconnect'] and c['canDisconnect'] for c in initial['connections'])
    source1, source2 = sources
    # Identify source ordering from actual routing, not display names.
    edge1 = next(c['connection'] for c in initial['connections'] if c['connection']['to']['portID'] == 'in.audio.bus1')
    if address(source1) != edge1['from']['node']:
        source1, source2 = source2, source1
    pair = {'first': {'node': router_address, 'portID': 'in.audio.bus2'},
            'second': {'node': address(source1), 'portID': 'out.audio.main'}, 'firstOctant': 1, 'secondOctant': 5}
    minimized = False
    try:
        call('focus', {'minimized': True}); minimized = True
        wait_minimized()
        created = write('connect_ports', pair)
        assert created['changed'] and created['revision'] == before['revision'] + 1
        id1 = created['connectionID']
        duplicate = write('connect_ports', {**pair, 'firstOctant': 0})
        assert not duplicate['changed'] and duplicate['revision'] == created['revision']
        assert duplicate['layoutRevision'] == created['layoutRevision'] and duplicate['connectionID'] == id1
        reject('connect_ports', {**revisions(before), **pair}, 'stale_revision')
        reconnect = {**pair, 'connectionID': id1,
                     'first': {'node': router_address, 'portID': 'in.audio.bus1'},
                     'second': {'node': address(source2), 'portID': 'out.audio.main'}}
        changed = write('reconnect_ports', reconnect)
        assert changed['changed'] and changed['connectionID']['edgeID'] == id1['edgeID']
        id2 = changed['connectionID']
        reject('disconnect_ports', {**revisions(state()), 'connectionID': id1}, '케이블이 없습니다')
        removed = write('disconnect_ports', {'connectionID': id2})
        assert removed['changed']
        for _ in range(3):
            write('undo')
        assert call('inspect', scope)['graph'] == graph
        catalog = call('ports', {'node': router_address})
        assert catalog['connections'] == initial['connections']
        move_base = state()
        moves = [{'id': c['connection']['id'], 'placement': {'from': i * 2, 'to': i * 2 + 1}}
                 for i, c in enumerate(catalog['connections'])]
        moved = write('move_ports', {'moves': moves})
        assert moved['changed'] and moved['revision'] == move_base['revision']
        assert moved['layoutRevision'] == move_base['layoutRevision'] + 1
        placements = {json.dumps(c['connection']['id'], sort_keys=True): c['placement'] for c in call('ports', {'node': router_address})['connections']}
        assert all(placements[json.dumps(m['id'], sort_keys=True)] == m['placement'] for m in moves)
        assert not write('move_ports', {'moves': moves})['changed']
        reject('move_ports', {**revisions(move_base), 'moves': moves}, 'stale_layout')
        reject('undo', revisions(move_base), 'stale_layout')
        invalid = copy.deepcopy(moves)
        invalid[0]['placement'] = {'from': 7, 'to': 0}
        invalid[-1]['id']['edgeID'] = 'nonexistent-port-qa'
        reject('move_ports', {**revisions(state()), 'moves': invalid}, '연결을 찾을 수 없습니다')
        restored = write('undo')
        assert restored['revision'] == move_base['revision']
        assert restored['layoutRevision'] == moved['layoutRevision'] + 1
        assert call('ports', {'node': router_address})['connections'] == initial['connections']
        assert call('inspect', scope)['graph'] == graph
        current = state()
        assert current['selection'] == before['selection'] and current['view']['zoom'] == before['view']['zoom']
        assert all(w['minimized'] for w in current['runtime']['windows'])
        call('save', {'projectID': current['projectID'], 'expectedRevision': current['revision']})
        saved = json.loads((Path(current['path']) / 'manifest.json').read_text())
        opened = call('open', {'projectID': current['projectID'], 'expectedRevision': current['revision'], 'path': current['path']})
        deadline = time.monotonic() + 20
        while True:
            job = qa.call('job', {'jobID': opened['jobID']})
            if job['job']['state'] != 'running':
                break
            assert time.monotonic() < deadline
            time.sleep(1)
        evidence.append({'method': 'job', 'result': job})
        assert job['job']['state'] == 'completed'
        assert call('inspect', scope)['graph'] == graph
        reopened = call('ports', {'node': router_address})
        assert reopened['layoutRevision'] == current['layoutRevision'] and reopened['revision'] == current['revision']
        assert reopened['connections'] == initial['connections']
        assert json.loads((Path(current['path']) / 'manifest.json').read_text()) == saved
        evidence.append({'verified': 'minimal-window-background-edit-undo-stale-no-op-save-reopen', 'state': state()})
    finally:
        if minimized:
            qa.call('focus', {'minimized': False})
        path.write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'evidence': str(path), 'steps': len(evidence), 'revision': state()['revision'], 'layoutRevision': state()['layoutRevision']}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('evidence_name')
    args = parser.parse_args()
    assert re.fullmatch('[a-z0-9-]{1,64}', args.evidence_name)
    path = qa.OUT / (args.evidence_name + '.json')
    with path.open('x'):
        pass
    run(path)
