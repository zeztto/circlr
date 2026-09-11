#!/usr/bin/env python3
"""Check audio-scope baseline preservation; final candidate evidence is pending."""
import copy
import hashlib
import json
import math
from pathlib import Path
import wave

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'qa/generated/audio-scope'


def load(name):
    return json.loads((OUT / (name + '.json')).read_text())


def music(value):
    value = copy.deepcopy(value)
    value.pop('musicRevision', None)
    value.pop('hierarchyView', None)
    colors = value.get('circleColors')
    if colors is not None:
        assert len(colors) % 2 == 0
        value['circleColors'] = {json.dumps(colors[i], sort_keys=True): colors[i+1] for i in range(0, len(colors), 2)}
        assert len(value['circleColors']) * 2 == len(colors)
    return value


def target_use(project, scenario):
    arrangement = next(a for a in project['arrangements'] if a['id'] == scenario['arrangementID'])
    return next(u for u in arrangement['uses'] if u['id'] == scenario['useID'])


def main():
    names = ['baseline/' + n for n in ['before', 'duplicated', 'empty', 'shared-source']]
    captures = {n: load(n) for n in names}; scenario = load('scenario'); package = load('baseline/package')
    manifest = lambda n: captures[n]['manifest']
    for name, capture in captures.items():
        s = capture['state']; project = capture['manifest']
        assert s['projectID'] == package['projectID'] == project['id']
        assert s['runtime']['build'] == '85' and s['runtime']['bundleID'] == 'com.circlr.integrationqa'
        assert s['revision'] == project['musicRevision'] and not s['dirty']
        assert s['output']['attempts'] == s['audition']['attempts'] == 0
        assert not s['playback']['playing']
        assert not any(s['recording'][k] for k in ['audio', 'midi', 'busy'])
        expected = music(manifest('baseline/before'))
        use = target_use(expected, scenario)
        use.clear(); use.update(copy.deepcopy(target_use(project, scenario)))
        assert expected == music(project), name
    for name in ['empty', 'shared-source']:
        assert music(manifest('baseline/duplicated')) == music(manifest('baseline/' + name))
    duplicated = manifest('baseline/duplicated'); use = target_use(duplicated, scenario)
    node = next(n for n in use['graphEdits']['addedNodes'] if n['id'] == scenario['copyNodeID'])
    audio = node['content']['audio']
    assert any(c['id'] == audio['clipID'] for c in use['laneOverrides'][audio['laneID']]['audio'])
    section = next(s for s in duplicated['sections'] if s['id'] == use['sectionID'])
    assert not any(c['id'] == audio['clipID'] for lane in section['lanes'] for c in lane['audio'])
    assert not any(n['id'] == scenario['copyNodeID'] for n in section['graph']['nodes'])
    empty = manifest('baseline/empty')['hierarchyView']['workspace']
    assert empty['original'] and 'audioClipID' not in empty['selection']
    assert captures['baseline/empty']['state']['selection']['music']['nodeID'] == scenario['copyNodeID']
    assert '오디오 파형 편집기' not in (OUT / 'baseline/empty.ax.txt').read_text()
    assert '오디오 파형 편집기' in (OUT / 'baseline/shared-source.ax.txt').read_text()
    assert manifest('baseline/shared-source')['hierarchyView']['workspace']['original']

    final_names = ['before', 'shared-trim', 'shared-undo', 'use-scope', 'use-trim', 'use-undo',
                   'copy-use', 'recovery', 'help-return', 'return-noop', 'click-recovered']
    final = {n: load('final/' + n) for n in final_names}
    for name, capture in final.items():
        s = capture['state']
        assert s['projectID'] == package['projectID'] and s['runtime']['build'] == '86'
        assert s['revision'] == capture['manifest']['musicRevision'] and not s['dirty']
        assert s['output']['attempts'] == s['audition']['attempts'] == 0
        assert not s['playback']['playing'] and not any(s['recording'][k] for k in ['audio', 'midi', 'busy'])
    assert music(final['before']['manifest']) == music(manifest('baseline/shared-source'))
    source_node = next(n for n in section['graph']['nodes'] if n['id'] == scenario['sourceNodeID'])
    source_audio = source_node['content']['audio']
    def original_clip(project):
        owner = next(s for s in project['sections'] if s['id'] == use['sectionID'])
        lane = next(l for l in owner['lanes'] if l['id'] == source_audio['laneID'])
        return next(c for c in lane['audio'] if c['id'] == source_audio['clipID'])
    expected = music(final['before']['manifest'])
    clip = original_clip(expected); clip['sourceStart'] = .1; clip['duration'] = 31.9
    assert expected == music(final['shared-trim']['manifest'])
    assert music(final['shared-undo']['manifest']) == music(final['before']['manifest'])
    assert music(final['use-scope']['manifest']) == music(final['shared-undo']['manifest'])
    expected = music(final['use-scope']['manifest'])
    lane = target_use(expected, scenario)['laneOverrides'][source_audio['laneID']]
    clip = next(c for c in lane['audio'] if c['id'] == source_audio['clipID'])
    clip['sourceStart'] = .2; clip['duration'] = 31.8
    assert expected == music(final['use-trim']['manifest'])
    for name in ['use-undo', 'copy-use', 'recovery', 'help-return', 'return-noop', 'click-recovered']:
        assert music(final[name]['manifest']) == music(final['use-scope']['manifest']), name
    for name in ['recovery', 'help-return', 'return-noop']:
        assert final[name]['manifest']['hierarchyView']['workspace']['original']
        assert final[name]['state']['selection']['music']['nodeID'] == scenario['copyNodeID']
    assert not final['click-recovered']['manifest']['hierarchyView']['workspace']['original']
    assert final['click-recovered']['state']['selection']['music']['nodeID'] == scenario['copyNodeID']
    assert '오디오 공유 원본 편집' in (OUT / 'final/shared-source.ax.txt').read_text()
    assert '공유 원본에는 없습니다' in (OUT / 'final/recovery.ax.txt').read_text()
    assert 'button (disabled) Description: 이번 사용 편집' in (OUT / 'final/help-return.ax.txt').read_text()

    keyboard_names = ['before', 'recovery', 'return-recovered', 'help-return', 'before-mute', 'muted',
                      'bounced', 'bounce-recovered', 'restored', 'restore-undo', 'bounce-undo', 'mute-undo', 'reopened']
    keyboard = {n: load('keyboard/' + n) for n in keyboard_names}
    km = lambda n: keyboard[n]['manifest']
    kp = load('keyboard/package')
    assert '6902AC6C-552F-30C6-9B8F-C18DF5AC7B29' in kp['uuid']
    for name, capture in keyboard.items():
        s = capture['state']
        assert s['projectID'] == package['projectID'] and s['runtime']['build'] == '86'
        assert s['revision'] == capture['manifest']['musicRevision'] and not s['dirty']
        assert s['output']['attempts'] == s['audition']['attempts'] == 0
        assert not s['playback']['playing'] and not any(s['recording'][k] for k in ['audio', 'midi', 'busy'])
    for name in ['before', 'recovery', 'return-recovered', 'help-return', 'before-mute']:
        assert music(km(name)) == music(final['click-recovered']['manifest']), name
    assert km('recovery')['hierarchyView']['workspace']['original']
    assert not km('return-recovered')['hierarchyView']['workspace']['original']
    assert km('help-return')['hierarchyView']['workspace']['original']
    assert keyboard['recovery']['state']['selection'] == keyboard['return-recovered']['state']['selection']
    assert '오디오 파형 편집기' in (OUT / 'keyboard/return-recovered.ax.txt').read_text()
    assert 'button (disabled) Description: 이번 사용 편집' in (OUT / 'keyboard/help-return.ax.txt').read_text()

    report = load('keyboard/bounce-pcm')
    job = keyboard['bounced']['state']['job']
    assert job['kind'] == 'bounce' and job['state'] == 'completed'
    assert job['id'] == report['job']['id']
    bounce_use = target_use(km('bounced'), scenario)
    bounce_node = next(n for n in bounce_use['graphEdits']['addedNodes'] if n['id'] == job['nodeID'])
    output_id = bounce_node['bounce']['outputNodeID']
    expected = music(km('before-mute'))
    output = copy.deepcopy(next(n for n in section['graph']['nodes'] if n['id'] == output_id))
    output['muted'] = True
    target_use(expected, scenario)['graphEdits']['nodeOverrides'][output_id] = output
    assert expected == music(km('muted'))
    assert bounce_use['graphEdits']['nodeOverrides'][output_id] == output
    assert len(km('bounced')['assets']) == 3 and km('bounced')['assets'][:2] == duplicated['assets']
    asset = km('bounced')['assets'][-1]
    lane = next(l for l in bounce_use['addedLanes'] if l['id'] == bounce_node['content']['audio']['laneID'])
    assert len(lane['audio']) == 1 and lane['audio'][0]['assetID'] == asset['id']
    assert lane['audio'][0]['id'] == bounce_node['content']['audio']['clipID']
    assert lane['audio'][0]['duration'] == 34 and lane['audio'][0]['preservesTail']
    assert bounce_node['bounce']['sourceRevision'] == keyboard['muted']['state']['revision']
    assert bounce_node['bounce']['bodySeconds'] == 32 and bounce_node['bounce']['tailSeconds'] == 2
    replaced = bounce_node['bounce']['replacedInputs']; assert len(replaced) == 1
    assert replaced[0] in section['graph']['edges'] and replaced[0]['to'] == output_id
    edge = next(e for e in bounce_use['graphEdits']['addedEdges'] if e['from'] == bounce_node['id'])
    assert edge['to'] == output_id and edge['signal'] == 'audio' and not edge['sidechain']
    expected = music(km('muted')); expected['assets'].append(copy.deepcopy(asset))
    eu = target_use(expected, scenario); eu['addedLanes'].append(copy.deepcopy(lane))
    ed = eu['graphEdits']; ed['addedNodes'].append(copy.deepcopy(bounce_node)); ed['addedEdges'].append(copy.deepcopy(edge))
    ed['removedEdgeIDs'].append(replaced[0]['id'])
    ed['layout']['positions'][bounce_node['id']] = copy.deepcopy(bounce_use['graphEdits']['layout']['positions'][bounce_node['id']])
    assert expected == music(km('bounced'))  # Exact render delta; other uses/source music unchanged.
    assert music(km('bounced')) == music(km('bounce-recovered'))
    assert km('bounced')['hierarchyView']['workspace']['original']
    assert not km('bounce-recovered')['hierarchyView']['workspace']['original']
    assert '오디오 파형 편집기' in (OUT / 'keyboard/bounce-recovered.ax.txt').read_text()
    assert '원본 복원' in (OUT / 'keyboard/bounce-recovered.ax.txt').read_text()
    expected = music(km('bounce-recovered')); ed = target_use(expected, scenario)['graphEdits']
    node = next(n for n in ed['addedNodes'] if n['id'] == bounce_node['id'])
    node.pop('bounce'); node['muted'] = True
    ed['addedEdges'].remove(edge); ed['removedEdgeIDs'].remove(replaced[0]['id'])
    assert expected == music(km('restored'))
    for left, right in [('restore-undo', 'bounce-recovered'), ('bounce-undo', 'muted'), ('mute-undo', 'before-mute')]:
        assert music(km(left)) == music(km(right)), (left, right)
    assert km('mute-undo') == km('reopened')

    fixture = Path(package['fixture']); source = fixture.with_name('studio.circlr')
    digest = hashlib.sha256((source / 'manifest.json').read_bytes()).hexdigest()
    assert digest == package['sourceSHA256'] == '12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d'
    assets = duplicated['assets']; assert len(assets) == 2
    for asset in assets:
        for folder in [fixture, source]:
            assert hashlib.sha256((folder / asset['path']).read_bytes()).hexdigest() == asset['checksum']
    rendered_asset = km('bounced')['assets'][-1]
    # Save/Undo prunes unreferenced fixture media. Preserve the render from Bounces
    # under QA evidence and bind it to the manifest's checksum before decoding.
    rendered_path = OUT / 'keyboard/bounced.wav'
    assert hashlib.sha256(rendered_path.read_bytes()).hexdigest() == rendered_asset['checksum'] == report['checksum']
    total_square = 0; peak = 0; sample_count = 0
    with wave.open(str(rendered_path), 'rb') as audio:
        assert (audio.getnchannels(), audio.getsampwidth(), audio.getframerate(), audio.getnframes()) == (2, 3, 48000, 1632000)
        while data := audio.readframes(8192):
            for offset in range(0, len(data), 3):
                sample = int.from_bytes(data[offset:offset+3], 'little', signed=True)
                peak = max(peak, abs(sample)); total_square += sample * sample; sample_count += 1
    peak /= 8388608
    rms = math.sqrt(total_square / sample_count) / 8388608
    assert peak > 0 and rms > 0
    assert math.isclose(peak, report['peak'], abs_tol=1e-12) and math.isclose(rms, report['rms'], abs_tol=1e-12)
    print(json.dumps({'status': 'passed', 'nativeSnapshots': len(names) + len(final_names) + len(keyboard_names), 'baselineRegressionReproduced': True,
                      'preservedAssets': 2, 'physicalAudioAttempts': 0,
                      'offlineBounceRenders': 1, 'bouncePeak': peak, 'bounceRMS': rms,
                      'finalPackageUUID': kp['uuid']}, ensure_ascii=False))


if __name__ == '__main__':
    main()
