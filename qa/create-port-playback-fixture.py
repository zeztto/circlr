#!/usr/bin/env python3
"""Create an isolated native playback fixture; does not open apps or start audio."""
import copy
import hashlib
import json
import math
from pathlib import Path
import struct
import uuid
import wave

BASE = Path.home() / 'Library/Application Support/circlr-ports-qa/fixtures'
TARGET = BASE / 'ports-playback.circlr'
SEED = BASE / 'ports-gesture.circlr/manifest.json'


def identity(name):
    return str(uuid.uuid5(uuid.NAMESPACE_URL, 'circlr-ports-playback-c3a/' + name)).upper()


def main():
    assert SEED.is_file() and not TARGET.exists(), 'Preserve previous QA projects'
    project = json.loads(SEED.read_text())
    arrangement = project['arrangements'][0]
    use = copy.deepcopy(next(u for u in arrangement['uses'] if u['id'] == 'D6E3678B-67AB-4765-9E25-BD7A7166573F'))
    section = copy.deepcopy(next(s for s in project['sections'] if s['id'] == use['sectionID']))
    settings = copy.deepcopy(section['settings'])
    layout = copy.deepcopy(section['graph']['layout']); layout['positions'] = {}; layout['groups'] = []
    router = identity('router'); nodes = []; edges = []; lanes = []; assets = []
    tracks = copy.deepcopy(project['tracks'][:2])
    instrument = copy.deepcopy(next(t['instrument'] for t in project['tracks'] if t['instrument']['kind'] == 'synthesizer'))
    (TARGET / 'media').mkdir(parents=True)
    for index, track in enumerate(tracks):
        track.update(id=identity('track' + str(index)), name=f'출력 {index+1}', gain=0.7, muted=False, instrument=instrument)
        source, output, lane, clip, asset = [identity(name + str(index)) for name in ['source', 'output', 'lane', 'clip', 'asset']]
        path = TARGET / 'media' / f'{asset}.wav'
        # Quiet test tones alternate every four seconds, with short click-free ramps.
        with wave.open(str(path), 'wb') as audio:
            audio.setnchannels(2); audio.setsampwidth(2); audio.setframerate(48000)
            block = bytearray()
            for frame in range(32 * 48000):
                time = frame / 48000
                active = int(time / 4) % 2 == index
                phase = time % 4
                gain = min(1, phase / 0.01, (4-phase) / 0.01) * (0.04 if active else 0)
                left = int(32767 * gain * math.sin(2 * math.pi * (220 if index == 0 else 440) * time))
                right = int(left * 0.5)
                block.extend(struct.pack('<hh', left, right))
                if len(block) >= 192000:
                    audio.writeframesraw(block); block.clear()
            if block: audio.writeframesraw(block)
        assets.append(dict(id=asset, name=f'검증 톤 {index+1}', path=f'media/{asset}.wav', duration=32,
                           sampleRate=48000, checksum=hashlib.sha256(path.read_bytes()).hexdigest()))
        lanes.append(dict(id=lane, trackID=track['id'], notes=[], audio=[dict(id=clip, assetID=asset, beat=0,
            duration=32, sourceStart=0, sourceBPM=120, followsTempo=False, gain=1, fadeIn=0, fadeOut=0, preservesTail=True)]))
        common = dict(gain=1, muted=False, startBeat=0, repeatCount=1, settings=settings)
        nodes.append(dict(common, id=source, name=f'검증 톤 {index+1}', content=dict(audio=dict(laneID=lane, clipID=clip))))
        nodes.append(dict(common, id=output, name=f'출력 {index+1}', content=dict(output=dict(trackID=track['id']))))
        y = -200 if index == 0 else 200
        layout['positions'].update({source: dict(x=-360, y=y), output: dict(x=360, y=y)})
        edges += [dict(id=identity('input-edge'+str(index)), **{'from': source}, to=router, signal='audio', sidechain=False,
                       gain=1, fromPortID='out.audio.main', toPortID=f'in.audio.bus{index+1}'),
                  dict(id=identity('output-edge'+str(index)), **{'from': router}, to=output, signal='audio', sidechain=False,
                       gain=1, fromPortID=f'out.audio.bus{index+1}', toPortID='in.audio.main')]
    nodes.append(dict(common, id=router, name='독립 스테레오 출력', content=dict(router={'_0': {'routes': [
        dict(input=f'in.audio.bus{i}', output=f'out.audio.bus{i}', gain=1) for i in [1, 2]]}})))
    layout['positions'][router] = dict(x=0, y=0)
    section.update(id=identity('section'), name='출력별 신호 검증', bars=16, lanes=lanes,
                   graph=dict(nodes=nodes, edges=edges, layout=layout), tempoChanges=[], meterChanges=[])
    use.update(id=identity('use'), sectionID=section['id'], name=section['name'], barsOverride=16,
               addedLanes=[], laneOverrides={}, excludedLaneIDs=[], gain=1, repeatCount=1, isEnd=True)
    use.pop('graphEdits', None); use.pop('graphLayout', None)
    arrangement.update(uses=[use], startID=use['id'], edges=[], chosenEdges={}, name='포트 신호 검증')
    arrangement['layout']['positions'] = {}; arrangement['layout']['groups'] = []
    master = copy.deepcopy(next(n for n in project['signal']['nodes'] if n['kind'] == 'master'))
    project['signal']['nodes'] = [master] + [dict(id=identity('signal'+str(i)), name=t['name'], kind='source',
        trackID=t['id'], effect=copy.deepcopy(master['effect'])) for i, t in enumerate(tracks)]
    project['signal']['edges'] = [dict(id=identity('signal-edge'+str(i)), **{'from': identity('signal'+str(i))}, to=master['id'], gain=1, sidechain=False) for i in range(2)]
    project['signal']['layout']['positions'] = {}; project['signal']['layout']['groups'] = []
    project.update(id=identity('project'), name='포트 신호 검증', musicRevision=1, sections=[section],
                   arrangements=[arrangement], tracks=tracks, assets=assets, patterns=[], takes=[])
    project.pop('portLayout', None); project.pop('hierarchyView', None)
    project['album']['compositions'][0]['name'] = '출력별 신호 검증'
    (TARGET / 'manifest.json').write_text(json.dumps(project, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(dict(path=str(TARGET), projectID=project['id'], arrangementID=arrangement['id'], useID=use['id'], router=router)))


if __name__ == '__main__':
    main()
