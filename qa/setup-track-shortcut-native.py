#!/usr/bin/env python3
"""Configure only the owned build88 shortcut fixture through revision-guarded MCP."""
import hashlib
import importlib.util
import json
from pathlib import Path
import time
import sys

spec = importlib.util.spec_from_file_location('capture', Path(__file__).with_name('verify-track-shortcut-native.py'))
v = importlib.util.module_from_spec(spec); spec.loader.exec_module(v)


def main():
    package = json.loads((v.OUT / 'baseline/package.json').read_text())
    out = v.OUT / 'baseline'; scenario_path = v.OUT / 'scenario.json'
    resume = sys.argv[1:] == ['--resume-first-batch']
    assert sys.argv[1:] in ([], ['--resume-first-batch'])
    assert not scenario_path.exists(), 'Preserve completed setup'
    assert resume or not (out / 'before.json').exists(), 'Use --resume-first-batch only after an atomic rejection'
    q = v.q; q.FIXTURE = Path(package['fixture']); q.PROJECT_ID = package['projectID']
    s = q.call('snapshot')
    assert s['runtime']['bundleID'] == 'com.circlr.integrationqa' and s['runtime']['build'] == '88'
    assert s['output']['attempts'] == s['audition']['attempts'] == 0
    assert not s['dirty'] and not s['recording']['busy'] and not s['playback']['playing']
    if s['path'] != package['fixture']:
        opened = q.call('open', {'projectID': s['projectID'], 'expectedRevision': s['revision'], 'path': package['fixture']})
        for _ in range(20):
            job = q.call('job', {'jobID': opened['jobID']})['job']
            if job['state'] != 'running': break
            time.sleep(1)
        assert job['state'] == 'completed', job
    if resume:
        before = json.loads((out / 'before.json').read_text())
        assert q.state()['revision'] == before['state']['revision']
        assert json.loads(q.FIXTURE.joinpath('manifest.json').read_text()) == before['manifest']
    else:
        v.capture('before', 'baseline')
    s = q.state(); arrangement = next(a for a in s['arrangements'] if a['id'] == s['activeArrangementID'])
    use = arrangement['uses'][0]; scope = {'arrangementID': arrangement['id'], 'useID': use['id']}
    original = q.call('inspect', scope)
    source = next(n for n in original['graph']['nodes'] if n['name'] == '검증 톤 1')
    lane_id = source['content']['audio']['laneID']
    track_id = next(l for l in original['lanes'] if l['id'] == lane_id)['trackID']
    ops = [dict(scope, kind='edit_audio', nodeID=source['id'], edit='duplicate', beatOffset=0),
           dict(scope, kind='add_effect', **{'from': source['id']}, name='첫 번째 게인', effect={'kind': 'gain', 'amount': .5, 'secondary': .25}),
           dict(scope, kind='add_effect', **{'from': source['id']}, name='두 번째 게인', effect={'kind': 'gain', 'amount': .75, 'secondary': .25}),
           dict(scope, kind='add_midi', trackID=track_id, notes=[])]
    q.write('apply', {'operations': ops})
    v.capture('candidates-connected', 'baseline')
    prepared = q.call('inspect', scope)
    old_ids = {n['id'] for n in original['graph']['nodes']}
    new_nodes = [n for n in prepared['graph']['nodes'] if n['id'] not in old_ids]
    copied = next(n for n in new_nodes if 'audio' in n['content'])
    copy_edges = [e for e in prepared['graph']['edges'] if e['from'] == copied['id']]
    assert len(copy_edges) == 1
    edge = copy_edges[0]
    def address(node): return {'music': dict(scope, nodeID=node)}
    q.write('disconnect_ports', {'expectedLayoutRevision': q.state()['layoutRevision'],
                                 'connectionID': {'edgeID': edge['id'], 'from': address(edge['from']), 'to': address(edge['to'])}})
    q.call('focus', dict(scope, nodeID=source['id'], detail=True))
    v.capture('prepared', 'baseline')
    with scenario_path.open('x') as file:
        json.dump(dict(scope, trackID=track_id, sourceNodeID=source['id'], copyNodeID=copied['id'],
                       effectNodeIDs=[n['id'] for n in new_nodes if 'effect' in n['content']],
                       midiNodeIDs=[n['id'] for n in new_nodes if 'midi' in n['content']],
                       setupRevisions=[s['revision'], q.state()['revision']]), file, ensure_ascii=False, indent=2)
    source_path = q.FIXTURE.with_name('studio.circlr') / 'manifest.json'
    assert hashlib.sha256(source_path.read_bytes()).hexdigest() == package['sourceSHA256']
    print(scenario_path)


if __name__ == '__main__':
    main()
