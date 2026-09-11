#!/usr/bin/env python3
"""Inspect captured render-tail documents and WAV bytes; never renders or plays."""
import copy
import hashlib
import json
import math
from pathlib import Path
import wave

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'qa/generated/render-tail'


def load(name):
    return json.loads((OUT / (name + '.json')).read_text())


def music(value):
    value = copy.deepcopy(value)
    value.pop('musicRevision', None); value.pop('hierarchyView', None)
    colors = value.get('circleColors')
    if colors is not None:
        assert len(colors) % 2 == 0
        value['circleColors'] = {json.dumps(colors[i], sort_keys=True): colors[i+1] for i in range(0, len(colors), 2)}
        assert len(value['circleColors']) * 2 == len(colors)
    return value


def pcm(path):
    square = count = peak = end_peak = short_peak = short_square = short_count = 0
    with wave.open(str(path), 'rb') as f:
        assert (f.getnchannels(), f.getsampwidth(), f.getframerate()) == (2, 3, 48000)
        frames = f.getnframes(); end_sample = max(0, frames - 48000) * 2
        short_sample = max(0, frames - 4800) * 2
        while data := f.readframes(8192):
            for offset in range(0, len(data), 3):
                v = int.from_bytes(data[offset:offset+3], 'little', signed=True)
                peak = max(peak, abs(v)); square += v * v
                if count >= end_sample: end_peak = max(end_peak, abs(v))
                if count >= short_sample:
                    short_peak = max(short_peak, abs(v)); short_square += v * v; short_count += 1
                count += 1
    assert count == frames * 2
    return {'frames': frames, 'duration': frames / 48000, 'peak': peak / 8388608,
            'rms': math.sqrt(square / count) / 8388608, 'lastSecondPeak': end_peak / 8388608,
            'endWindowPeak': short_peak / 8388608, 'endWindowRMS': math.sqrt(short_square / short_count) / 8388608}


def main():
    names = ['before', 'delay-ready', 'fixed-bounce', 'delay-restored']
    captures = {n: load('baseline/' + n) for n in names}; package = load('baseline/package')
    m = lambda n: captures[n]['manifest']
    for name, capture in captures.items():
        s = capture['state']
        assert s['projectID'] == package['projectID'] == capture['manifest']['id']
        assert s['runtime']['build'] == '86' and s['runtime']['bundleID'] == 'com.circlr.integrationqa'
        assert s['revision'] == capture['manifest']['musicRevision'] and not s['dirty']
        assert s['output']['attempts'] == s['audition']['attempts'] == 0
        assert not s['playback']['playing'] and not any(s['recording'][k] for k in ['audio', 'midi', 'busy'])
        expected = music(m('before'))
        expected['arrangements'][0]['uses'][0] = copy.deepcopy(capture['manifest']['arrangements'][0]['uses'][0])
        if name == 'fixed-bounce': expected['assets'] = copy.deepcopy(capture['manifest']['assets'])
        assert expected == music(capture['manifest']), name
    assert music(m('delay-ready')) == music(m('delay-restored'))
    original = m('before')['arrangements'][0]['uses'][0]['graphEdits']
    delay = m('delay-ready')['arrangements'][0]['uses'][0]['graphEdits']
    added = [n for n in delay['addedNodes'] if n not in original['addedNodes']]
    assert len(added) == 1
    assert added[0]['content']['effect']['_0'] == {'amount': 1, 'kind': 'delay', 'secondary': .8}
    job = captures['fixed-bounce']['state']['job']
    assert job['kind'] == 'bounce' and job['state'] == 'completed'
    u = m('fixed-bounce')['arrangements'][0]['uses'][0]
    node = next(n for n in u['graphEdits']['addedNodes'] if n['id'] == job['nodeID'])
    assert node['bounce']['bodySeconds'] == 32 and node['bounce']['tailSeconds'] == 2
    assert node['bounce']['sourceRevision'] == captures['delay-ready']['state']['revision']
    assert len(m('fixed-bounce')['assets']) == 3
    assert m('fixed-bounce')['assets'][:2] == m('before')['assets']
    rendered = m('fixed-bounce')['assets'][-1]
    assert hashlib.sha256((OUT / 'baseline/fixed-bounce.wav').read_bytes()).hexdigest() == rendered['checksum'] == '0b82e9a4713e5ffea1dda798194108a784be1f4a4a0559b62571a4b5eda39401'
    observed = pcm(OUT / 'baseline/fixed-bounce.wav')
    assert observed['duration'] == rendered['duration'] == 34
    assert observed['peak'] > 0 and observed['lastSecondPeak'] > 0
    fixture = Path(package['fixture']); source = fixture.with_name('studio.circlr')
    assert hashlib.sha256((source / 'manifest.json').read_bytes()).hexdigest() == package['sourceSHA256'] == '12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d'
    assert len(m('before')['assets']) == 2
    for asset in m('before')['assets']:
        for folder in [fixture, source]:
            assert hashlib.sha256((folder / asset['path']).read_bytes()).hexdigest() == asset['checksum']

    final_names = ['opened', 'manual-set', 'auto-bounce', 'bounced-export', 'auto-undone',
                   'manual-bounce', 'manual-export', 'manual-undone', 'cap-effects', 'cancel-before', 'cap-render-rejected']
    final_names += ['cancel-settled', 'cancel-preserved', 'cap-undone', 'reopen-ready', 'reopened', 'reopened-export', 'final']
    captures_final = {n: load('final/' + n) for n in final_names}
    fm = lambda n: captures_final[n]['manifest']
    for name, capture in captures_final.items():
        s = capture['state']
        assert s['projectID'] == package['projectID'] and s['runtime']['build'] == '87'
        assert s['revision'] == capture['manifest']['musicRevision'] and not s['dirty']
        assert s['output']['attempts'] == s['audition']['attempts'] == 0
        assert not s['playback']['playing'] and not any(s['recording'][k] for k in ['audio', 'midi', 'busy'])
        expected = music(m('delay-restored'))
        expected['arrangements'][0]['uses'][0] = copy.deepcopy(capture['manifest']['arrangements'][0]['uses'][0])
        expected['assets'] = copy.deepcopy(capture['manifest']['assets'])
        assert expected == music(capture['manifest']), name
    for name in ['opened', 'manual-set', 'auto-undone', 'manual-undone']:
        assert music(fm(name)) == music(m('delay-restored')), name
    assert music(fm('auto-bounce')) == music(fm('bounced-export'))
    assert music(fm('manual-bounce')) == music(fm('manual-export'))
    results = {}
    for name, seconds, tail, signal in [('auto-bounce', 74, 42, False), ('manual-bounce', 34, 2, True),
                                       ('bounced-export', 74, 42, False), ('manual-export', 34, 2, True)]:
        job = captures_final[name]['state']['job']
        assert job['state'] == 'completed' and job['renderedSeconds'] == seconds
        assert job['tail']['effectiveSeconds'] == tail and job['endWindowHasSignal'] == signal
        assert job['endWindowSeconds'] == .1
        result = pcm(OUT / ('final/' + name + '.wav')); results[name] = result
        assert result['duration'] == seconds
        # Export uses 24-bit quantization; job diagnostics are pre-quantization Float.
        for key in ['endWindowPeak', 'endWindowRMS']:
            assert abs(result[key] - job[key]) <= 2 / 8388608, (name, key)
        if 'bounce' in name and name != 'bounced-export':
            project = fm(name); use = project['arrangements'][0]['uses'][0]
            node = next(n for n in use['graphEdits']['addedNodes'] if n['id'] == job['nodeID'])
            assert node['bounce']['bodySeconds'] == 32 and node['bounce']['tailSeconds'] == tail
            assert project['assets'][:2] == m('before')['assets'] and len(project['assets']) == 3
            asset = project['assets'][-1]
            assert hashlib.sha256((OUT / ('final/' + name + '.wav')).read_bytes()).hexdigest() == asset['checksum']
            expected = music(fm('opened')); eu = expected['arrangements'][0]['uses'][0]
            lane = next(l for l in use['addedLanes'] if l['id'] == node['content']['audio']['laneID'])
            assert lane['audio'][0]['assetID'] == asset['id'] and lane['audio'][0]['duration'] == seconds
            edge = next(e for e in use['graphEdits']['addedEdges'] if e['from'] == node['id'])
            assert edge['to'] == node['bounce']['outputNodeID']
            replaced = node['bounce']['replacedInputs']; assert len(replaced) == 1
            expected['assets'].append(copy.deepcopy(asset)); eu['addedLanes'].append(copy.deepcopy(lane))
            ed = eu['graphEdits']; ed['addedNodes'].append(copy.deepcopy(node)); ed['addedEdges'].append(copy.deepcopy(edge))
            ed['removedEdgeIDs'].append(replaced[0]['id'])
            ed['layout']['positions'][node['id']] = copy.deepcopy(use['graphEdits']['layout']['positions'][node['id']])
            assert expected == music(project), name
    with wave.open(str(OUT / 'baseline/fixed-bounce.wav'), 'rb') as f:
        fixed_pcm = f.readframes(f.getnframes())
    for name in ['auto-bounce', 'manual-bounce']:
        with wave.open(str(OUT / ('final/' + name + '.wav')), 'rb') as f:
            assert f.readframes(34 * 48000) == fixed_pcm
    invalid = load('final/native-invalid')
    assert invalid['reply']['ok'] is False and '0–120' in invalid['reply']['error']
    before_invalid = copy.deepcopy(invalid['before']); after_invalid = copy.deepcopy(invalid['after'])
    before_invalid.pop('sequence'); after_invalid.pop('sequence'); assert before_invalid == after_invalid
    assert music(fm('cap-effects')) == music(fm('cancel-before')) == music(fm('cap-render-rejected'))
    rejected = captures_final['cap-render-rejected']['state']['job']
    assert rejected['state'] == 'failed' and '0 dBFS' in rejected['message']
    assert rejected['tail']['estimatedSeconds'] > 120 and rejected['tail']['effectiveSeconds'] == 120
    assert len(fm('cap-render-rejected')['assets']) == 2
    cancelled = load('final/cancel-job')
    assert cancelled['started']['state'] == cancelled['running']['job']['state'] == 'running'
    assert cancelled['after']['job']['state'] == 'cancelled'
    assert cancelled['started']['jobID'] == cancelled['running']['job']['id'] == cancelled['after']['job']['id']
    for key in ['revision', 'assets', 'arrangements', 'selection']:
        assert cancelled['before'][key] == cancelled['after'][key]
    assert '직접 지정한 길이가 자동 추정보다 짧아' in (OUT / 'final/manual-set.ax.txt').read_text()
    assert '120초 한도를 넘었습니다' in (OUT / 'final/cap-ready.ax.txt').read_text()
    for name in ['cancel-settled', 'cancel-preserved']:
        assert music(fm(name)) == music(fm('cap-effects'))
        assert captures_final[name]['state']['revision'] == cancelled['after']['revision']
        assert captures_final[name]['state']['job'] == cancelled['after']['job']
    assert music(fm('cap-undone')) == music(fm('opened'))
    for name in ['reopened', 'reopened-export', 'final']:
        assert music(fm(name)) == music(fm('reopen-ready'))
        assert fm(name)['musicRevision'] == fm('reopen-ready')['musicRevision']
    assert fm('reopen-ready') == fm('reopened')
    for left, right in [('auto-bounce.wav', 'reopened-bounce.wav'), ('bounced-export.wav', 'reopened-export.wav')]:
        assert (OUT / 'final' / left).read_bytes() == (OUT / 'final' / right).read_bytes()
    ready = fm('reopen-ready'); asset = ready['assets'][-1]
    assert len(ready['assets']) == 3 and ready['assets'][:2] == m('before')['assets']
    assert hashlib.sha256((OUT / 'final/reopened-bounce.wav').read_bytes()).hexdigest() == asset['checksum']
    ready_job = captures_final['reopen-ready']['state']['job']
    node = next(n for n in ready['arrangements'][0]['uses'][0]['graphEdits']['addedNodes'] if n['id'] == ready_job['nodeID'])
    assert node['bounce']['tailSeconds'] == 42 and node['bounce']['bodySeconds'] == 32
    # Second auto bounce differs only by generated identities/source revision.
    old = music(fm('auto-bounce')); new = music(ready)
    old_use = old['arrangements'][0]['uses'][0]; new_use = new['arrangements'][0]['uses'][0]
    old_node = next(n for n in old_use['graphEdits']['addedNodes'] if 'bounce' in n)
    old_lane = next(l for l in old_use['addedLanes'] if l['id'] == old_node['content']['audio']['laneID'])
    new_lane = next(l for l in new_use['addedLanes'] if l['id'] == node['content']['audio']['laneID'])
    old_edge = next(e for e in old_use['graphEdits']['addedEdges'] if e['from'] == old_node['id'])
    new_edge = next(e for e in new_use['graphEdits']['addedEdges'] if e['from'] == node['id'])
    identities = {old['assets'][-1]['id']: asset['id'], old_node['id']: node['id'], old_lane['id']: new_lane['id'],
                  old_lane['audio'][0]['id']: new_lane['audio'][0]['id'], old_edge['id']: new_edge['id']}
    serialized = json.dumps(old, sort_keys=True)
    for previous, replacement in identities.items(): serialized = serialized.replace(previous, replacement)
    remapped = json.loads(serialized)
    next(n for n in remapped['arrangements'][0]['uses'][0]['graphEdits']['addedNodes'] if 'bounce' in n)['bounce']['sourceRevision'] = node['bounce']['sourceRevision']
    assert remapped == new
    assert music(json.loads((fixture / 'manifest.json').read_text())) == music(fm('final'))
    assert hashlib.sha256((fixture / asset['path']).read_bytes()).hexdigest() == asset['checksum']
    print(json.dumps({'status': 'passed', 'baselineSnapshots': len(names), 'finalSnapshots': len(final_names),
                      'baselinePCM': observed, 'finalPCM': results,
                      'preservedAssets': 2, 'physicalAudioAttempts': 0,
                      'successfulOfflineRenders': 7, 'cancelledJobs': 1, 'rejectedPeakJobs': 1}, ensure_ascii=False))


if __name__ == '__main__':
    main()
