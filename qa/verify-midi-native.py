#!/usr/bin/env python3
"""Capture or exercise MIDI editing on the exact dedicated 0.17 QA project."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import sys
import time
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from mcp.server import call_tool
OUT=ROOT/'qa/generated/0.17'
EXPECTED=OUT/'midi-QA.circlr'
SOCKET=Path.home()/'Library/Application Support/circlr-hierarchy-qa/Agent/agent.sock'

def raw(name,args=None):return call_tool(str(SOCKET),'circlr_'+name,args or {})['structuredContent']
def call(name,args=None):
    r=raw(name,args)
    if not r.get('ok'):raise RuntimeError(r)
    return r['result']
def state():
    s=call('snapshot')
    assert s['runtime']['bundleID']=='com.circlr.hierarchyqa' and s['runtime']['version']=='0.17.0' and s['path']==str(EXPECTED),'Expected dedicated 0.17 QA app and exact copy'
    return s
def write(name,args=None):
    s=state();return call(name,dict(args or {},projectID=s['projectID'],expectedRevision=s['revision']))
def inspect(s):
    a=s['selection'].get('music') or s['selection'].get('section')
    assert a,'Select a section or MIDI circle'
    return call('inspect',dict(arrangementID=a['arrangementID'],useID=a['useID']))
def capture():
    s=state();return {'state':s,'inspection':inspect(s)}
def wait(job):
    deadline=time.monotonic()+120
    while time.monotonic()<deadline:
        r=call('job',{'jobID':job['jobID']})['job']
        if r['state']!='running':
            assert r['state']=='completed',r
            return r
        time.sleep(.5)
    raise TimeoutError(job)
def main():
    p=argparse.ArgumentParser();p.add_argument('name');p.add_argument('--commands',action='store_true');p.add_argument('--export',action='store_true');a=p.parse_args()
    assert re.fullmatch(r'[a-z0-9-]{1,64}',a.name)
    target=OUT/(a.name+'.json');assert not target.exists()
    result=capture()
    if a.commands:
        s=result['state'];before=result['inspection'];address=s['selection']['music']
        node=next(n for n in before['graph']['nodes'] if n['id']==address['nodeID']);lane_id=node['content']['midi']['laneID']
        lane=next(l for l in before['lanes'] if l['id']==lane_id);ids=[n['id'] for n in lane['notes'][:3]]
        op=dict(kind='edit_notes',**address,laneID=lane_id,noteIDs=ids,edit='transpose',semitones=1)
        write('apply',{'operations':[op]});after=inspect(state());changed=next(l for l in after['lanes'] if l['id']==lane_id)
        for old,new in zip(lane['notes'],changed['notes']):
            expected=dict(old,pitch=old['pitch']+(1 if old['id'] in ids else 0));assert new==expected
        s=state();failed=raw('apply',{'projectID':s['projectID'],'expectedRevision':s['revision'],'operations':[op,dict(op,noteIDs=['missing'])]})
        assert not failed['ok'] and inspect(state())['lanes']==after['lanes']
        write('undo');assert inspect(state())['lanes']==before['lanes']
        result['commands']={'selectedOnly':True,'invalidBatchAtomic':True,'undoRestored':True}
    if a.export:
        path=OUT/(a.name+'.wav');wait(write('export',{'path':str(path)}));state()
        actual=hashlib.sha256(path.read_bytes()).hexdigest();expected=hashlib.sha256((ROOT/'music/f0r-h3r/v4/f0r h3r.wav').read_bytes()).hexdigest();assert actual==expected
        result['audioSHA256']=actual
    target.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n');print(json.dumps({'path':str(target),'commands':result.get('commands'),'export':a.export}))
if __name__=='__main__':main()
