#!/usr/bin/env python3
"""Dedicated 0.20 QA app only. --record requires prior user microphone authorization."""
import argparse
import json
from pathlib import Path
import re
import sys
import time
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from mcp.server import call_tool
OUT=ROOT/'qa/generated/0.20'
EXPECTED=OUT/'recording-QA.circlr'
SOCKET=Path.home()/'Library/Application Support/circlr-hierarchy-qa/Agent/agent.sock'
def raw(name,args=None):return call_tool(str(SOCKET),'circlr_'+name,args or {})['structuredContent']
def call(name,args=None):
    r=raw(name,args)
    if not r.get('ok'):raise RuntimeError(r)
    return r['result']
def state():
    s=call('snapshot');assert s['runtime']['bundleID']=='com.circlr.hierarchyqa' and s['runtime']['version']=='0.20.0' and s['path']==str(EXPECTED),'Dedicated QA app and exact copy required'
    return s
def write(name,args=None):
    s=state();return call(name,dict(args or {},projectID=s['projectID'],expectedRevision=s['revision']))
def inspect(s):
    a=s['selection'].get('music') or s['selection'].get('section');assert a
    return call('inspect',dict(arrangementID=a['arrangementID'],useID=a['useID']))
def capture():
    s=state();return {'state':s,'inspection':inspect(s)}
def wait(job):
    deadline=time.monotonic()+120
    while time.monotonic()<deadline:
        r=call('job',{'jobID':job['jobID']})['job']
        if r['state']!='running':assert r['state']=='completed',r;return r
        time.sleep(.5)
    raise TimeoutError('Observation expired; inspect the same job before further action: '+str(job))
def main():
    p=argparse.ArgumentParser();p.add_argument('name');p.add_argument('--record',action='store_true',help='Only after explicit user authorization of up to two seconds of real input');a=p.parse_args()
    assert re.fullmatch('[a-z0-9-]{1,64}',a.name);target=OUT/(a.name+'.json');assert not target.exists();result=capture()
    if a.record:
        s=result['state'];assert not s['recording']['busy'];node=next(n for n in result['inspection']['graph']['nodes'] if n['id']==s['selection']['music']['nodeID'])
        circle=next(c for c in result['inspection']['circles'] if c['address']==s['selection'])
        assert node['name']=='코드 편집 검증 바운스 · 뒤' and node.get('lengthBeats')==4 and node['repeatCount']==1 and node['startBeat']==0 and node['settings']['tempo']['source']=='inherit' and result['inspection']['context']['tempo']==120 and circle['timeline']['duration']==2,'QA recording must be capped at two seconds by its native node clock'
        result['ack']=write('record');samples=[];deadline=time.monotonic()+90
        while time.monotonic()<deadline:
            s=state();samples.append({'at':time.monotonic(),'revision':s['revision'],**s['recording']})
            if not s['recording']['busy']:break
            time.sleep(.1)
        else:
            call('stop');raise TimeoutError('Recording observation expired; input gated, inspect same worker until cleanup')
        result['samples']=samples;result['after']=capture()
        OUT.joinpath(a.name+'-events.json').write_text(json.dumps(call('events'),ensure_ascii=False,indent=2))
        # A denied/failed device is evidence, not a successful take.
        result['createdAssets']=[x for x in result['after']['state']['assets'] if x['id'] not in {x['id'] for x in result['state']['assets']}]
        assert all(0<x['duration']<=2 for x in result['createdAssets'])
    target.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n');print(json.dumps({'path':str(target),'recordRequested':a.record,'createdAssets':len(result.get('createdAssets',[]))}))
if __name__=='__main__':main()
