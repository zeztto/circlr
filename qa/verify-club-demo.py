#!/usr/bin/env python3
"""Inspect the saved v4 notes, not the generator's intentions."""
import argparse
import importlib.util
import json
from pathlib import Path


def require(test, message):
    if not test: raise ValueError(message)


def verify(project):
    p = json.loads((project / 'manifest.json').read_text())
    require(p['global']['tempo'] == 120, 'Tempo must be 120 BPM')
    require(len(p['tracks']) == 15, 'Expected 15 independent tracks')
    require([s['bars'] for s in p['sections']] == [16,16,8,16,8,16,16], 'DJ phrase map changed')
    synths = [t['instrument']['synth'] for t in p['tracks'][4:14]]
    require({s['voice'] for s in synths} == set(range(10)), 'Expected ten different synth voices')
    require(all(s['engineVersion'] == 3 for s in synths), 'Expected engine 3')
    active, counts = {}, [0]*15
    notes = 0
    for si,section in enumerate(p['sections']):
        lanes = section['lanes']; require(len(lanes) == 15, 'Lane map mismatch')
        for bar in range(section['bars']):
            def hits(index):
                return [round(n['beat']-bar*4,6) for n in lanes[index]['notes'] if bar*4<=n['beat']<(bar+1)*4]
            kick = hits(0); snare = hits(1); hat = hits(2); shaker=hits(3)
            require(kick == ([] if si==4 and bar<6 else [0,1,2,3]), f'Unexpected kick {si}/{bar}: {kick}')
            quiet = (si==0 and bar<4) or (si==6 and bar>=12) or (si==4 and bar<6)
            require(snare == ([] if quiet else [1,3]), f'Unexpected backbeat {si}/{bar}')
            require(hat == ([] if si==4 and bar<6 else [.5,1.5,2.5,3.5]), f'Unexpected hat {si}/{bar}')
            require(shaker in [[],[1.5,3.5]], 'No sixteenth-note shaker rolls')
        active[section['name']] = []
        for i,lane in enumerate(lanes):
            require(lane['trackID'] == p['tracks'][i]['id'], 'Track/lane ownership mismatch')
            if lane['notes'] or lane['audio']: active[section['name']].append(p['tracks'][i]['name'])
            counts[i] += len(lane['notes']); notes += len(lane['notes'])
            for n in lane['notes']:
                require(0<=n['beat']<section['bars']*4 and n['beat']+n['length']<=section['bars']*4+1e-6, 'Note outside section')
                require(1<=n['velocity']<=127, 'Invalid velocity')
                if i<4: require(n['pitch'] == [36,38,42,70][i], 'No tom/roll mapping in drums')
        # Each ducking node must actually receive the kick as sidechain audio.
        graph=section['graph']; effects=[n for n in graph['nodes'] if 'effect' in n['content']]
        compressors=[n for n in effects if n['content']['effect']['_0']['kind']=='compressor']
        require(len(compressors)==4,'Expected four sidechains')
        for node in compressors:
            require(any(e['from']=='instrument:'+p['tracks'][0]['id'] and e['to']==node['id'] and e.get('sidechain') for e in graph['edges']), 'Missing kick sidechain')
    require(all(counts[i]>0 for i in range(14)), 'An instrument is only decorative')
    require(all(not p['sections'][0]['lanes'][i]['notes'] or min(n['beat'] for n in p['sections'][0]['lanes'][i]['notes'])>=32 for i in range(4,14)), 'Intro first eight bars must remain percussion-only')
    require(all(not p['sections'][-1]['lanes'][i]['notes'] or max(n['beat']+n['length'] for n in p['sections'][-1]['lanes'][i]['notes'])<=32 for i in range(4,14)), 'Outro final eight bars must have no harmonic notes')
    return {'tempo':120,'bars':96,'tracks':15,'synthVoices':10,'notes':notes,'kickGrid':'quarter notes; breakdown first 6 bars silent','backbeat':[2,4],'tomHits':0,'snareRolls':0,'notesPerTrack':dict(zip((t['name'] for t in p['tracks']),counts)),'activeTracksBySection':active,'artistListeningReview':'pending'}


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('project',type=Path);parser.add_argument('--output',type=Path);args=parser.parse_args()
    result=verify(args.project);text=json.dumps(result,ensure_ascii=False,indent=2)+'\n'
    if args.output:args.output.write_text(text)
    print(text,end='')
