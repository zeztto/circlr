#!/usr/bin/env python3
"""Refine the bundled v5 demo without changing identity, layout or DJ rhythm.

Produces a new self-contained project directory and sibling JSON audit report.
Never replaces an existing destination. Final audio measurements remain separate.

Offline reproduction from the preserved release tag (run at repository root):
    mkdir -p music/f0r-h3r/v6-source
    git archive v0.50.1 Resources/Demos/f0r-h3r.circlr | tar -x -C music/f0r-h3r/v6-source
    python3 Tools/refine-demo-v6.py music/f0r-h3r/v6-source/Resources/Demos/f0r-h3r.circlr 'music/f0r-h3r/reproduced-v6/f0r h3r.circlr'

Use new directories; production audio is rendered separately with circlr-studio.
The pinned test fixture is gzip JSON from that same tag, with no audio duplication.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import shutil
import uuid

NAMESPACE = uuid.UUID('cb088052-e185-4af9-97f7-e45f28e03719')


def refine(project):
    p = copy.deepcopy(project)
    if (p['name'] != 'f0r h3r' or p['global']['tempo'] != 120 or
            len(p['tracks']) != 15 or [s['bars'] for s in p['sections']] != [16,16,8,16,8,16,16]):
        raise ValueError('Expected the original 120 BPM / 15-track / 96-bar v5 demo')
    if p.get('patterns') or any(u.get('graphEdits') for a in p['arrangements'] for u in a['uses']):
        raise ValueError('Independent MIDI patterns or arrangement graph overrides need explicit reconciliation')
    # Tracks own patches; graph instrument nodes refer to these exact track IDs.
    patches = {4: {'stereoWidth': 0, 'release': .055},
               5: {'cutoff': 7200, 'stereoWidth': .72, 'release': .24},
               6: {'stereoWidth': .82, 'motion': .38},
               8: {'cutoff': 4400, 'attack': .022, 'release': .16, 'stereoWidth': .22},
               9: {'stereoWidth': .78, 'detune': 16},
               13: {'stereoWidth': .85}}
    for index, changes in patches.items():
        p['tracks'][index]['instrument']['synth'].update(changes)
    articulation = 0
    automation = []
    # Sparse long-form arcs; no rapid wobble or additional drum events.
    curves = {(2,6): ([1100,1800,2800], [.12,.16,.20]),
              (4,6): ([1900,950,1800], [.16,.12,.16]),
              (5,6): ([1700,2100,2500], [.14,.17,.20]),
              (3,9): ([3100,3900,4500], [.14,.17,.19]),
              (5,9): ([3500,4400,5000], [.15,.18,.21])}
    for si, section in enumerate(p['sections']):
        for ti in (5,8):
            lane = section['lanes'][ti]
            midi = [n for n in section['graph']['nodes'] if n['content'].get('midi',{}).get('laneID') == lane['id']]
            if len(midi) != 1 or lane['trackID'] != p['tracks'][ti]['id']:
                raise ValueError('Graph MIDI must reference its legacy lane exactly once')
            for note in lane['notes']:
                # Keep bass/drums and all note positions/pitches/velocities untouched.
                # EP comps breathe; lead sustained notes retain their phrase endings.
                factor = (.94 if si != 4 else 1.0) if ti == 5 else (.97 if note['length'] < .5 else 1.0)
                if factor != 1:
                    note['length'] = round(note['length'] * factor, 6)
                    articulation += 1
        for ti in (6,9):
            if (si,ti) not in curves:
                continue
            node = next(n for n in section['graph']['nodes'] if n['content'].get('instrument',{}).get('trackID') == p['tracks'][ti]['id'])
            if node.get('automation'):
                raise ValueError('Refusing to replace existing demo automation')
            values = curves[si,ti]
            beats = [0, section['bars']*2, section['bars']*4]
            node['automation'] = []
            for parameter, levels in zip(('synthCutoff','synthResonance'), values):
                points = [{'id':str(uuid.uuid5(NAMESPACE, f"{section['id']}:{node['id']}:{parameter}:{beat}")).upper(),
                           'beat':beat, 'value':value, 'shape':'linear'} for beat,value in zip(beats,levels)]
                node['automation'].append({'parameter':parameter,'enabled':True,'points':points})
            automation.append({'sectionID':section['id'],'nodeID':node['id'],'points':6})
    p['schemaVersion'] = max(6,p['schemaVersion'])
    p['musicRevision'] = p.get('musicRevision',0)+1
    return p, {'productionVersion':6,'sourceVersion':5,'automation':automation,
               'articulatedNotes':articulation,'modifiedPatchTrackIndices':list(patches),
               'preserved':['existing IDs','layout','colors','form','DJ drums','note starts/pitches/velocities','routing','media'],
               'listeningReview':'pending','audioMeasurements':'pending final engine render'}


def run(source, destination):
    source, destination = source.resolve(), destination.absolute()
    report_path = destination.with_suffix('.v6-report.json')
    if destination.exists() or report_path.exists() or source == destination or source in destination.parents:
        raise ValueError('Use a new destination outside the source project')
    if any(x.is_symlink() for x in source.rglob('*')):
        raise ValueError('Symlink media is not supported')
    raw = (source/'manifest.json').read_bytes()
    p, report = refine(json.loads(raw))
    encoded = (json.dumps(p,ensure_ascii=False,indent=2,sort_keys=True)+'\n').encode()
    report.update(sourceManifestSHA256=hashlib.sha256(raw).hexdigest(),
                  resultManifestSHA256=hashlib.sha256(encoded).hexdigest())
    shutil.copytree(source,destination)
    (destination/'manifest.json').write_bytes(encoded)
    report_path.write_text(json.dumps(report,ensure_ascii=False,indent=2,sort_keys=True)+'\n')
    return report


if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source',type=Path);parser.add_argument('destination',type=Path)
    args=parser.parse_args()
    print(json.dumps(run(args.source,args.destination),ensure_ascii=False,indent=2))
