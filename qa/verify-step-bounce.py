#!/usr/bin/env python3
"""Native step -> synth/FX -> bounce equivalence. Run with NumPy in the QA runtime."""
from pathlib import Path
import json
import runpy
import wave
import numpy as np

m=runpy.run_path(str(Path(__file__).with_name('verify-step-native.py')))
s=m['state']();before=m['inspect'](s);address=s['selection']['music']
node=next(n for n in before['graph']['nodes'] if n['id']==address['nodeID'])
lane_id=node['content']['midi']['laneID'];lane=next(l for l in before['lanes'] if l['id']==lane_id)
assert next(t for t in s['tracks'] if t['id']==lane['trackID'])['instrument']['kind']=='synthesizer'
out=m['OUT'];paths=[out/'step-edited.wav',out/'step-bounced.wav',out/'step-bounce.json']
assert not any(p.exists() for p in paths),'Preserve earlier evidence'
op=dict(kind='set_step',**address,laneID=lane_id,stepIndex=0,subdivisions=4,pitch=68,enabled=True,velocity=109,gate=4)
m['write']('apply',{'operations':[op]})
edited=m['inspect'](m['state']());assert edited['lanes']!=before['lanes']
first=m['wait'](m['write']('export',{'path':str(paths[0])}))
bounce=m['wait'](m['write']('bounce',dict(arrangementID=address['arrangementID'],useID=address['useID'],trackID=lane['trackID'])))
assert bounce['nodeID']
second=m['wait'](m['write']('export',{'path':str(paths[1])}))
def pcm(path):
    with wave.open(str(path),'rb') as f:
        assert f.getsampwidth()==3 and f.getnchannels()==2 and f.getframerate()==48000
        a=np.frombuffer(f.readframes(f.getnframes()),dtype=np.uint8).reshape(-1,3).astype(np.int32)
    return (a[:,0] | a[:,1]<<8 | a[:,2]<<16)<<8>>8
a=pcm(paths[0]);b=pcm(paths[1]);assert a.shape==b.shape
# A 24-bit intermediate plus Float32 remix is not bit-exact; cap error at four LSB (-126 dBFS).
peak=int(np.max(np.abs(a-b)));assert peak<=4,peak
original=pcm(m['ROOT']/'music/f0r-h3r/v4/f0r h3r.wav');changed=int(np.max(np.abs(a-original)));assert changed>1
m['write']('undo');m['write']('undo');assert m['inspect'](m['state']())['lanes']==before['lanes']
paths[2].write_text(json.dumps({'jobs':[first,bounce,second],'max24BitDifference':peak,'newStepChangesPCM':changed,'undoRestored':True},ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'max24BitDifference':peak,'newStepChangesPCM':changed,'undoRestored':True}))
