#!/usr/bin/env python3
"""Exercise the step command or capture native state in the dedicated 0.16 QA copy."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import sys
import time
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from mcp.server import call_tool

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'qa/generated/0.16'
SOCKET=Path.home()/'Library/Application Support/circlr-hierarchy-qa/Agent/agent.sock'
EXPECTED=OUT/'step-QA.circlr'

def raw(name,args=None):
    return call_tool(str(SOCKET),'circlr_'+name,args or {})['structuredContent']

def call(name,args=None):
    r=raw(name,args)
    if not r.get('ok'):raise RuntimeError(r)
    return r['result']

def state():
    s=call('snapshot')
    if s['runtime']['bundleID']!='com.circlr.hierarchyqa' or s['runtime']['version']!='0.16.0' or s['path']!=str(EXPECTED):
        raise RuntimeError('Expected the dedicated 0.16 QA app and step-QA copy')
    return s

def write(name,args=None):
    s=state()
    return call(name,dict(args or {},projectID=s['projectID'],expectedRevision=s['revision']))

def wait(job):
    deadline=time.monotonic()+120
    while time.monotonic()<deadline:
        progress=call('job',{'jobID':job['jobID']})['job']
        if progress['state']!='running':
            if progress['state']!='completed':raise RuntimeError(progress)
            return progress
        time.sleep(.5)
    raise TimeoutError(job)

def inspect(s):
    address=s['selection'].get('music')
    if not address:raise RuntimeError('Select a MIDI circle first')
    return call('inspect',{'arrangementID':address['arrangementID'],'useID':address['useID']})

def exercise(s):
    address=s['selection']['music'];before=inspect(s)
    node=next(n for n in before['graph']['nodes'] if n['id']==address['nodeID'])
    lane_id=node['content']['midi']['laneID']
    lane=next(l for l in before['lanes'] if l['id']==lane_id)
    op=dict(kind='set_step',**address,laneID=lane_id,stepIndex=0,subdivisions=4,pitch=0,velocity=109,gate=2,enabled=True)
    write('apply',{'operations':[op]});first=inspect(state())
    write('apply',{'operations':[op]});second=inspect(state())
    assert first['lanes']==second['lanes'],'Repeated enable duplicated a note'
    current=state()
    bad=dict(op,nodeID='missing-source')
    failed=raw('apply',{'projectID':current['projectID'],'expectedRevision':current['revision'],'operations':[dict(op,pitch=1),bad]})
    assert not failed['ok'],'Invalid source was accepted'
    assert inspect(state())['lanes']==second['lanes'],'Invalid batch changed music'
    stale=raw('apply',{'projectID':current['projectID'],'expectedRevision':current['revision']-1,'operations':[op]})
    assert not stale['ok'],'Stale revision was accepted'
    write('undo')
    assert inspect(state())['lanes']==before['lanes'],'Undo did not restore lane data'
    return {'idempotent':True,'invalidBatchAtomic':True,'staleRejected':True,'undoRestored':True,'originalNoteCount':len(lane['notes'])}

def main():
    p=argparse.ArgumentParser();p.add_argument('capture');p.add_argument('--exercise',action='store_true');p.add_argument('--export',action='store_true');a=p.parse_args()
    if not re.fullmatch(r'[a-z0-9-]{1,64}',a.capture):raise ValueError('Invalid capture name')
    target=OUT/(a.capture+'.json')
    if target.exists():raise FileExistsError(target)
    s=state();result={'schema':'circlr-step-native-v1','state':s,'inspection':inspect(s)}
    if a.exercise:result['commands']=exercise(s)
    if a.export:
        path=OUT/(a.capture+'.wav');wait(write('export',{'path':str(path)}));state()
        actual=hashlib.sha256(path.read_bytes()).hexdigest()
        expected=hashlib.sha256((ROOT/'music/f0r-h3r/v4/f0r h3r.wav').read_bytes()).hexdigest()
        assert actual==expected,'Native audio differs from v4'
        result['audioSHA256']=actual;result['nativeAudioMatchesV4']=True
    target.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({'path':str(target),'commands':result.get('commands'),'audioCompared':a.export}))

if __name__=='__main__':main()
