#!/usr/bin/env python3
"""Read-only native evidence validation; never calls the application or audio devices."""
import copy
import hashlib
import json
import math
from pathlib import Path
import struct

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'qa/generated/audio-tempo-region'


def load(path):
    return json.loads(path.read_text())


def music(project):
    result = copy.deepcopy(project)
    result.pop('musicRevision', None)
    result.pop('hierarchyView', None)
    return result


def by_id(values, identifier):
    matches = [v for v in values if v['id'] == identifier]
    assert len(matches) == 1, identifier
    return matches[0]


def use(project, scenario):
    return by_id(by_id(project['arrangements'], scenario['arrangementID'])['uses'], scenario['useID'])


def graph(project, scenario):
    target = use(project, scenario)
    result = copy.deepcopy(by_id(project['sections'], scenario['sectionID'])['graph'])
    edits = target.get('graphEdits', {})
    for kind in ('node', 'edge'):
        values = kind+'s'
        result[values] = [edits.get(kind+'Overrides', {}).get(v['id'],v) for v in result[values]
                          if v['id'] not in edits.get('removed'+kind.title()+'IDs', [])]
        result[values] += edits.get('added'+kind.title()+'s', [])
    if 'layout' in edits: result['layout'] = edits['layout']
    return result


def wav(path):
    data = path.read_bytes()
    assert data[:4] == b'RIFF' and data[8:12] == b'WAVE'
    offset = 12
    fmt = samples = None
    while offset + 8 <= len(data):
        tag, length = data[offset:offset+4], struct.unpack_from('<I', data, offset+4)[0]
        payload = data[offset+8:offset+8+length]
        assert len(payload) == length
        if tag == b'fmt ': fmt = payload
        if tag == b'data': samples = payload
        offset += 8 + length + length % 2
    assert fmt is not None and samples is not None
    kind, channels, rate, _, alignment, bits = struct.unpack_from('<HHIIHH', fmt)
    if kind == 65534:
        assert len(fmt) >= 40
        kind = struct.unpack_from('<H', fmt, 24)[0]
    assert channels == 2 and rate == 48000 and alignment == channels * bits // 8
    assert len(samples) > 0 and len(samples) % alignment == 0
    if kind == 3:
        assert bits in (32, 64)
        values = [x[0] for x in struct.iter_unpack('<f' if bits == 32 else '<d', samples)]
        assert all(math.isfinite(v) for v in values) and max(map(abs, values)) > 1e-7
    else:
        assert kind == 1 and bits in (16, 24, 32) and any(samples)
    return len(samples) // alignment, rate, hashlib.sha256(data).hexdigest()


def main():
    scenario = load(OUT / 'baseline/scenario.json')
    seed = load(OUT / 'baseline/fixture-initial.json')
    package = load(OUT / 'final/package.json')
    injection = load(OUT / 'final/qa-injection.json')
    assert injection['qaOnlyMock'] and injection['denyOutput'] and injection['outputWorkerExit']==78
    assert package['build']=='113' and package['projectID']==scenario['projectID']
    for helper, checksum in injection['packagedHelperSHA256'].items():
        path=Path(package['app'])/'Contents/MacOS'/helper
        assert hashlib.sha256(path.read_bytes()).hexdigest()==checksum
    assert hashlib.sha256(Path(injection['preservedOutputWorker']).read_bytes()).hexdigest()==injection['productionHelperSHA256']['circlr-output-worker']
    revisions = dict(before=14, split=15, **{'split-undo':16, 'bounced':17, 'bounce-undo':18,
        'crossing-before':18, 'crossing-rejected':18, 'restored':18, 'reopened':18})
    captures = {name:load(OUT / 'final' / (name+'.json')) for name in revisions}
    base = captures['before']['manifest']
    assert music(base) == music(seed)
    for name, capture in captures.items():
        state, project = capture['state'], capture['manifest']
        assert state['projectID'] == project['id'] == scenario['projectID']
        assert state['revision'] == project['musicRevision'] == revisions[name], name
        assert state['runtime']['build'] == '113'
        assert state['runtime']['bundleID'] == 'com.circlr.integrationqa'
        assert not state['playback']['playing']
        assert state['output']['attempts'] == state['audition']['attempts'] == 0
        assert not any(state['recording'][key] for key in ('audio','midi','busy'))
        assert project['sections'] == base['sections'] and project['tracks'] == base['tracks'], name
        assert project['assets'][:2] == base['assets'] and len(base['assets']) == 2
        expected = music(base)
        target = use(expected, scenario)
        target.clear(); target.update(copy.deepcopy(use(project, scenario)))
        expected['assets'] = copy.deepcopy(project['assets'])
        assert expected == music(project), name
    for name in ('split-undo','bounce-undo','crossing-before','crossing-rejected','restored','reopened'):
        assert music(captures[name]['manifest']) == music(base), name
    reopened=captures['reopened']
    assert not reopened['state']['dirty']
    assert captures['restored']['manifest']==reopened['manifest']==load(Path(scenario['fixture'])/'manifest.json')
    assert captures['restored']['state']['path']==reopened['state']['path']==scenario['fixture']
    open_job=reopened['state']['job']
    assert open_job['kind']=='open' and open_job['state']=='completed' and open_job['progress']==1
    assert open_job['path']==scenario['fixture']
    # Reconstruct the split from the original selected clip, not from claimed success flags.
    source = scenario['constantRegion']
    original = by_id(by_id(base['sections'], scenario['sectionID'])['lanes'], source['laneID'])
    lane = use(captures['split']['manifest'], scenario)['laneOverrides'][source['laneID']]
    assert {k:v for k,v in lane.items() if k!='audio'} == {k:v for k,v in original.items() if k!='audio'}
    clip = by_id(original['audio'], source['clipID'])
    left = copy.deepcopy(clip)
    window = dict(sourceStart=clip['sourceStart'],duration=clip['duration'],cycleBeat=clip['beat'],automaticEdges=False,envelopes=[])
    left.update(duration=0.5,renderWindow=window,fadeIn=0,fadeOut=0)
    right_candidates = [c for c in lane['audio'] if c['id'] not in {v['id'] for v in original['audio']}]
    assert len(right_candidates) == 1
    right = copy.deepcopy(clip)
    right.update(id=right_candidates[0]['id'],sourceStart=0.5,duration=0.5,beat=1,renderWindow=window,fadeIn=0,fadeOut=0)
    assert lane['audio'] == [left if c['id']==clip['id'] else c for c in original['audio']] + [right]
    assert len(captures['split']['manifest']['assets']) == 2
    split_use, base_use = use(captures['split']['manifest'], scenario), use(base, scenario)
    for key in set(base_use) | set(split_use):
        if key not in ('laneOverrides','graphEdits'): assert split_use.get(key) == base_use.get(key), key
    for lane_id, value in base_use.get('laneOverrides',{}).items():
        if lane_id != source['laneID']: assert split_use['laneOverrides'][lane_id] == value
    original_graph = graph(base, scenario)
    split_graph = graph(captures['split']['manifest'], scenario)
    expected_graph = copy.deepcopy(original_graph)
    node = by_id(expected_graph['nodes'], source['nodeID'])
    added_nodes = [n for n in split_graph['nodes'] if n['id'] not in {v['id'] for v in original_graph['nodes']}]
    assert len(added_nodes) == 1
    other = copy.deepcopy(node)
    other.update(id=added_nodes[0]['id'],name=node['name']+' · 뒤')
    other['content'] = {'audio':dict(laneID=source['laneID'],clipID=right['id'])}
    expected_graph['nodes'].append(other)
    existing_edge_ids = {e['id'] for e in original_graph['edges']}
    new_edges = [e for e in split_graph['edges'] if e['id'] not in existing_edge_ids]
    outgoing = [e for e in original_graph['edges'] if e['from']==node['id']]
    assert len(new_edges) == len(outgoing)
    for edge, observed in zip(outgoing,new_edges):
        expected_edge = dict(edge,id=observed['id'])
        expected_edge['from'] = other['id']
        expected_graph['edges'].append(expected_edge)
    position = expected_graph['layout']['positions'].get(node['id'],dict(x=0,y=0))
    expected_graph['layout']['positions'][other['id']] = dict(x=position['x']+90,y=position['y']+130)
    for group in expected_graph['layout'].get('groups',[]):
        if node['id'] in group['members']: group['members'].append(other['id'])
    assert expected_graph == split_graph
    # Bounce must create one real, non-silent WAV while preserving both source assets.
    bounced = captures['bounced']['manifest']
    assert len(bounced['assets']) == 3
    asset = bounced['assets'][2]
    job = captures['bounced']['state']['job']
    assert job['kind']=='bounce' and job['state']=='completed' and job['progress']==1
    bgraph = graph(bounced, scenario)
    bnode = by_id(bgraph['nodes'],job['nodeID'])
    track = original['trackID']
    output = next(n for n in original_graph['nodes'] if n['content'].get('output',{}).get('trackID')==track)
    inputs = [e for e in original_graph['edges'] if e['to']==output['id']]
    section = by_id(base['sections'],scenario['sectionID'])
    assert base['global']['meter']==dict(numerator=4,denominator=4) and not section.get('meterChanges')
    total_beats=base_use.get('barsOverride',section['bars'])*4
    body = 8*60/120 + (total_beats-8)*60/140
    tail = job['tail']['effectiveSeconds']
    assert abs(job['renderedSeconds']-asset['duration'])<=1/48000
    assert abs(asset['duration']-body-tail)<=1/48000
    assert asset['name']==by_id(base['tracks'],track)['name']+' 바운스'
    expected_node = dict(id=bnode['id'],name=asset['name'],content=copy.deepcopy(bnode['content']),
        settings={key:{'source':'inherit'} for key in ('beatGrid','meter','rhythm','scale','tempo')},
        startBeat=0,repeatCount=1,gain=1,muted=False,
        bounce=dict(outputNodeID=output['id'],replacedInputs=inputs,sourceRevision=16,bodySeconds=body,tailSeconds=tail))
    assert bnode == expected_node
    audio = bnode['content']['audio']
    buse = use(bounced,scenario)
    new_lanes = [lane for lane in buse.get('addedLanes',[]) if lane['id'] not in {x['id'] for x in base_use.get('addedLanes',[])}]
    expected_clip = dict(id=audio['clipID'],assetID=asset['id'],duration=asset['duration'],beat=0,sourceStart=0,
        gain=1,followsTempo=False,sourceBPM=120,preservesTail=True)
    assert new_lanes == [dict(id=audio['laneID'],trackID=track,notes=[],audio=[expected_clip])]
    for key in set(base_use)|set(buse):
        if key not in ('graphEdits','addedLanes'): assert buse.get(key)==base_use.get(key),key
    assert buse['addedLanes']==base_use.get('addedLanes',[])+new_lanes
    expected_bgraph=copy.deepcopy(original_graph)
    expected_bgraph['nodes'].append(expected_node)
    edges=[e for e in bgraph['edges'] if e['id'] not in {v['id'] for v in original_graph['edges']}]
    assert len(edges)==1
    expected_bgraph['edges']=[e for e in original_graph['edges'] if e['to']!=output['id']]+[
        dict(id=edges[0]['id'],**{'from':bnode['id'],'to':output['id']},signal='audio',gain=1,sidechain=False)]
    position=original_graph['layout']['positions'].get(output['id'],dict(x=0,y=0))
    expected_bgraph['layout']['positions'][bnode['id']]=dict(x=position['x']-240,y=position['y']-220)
    assert expected_bgraph==bgraph
    rejected=captures['crossing-rejected']['state']['job']
    assert rejected['kind']=='bounce' and rejected['state']=='failed' and rejected['id']!=job['id']
    assert '템포' in rejected['message'] and '바뀝니다' in rejected['message']
    success_response=load(OUT/'final/bounce-job.json')
    failure_response=load(OUT/'final/crossing-bounce-job.json')
    assert success_response==dict(job=job,revision=17)
    assert failure_response==dict(job=rejected,revision=18)
    alert=(OUT/'final/crossing-split-rejected.ax.txt').read_text()
    assert 'sheet Description: alert' in alert and rejected['message'] in alert
    assert (OUT/'final/crossing-split-rejected.jpg').stat().st_size>0

    path = Path(asset['path'])
    if not path.is_absolute(): path = Path(scenario['fixture']) / path
    preserved = OUT / 'final/bounced.wav'
    if preserved.exists(): path = preserved
    frames, rate, digest = wav(path)
    assert digest == asset['checksum']
    assert abs(frames/rate-asset['duration']) <= 1/rate
    for source_asset in base['assets']:
        original_path = Path(scenario['fixture']) / source_asset['path']
        assert hashlib.sha256(original_path.read_bytes()).hexdigest() == source_asset['checksum']
    print('PASS: tempo-region native edits, Undo, persistence, source preservation, and offline WAV; physical output not exercised')


if __name__ == '__main__':
    main()
