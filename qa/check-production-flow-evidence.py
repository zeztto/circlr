#!/usr/bin/env python3
"""Read-only exact-change and offline PCM audit; no app, MCP or hardware calls."""
import copy
import importlib.util
import json
from pathlib import Path
import wave

spec = importlib.util.spec_from_file_location('flow_package', Path(__file__).with_name('prepare-production-flow-qa.py'))
p = importlib.util.module_from_spec(spec); spec.loader.exec_module(p)
D = p.OUT / 'current122'
TRACK = '7E0D9016-E91D-4325-B807-033F233E32EA'
REVISIONS = {'before':18, 'step-edited':19, 'sound-edited':20, 'effect-added':21, 'bounced':22,
             'source-restored':23, 'bounce-undone':25, 'all-undone':28, 'reopened':28}
read = lambda name: json.loads((D / (name + '.json')).read_text())
use = lambda m: m['arrangements'][0]['uses'][0]
graph = lambda m: use(m)['graphEdits']


def music(m):
    return {k:v for k,v in m.items() if k not in ['hierarchyView','musicRevision','layoutRevision','modifiedAt']}


def pcm(path):
    with wave.open(str(path), 'rb') as wav:
        assert wav.getframerate() == 48000 and wav.getsampwidth() == 3 and wav.getnchannels() == 2
        frames = wav.getnframes(); data = wav.readframes(frames)
        assert len(data) == frames * 6
        return frames, data


def main():
    package = read('package'); injection = read('qa-injection')
    scenario = json.loads((p.OUT / 'baseline/scenario.json').read_text())
    seed = json.loads((p.OUT / 'baseline/fixture-initial.json').read_text())
    assert package['build'] == '122' and package['projectID'] == p.PROJECT_ID and package['fixture'] == str(p.FIXTURE)
    assert p.digest(p.SOURCE / 'manifest.json') == package['sourceSHA256'] == scenario['sourceSHA256']
    mac = Path(package['app']) / 'Contents/MacOS'
    assert p.digest(mac / 'circlr') == package['packagedMainSHA256']
    assert p.run(['dwarfdump','--uuid',str(mac / 'circlr')]).split()[1] == package['sourceBinaryUUID'] == package['packagedMainUUID']
    p.run(['codesign','--verify','--deep','--strict',package['app']])
    assert injection['denyAllAudioHelpers'] and injection['helperExit'] == 78
    assert set(injection['packagedHelperSHA256']) == set(p.HELPERS)
    for helper in p.HELPERS:
        assert p.digest(mac / helper) == injection['packagedHelperSHA256'][helper]
        assert injection['productionHelperSHA256'][helper] == package['sourceBinarySHA256'][helper]
        assert injection['packagedHelperSHA256'][helper] != package['sourceBinarySHA256'][helper]
    resources = Path(package['app']) / 'Contents/Resources/Codex'
    assert p.digest(resources / 'manifest.json') == package['codexManifestSHA256']
    for name, checksum in json.loads((resources / 'manifest.json').read_text())['files'].items():
        assert p.digest(resources / name) == checksum
    docs = {}; retired_assets = set()
    def offline_safe(value):
        if isinstance(value, dict):
            assert value.get('kind') not in ['audioUnit', 'soundBank']
            assert value.get('followsTempo') is not True
            for child in value.values(): offline_safe(child)
        elif isinstance(value, list):
            for child in value: offline_safe(child)
    for name, revision in REVISIONS.items():
        record = read(name); s = record['state']; m = record['manifest']; docs[name] = m
        assert record['saved'] and record['packageBuild'] == s['runtime']['build'] == '122'
        assert s['runtime']['bundleID'] == 'com.circlr.integrationqa'
        assert s['projectID'] == m['id'] == p.PROJECT_ID and s['path'] == str(p.FIXTURE)
        assert s['revision'] == m['musicRevision'] == revision and not s['dirty']
        assert s['output']['attempts'] == s['audition']['attempts'] == 0 and not s['playback']['playing']
        assert s['output']['phase'] == s['audition']['phase'] == 'idle' and s['audition']['heldNotes'] == 0
        assert not any(s['recording'][k] for k in ['audio','midi','busy'])
        offline_safe(m)
        assert len(m['tracks']) == 3 and all(t['instrument']['kind'] == 'synthesizer' and t['instrument']['synth']['engineVersion'] == 3 for t in m['tracks'])
        originals = {a['id']:a for a in seed['assets']}; current = {a['id']:a for a in m['assets']}
        assert len(current) == len(m['assets']) == (3 if name in ['bounced','source-restored'] else 2)
        assert all(current.get(k) == a for k,a in originals.items())
        for a in m['assets']:
            path = Path(a['path']); assert not path.is_absolute() and '..' not in path.parts
            if (p.FIXTURE / path).exists():
                assert p.digest(p.FIXTURE / path) == a['checksum']
            else:
                assert a['id'] == '9C1F0FA8-CBC6-4940-B32E-6B975DBDB47E' and name in ['bounced','source-restored']
                assert a['id'] in record['newAssetIDs']
                assert a['checksum'] == '9387feb5f7b38cb5a3569cf2d6bbca106f09646a953a6d84a440d9fea1aadb1e'
                assert p.digest(D / 'bounced-asset.wav') == a['checksum']
                retired_assets.add(a['id'])
    assert music(docs['before']) == music(seed)
    expected = copy.deepcopy(docs['before'])
    notes = docs['step-edited']['patterns'][0]['notes']; old = expected['patterns'][0]['notes']
    added = [n for n in notes if n not in old]
    assert len(added) == 1 and {k:v for k,v in added[0].items() if k != 'id'} == dict(pitch=66,beat=0.5,length=0.225,velocity=96)
    expected['patterns'][0]['notes'].append(added[0]); assert music(expected) == music(docs['step-edited'])
    expected = copy.deepcopy(docs['step-edited'])
    next(t for t in expected['tracks'] if t['id'] == TRACK)['instrument']['synth']['cutoff'] = 2400
    assert music(expected) == music(docs['sound-edited'])
    expected = copy.deepcopy(docs['sound-edited']); before_graph = graph(expected); after_graph = graph(docs['effect-added'])
    added_nodes = [n for n in after_graph['addedNodes'] if n not in before_graph['addedNodes']]
    assert len(added_nodes) == 1; effect = added_nodes[0]; eid = effect['id']
    assert effect['content'] == {'effect':{'_0':dict(kind='reverb',amount=0.5,secondary=0.3,renderVersion=2)}}
    assert effect['gain'] == 1 and not effect['muted']
    before_graph['addedNodes'].append(effect)
    edge = next(e for e in before_graph['addedEdges'] if e['from'] == 'instrument:'+TRACK and e['to'] == 'mix:'+TRACK)
    edge['from'] = eid
    new_edges = [e for e in after_graph['addedEdges'] if e not in before_graph['addedEdges']]
    assert len(new_edges) == 1 and {k:v for k,v in new_edges[0].items() if k != 'id'} == dict(gain=1,sidechain=False,signal='audio',**{'from':'instrument:'+TRACK,'to':eid})
    before_graph['addedEdges'].extend(new_edges)
    before_graph['layout']['positions'][eid] = dict(x=130,y=360)
    assert music(expected) == music(docs['effect-added'])
    job = read('bounce-observed-state')['job']; assert job['kind'] == 'bounce' and job['state'] == 'completed'
    bounced = docs['bounced']; node = next(n for n in graph(bounced)['addedNodes'] if n['id'] == job['nodeID'])
    assert node['id'] == 'AEE0A3F7-7BB2-4EC7-8CEA-13F0634B87EE'
    lane = next(l for l in use(bounced)['addedLanes'] if l['id'] == node['content']['audio']['laneID'])
    assert lane['trackID'] == TRACK and len(lane['audio']) == 1 and not lane['notes']
    clip = lane['audio'][0]; assert clip['id'] == node['content']['audio']['clipID']
    assert clip['assetID'] == '9C1F0FA8-CBC6-4940-B32E-6B975DBDB47E'
    assert abs(clip['duration'] - job['renderedSeconds']) < 1e-10
    assert node['bounce']['sourceRevision'] == 21 and node['bounce']['bodySeconds'] == 32
    expected = copy.deepcopy(bounced)
    graph(expected)['addedNodes'].remove(node)
    graph(expected)['layout']['positions'].pop(node['id'])
    output_edges = [e for e in graph(expected)['addedEdges'] if e['from'] == node['id']]
    assert len(output_edges) == 1 and output_edges[0]['to'] == 'output:'+TRACK
    graph(expected)['addedEdges'].remove(output_edges[0]); graph(expected)['addedEdges'].extend(node['bounce']['replacedInputs'])
    use(expected)['addedLanes'].remove(lane); expected['assets'] = [a for a in expected['assets'] if a['id'] != clip['assetID']]
    # Edge order is restored to the original insertion slot by the app's Undo.
    graph(expected)['addedEdges'].sort(key=lambda e: [x['id'] for x in graph(docs['effect-added'])['addedEdges']].index(e['id']))
    assert music(expected) == music(docs['effect-added'])
    restored = copy.deepcopy(bounced); n = next(n for n in graph(restored)['addedNodes'] if n['id'] == node['id'])
    n.pop('bounce'); n['muted'] = True
    graph(restored)['addedEdges'].remove(output_edges[0]); graph(restored)['addedEdges'].extend(node['bounce']['replacedInputs'])
    assert music(restored) == music(docs['source-restored'])
    assert bounced['assets'] == docs['source-restored']['assets']
    assert music(docs['bounce-undone']) == music(docs['effect-added'])
    assert music(docs['all-undone']) == music(docs['before']) == music(docs['reopened'])
    assert docs['all-undone'] == docs['reopened'] == json.loads((p.FIXTURE / 'manifest.json').read_text())
    frames, a = pcm(D / 'before-bounce.wav'); frames2, b = pcm(D / 'after-bounce.wav')
    assert frames == frames2 and abs(frames/48000 - job['renderedSeconds']) < 1/48000
    max_diff = peak = 0
    for offset in range(0,len(a),3):
        x = int.from_bytes(a[offset:offset+3],'little',signed=True); y = int.from_bytes(b[offset:offset+3],'little',signed=True)
        max_diff = max(max_diff,abs(x-y)); peak = max(peak,abs(x),abs(y))
    assert max_diff <= 4 and 0 < peak < 8388608
    assert (D / 'before-bounce.wav').read_bytes() == (D / 'source-restored.wav').read_bytes()
    print(json.dumps(dict(status='PASS', snapshots=len(docs), revisions=REVISIONS, frames=frames,
        sampleRate=48000,bitDepth=24,maxDifferenceLSB=max_diff,signalPeak=peak/8388608,
        restoredWAVByteExact=True,physicalAudioAttempts=0,retiredAfterUndoAssetIDs=sorted(retired_assets),archivedBounceAssetSHA256=p.digest(D / 'bounced-asset.wav'),scope='CPU offline fixture semantics and exported PCM; historical asset retired from fixture after Undo/save; preserved original archive checksum verified; no physical-playback claim')))


if __name__ == '__main__': main()
