#!/usr/bin/env python3
"""R30-01 QA only: deterministic authored song; no seeds, downloads, apps, or I/O playback."""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import struct
import wave

ROOT = Path(__file__).resolve().parent.parent
DEFAULT = ROOT / 'qa/generated/r30/release030.circlr'


def identity(name):
    return 'R30-' + name


def settings():
    return {k: {'source': 'inherit'} for k in ('tempo', 'scale', 'meter', 'beatGrid', 'rhythm')}


def layout(positions=None):
    return dict(positions=positions or {}, groups=[], pan=dict(x=100, y=150), zoom=1,
                grid=True, snap=True, spacing=24)


def note(name, beat, pitch, length=0.5, velocity=80):
    return dict(id=identity(name), beat=beat, length=length, pitch=pitch, velocity=velocity)


def circle(name, content):
    return dict(id=identity(name), name=name, content=content, settings=settings(),
                startBeat=0, repeatCount=1, gain=1, muted=False)


def edge(name, source, target, signal='audio'):
    return dict(id=identity(name), **{'from': source}, to=target, signal=signal, gain=1, sidechain=False)


def create(target):
    # Deliberately refuse overwrite, including a prior edited fixture.
    target.mkdir(parents=True, exist_ok=False)
    (target / 'media').mkdir()
    audio = target / 'media/R30-asset.wav'
    # Integer triangle arpeggio: 4 seconds / stereo PCM16 / 48 kHz.
    # Integer-only synthesis makes byte hashes independent of libm/platform trig.
    with wave.open(str(audio), 'wb') as wav:
        wav.setparams((2, 2, 48000, 0, 'NONE', 'not compressed'))
        data = bytearray()
        for frame in range(192000):
            pulse, local = divmod(frame, 24000)
            period = (436, 346, 291, 218)[pulse % 4]
            phase = frame % period
            triangle = 4 * abs(phase * 2 - period) - 2 * period
            envelope = min(local, 480, 24000 - local)
            value = triangle * 1100 * envelope // (period * 480)
            data.extend(struct.pack('<hh', value, value * 3 // 4))
        wav.writeframes(data)
    asset_hash = hashlib.sha256(audio.read_bytes()).hexdigest()
    drums = dict(id=identity('track-drums'), name='드럼', instrument=dict(kind='soundBank', program=0, drums=True), gain=0.45, muted=False)
    synth = dict(id=identity('track-synth'), name='신스', instrument=dict(kind='synthesizer', program=0, drums=False), gain=0.35, muted=False)
    audio_track = dict(id=identity('track-audio'), name='직접 작성 오디오', instrument=dict(kind='synthesizer', program=0, drums=False), gain=0.5, muted=False)
    tracks = [drums, synth, audio_track]
    pattern = dict(id=identity('shared-drums'), name='공유 드럼', length=8,
                   meter=dict(numerator=4, denominator=4), trackID=drums['id'], audio=[],
                   notes=[note(f'shared-note-{i}', i, 36 if i % 2 == 0 else 38, 0.25, 88) for i in range(8)])
    sections, uses = [], []
    for index, name in enumerate(('Intro', 'Verse', 'Chorus')):
        lanes = [dict(id=identity(f'{name}-lane-{kind}'), trackID=track['id'], notes=[], audio=[])
                 for kind, track in zip(('drums', 'synth', 'audio'), tracks)]
        if index == 0:
            lanes[0]['notes'] = [note(f'{name}-drum-{i}', i, 36 if i % 2 == 0 else 38, 0.25, 80) for i in range(8)]
        lanes[1]['notes'] = [note(f'{name}-synth-{i}', 2 * i, (48, 51, 55, 58)[i] + (12 if index == 2 else 0), 1.5) for i in range(4)]
        clip = dict(id=identity(f'{name}-clip'), assetID=identity('asset'), beat=0, duration=4,
                    sourceStart=0, sourceBPM=120, followsTempo=False, gain=1, fadeIn=0.01, fadeOut=0.02, preservesTail=False)
        lanes[2]['audio'] = [clip]
        nodes, edges, positions = [], [], {}
        for row, kind in enumerate(('drums', 'synth', 'audio')):
            track, lane = tracks[row], lanes[row]
            if kind == 'audio':
                source = circle(f'{name}-{kind}-source', {'audio': dict(laneID=lane['id'], clipID=clip['id'])})
            elif kind == 'drums' and index > 0:
                source = circle(f'{name}-{kind}-source', {'rhythmMIDI': dict(trackID=track['id'])})
                source['settings']['rhythm'] = dict(source='local', value=dict(patternID=pattern['id']))
            else:
                source = circle(f'{name}-{kind}-source', {'midi': dict(laneID=lane['id'])})
            nodes.append(source)
            previous = source
            if kind != 'audio':
                instrument = circle(f'{name}-{kind}-instrument', {'instrument': dict(trackID=track['id'])})
                if kind == 'synth':
                    instrument['automation'] = [dict(parameter='gain', enabled=True, points=[
                        dict(id=identity(f'{name}-gain-{i}'), beat=beat, value=value, shape='linear')
                        for i, (beat, value) in enumerate(((0, 0.4), (4, 0.8), (8, 0.4)))])]
                nodes.append(instrument)
                edges.append(edge(f'{name}-{kind}-midi-edge', source['id'], instrument['id'], 'midi'))
                previous = instrument
            if kind == 'synth':
                effect = circle(f'{name}-effect', {'effect': {'_0': dict(kind='delay', amount=0.12, secondary=0.15)}})
                nodes.append(effect)
                edges.append(edge(f'{name}-effect-edge', previous['id'], effect['id']))
                previous = effect
            output = circle(f'{name}-{kind}-output', {'output': dict(trackID=track['id'])})
            nodes.append(output)
            edges.append(edge(f'{name}-{kind}-output-edge', previous['id'], output['id']))
            row_nodes = [n for n in nodes if n['id'] not in positions]
            for col, node in enumerate(row_nodes):
                positions[node['id']] = dict(x=col * 220, y=row * 220)
        section = dict(id=identity(f'section-{name}'), name=name, bars=2, settings=settings(),
                       tempoChanges=[], meterChanges=[], lanes=lanes,
                       graph=dict(nodes=nodes, edges=edges, layout=layout(positions)))
        sections.append(section)
        use = dict(id=identity(f'use-{name}'), sectionID=section['id'], name=name, repeatCount=1,
                   isEnd=index == 2, settings=settings(), laneOverrides={}, addedLanes=[], excludedLaneIDs=[], effects=[], gain=1)
        if name == 'Verse':
            variant = copy.deepcopy(lanes[1])
            variant['notes'][0]['pitch'] = 60
            use['laneOverrides'][variant['id']] = variant
        uses.append(use)
    transition = dict(mode='within', anchor='sourceBars', length=0, effect=dict(kind='gain', amount=1, secondary=0.25))
    arrangement = dict(id=identity('arrangement'), name='기준 편곡', uses=uses,
                       edges=[dict(id=identity(f'flow-{i}'), **{'from': uses[i]['id']}, to=uses[i+1]['id'], transition=transition) for i in range(2)],
                       chosenEdges={}, startID=uses[0]['id'], layout=layout({u['id']: dict(x=i*280, y=0) for i, u in enumerate(uses)}))
    master = dict(id=identity('master'), name='출력', kind='master', effect=dict(kind='gain', amount=1, secondary=0.25))
    signal_nodes = [master] + [dict(id=identity('signal-' + str(i)), name=t['name'], kind='source', trackID=t['id'], effect=master['effect']) for i, t in enumerate(tracks)]
    signal_edges = [dict(id=identity('signal-edge-' + str(i)), **{'from': n['id']}, to=master['id'], gain=1, sidechain=False) for i, n in enumerate(signal_nodes[1:])]
    composition = dict(id=identity('composition'), name='0.30 제작 흐름 검증', kind='song', children=[],
                       arrangementIDs=[arrangement['id']], selectedArrangementID=arrangement['id'], settings=settings(), repeatCount=1, layout=layout())
    project = dict(schemaVersion=2, id=identity('project'), name='0.30 제작 흐름 검증', musicRevision=1,
                   global_=None, tracks=tracks, sections=sections, patterns=[pattern], arrangements=[arrangement],
                   activeArrangementID=arrangement['id'], assets=[dict(id=identity('asset'), name='직접 작성 삼각파 아르페지오',
                   path='media/R30-asset.wav', duration=4, sampleRate=48000, checksum=asset_hash)], takes=[],
                   signal=dict(nodes=signal_nodes, edges=signal_edges, layout=layout()),
                   album=dict(id=identity('album'), children=[composition['id']], compositions=[composition], layout=layout()))
    del project['global_']
    project['global'] = dict(tempo=120, scale=dict(root=0, name='minor', intervals=[0,2,3,5,7,8,10]),
                             meter=dict(numerator=4, denominator=4), beatGrid=dict(subdivisions=4, accents=[], swing=0), rhythm={})
    manifest = (json.dumps(project, ensure_ascii=False, sort_keys=True, indent=2) + '\n').encode()
    (target / 'manifest.json').write_bytes(manifest)
    return dict(projectID=project['id'], arrangementID=arrangement['id'], schemaVersion=2,
                sectionIDs=[s['id'] for s in sections], useIDs=[u['id'] for u in uses],
                sectionStartSeconds=[0,4,8], sectionDurationSeconds=4, songDurationSeconds=12,
                totalBeats=24, tempo=120, sourceSynthPitches=[48,51,55,58], verseUseSynthPitches=[60,51,55,58],
                sharedPatternID=pattern['id'], sharedSourceIDs=['R30-Verse-drums-source','R30-Chorus-drums-source'],
                sharedNoteCount=8, originalDrumNoteCount=8, synthNoteCountPerSection=4,
                assetID=identity('asset'), assetFrames=192000, assetChannels=2, assetSampleRate=48000,
                assetSHA256=asset_hash, manifestSHA256=hashlib.sha256(manifest).hexdigest())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=DEFAULT)
    args = parser.parse_args()
    baseline = create(args.output.expanduser().resolve())
    expected = json.loads((ROOT / 'qa/r30-fixture-baseline.json').read_text())
    if baseline != expected:
        raise SystemExit('Fixture differs from checked-in baseline: ' + json.dumps(baseline, sort_keys=True))
    print(json.dumps(dict(status='GENERATED_AND_HASH_VERIFIED', path=str(args.output), baseline=baseline), ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
