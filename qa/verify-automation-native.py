#!/usr/bin/env python3
"""Capture or exercise automation on the exact dedicated 0.19 QA project."""
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
OUT=ROOT/'qa/generated/0.19'
EXPECTED=OUT/'automation-QA.circlr'
SOCKET=Path.home()/'Library/Application Support/circlr-hierarchy-qa/Agent/agent.sock'

def raw(name,args=None):return call_tool(str(SOCKET),'circlr_'+name,args or {})['structuredContent']
def call(name,args=None):
    r=raw(name,args)
    if not r.get('ok'):raise RuntimeError(r)
    return r['result']
def state():
    s=call('snapshot')
    assert s['runtime']['bundleID']=='com.circlr.hierarchyqa' and s['runtime']['version']=='0.19.0' and s['path']==str(EXPECTED),'Expected dedicated 0.19 QA app and exact copy'
    return s
def write(name,args=None):
    s=state();return call(name,dict(args or {},projectID=s['projectID'],expectedRevision=s['revision']))
def inspect(s):
    a=s['selection'].get('music') or s['selection'].get('section')
    assert a,'Select a section or audio circle'
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
    p=argparse.ArgumentParser();p.add_argument('name');p.add_argument('--commands',action='store_true');p.add_argument('--export',action='store_true');p.add_argument('--bounce-audio',action='store_true');a=p.parse_args()
    assert re.fullmatch(r'[a-z0-9-]{1,64}',a.name)
    target=OUT/(a.name+'.json');assert not target.exists()
    result=capture()
    if a.commands:
        s=result['state'];before=result['inspection'];address=s['selection']['music']
        op=dict(kind='set_automation',**address,parameter='gain',automationPoints=[dict(id='qa-automation-0',beat=0,value=.2,shape='linear'),dict(id='qa-automation-1',beat=2,value=1,shape='linear')])
        write('apply',{'operations':[op]});after=inspect(state());revision=state()['revision']
        write('apply',{'operations':[op]});assert state()['revision']==revision
        bad=dict(kind='set_automation',**address,parameter='pan',automationPoints=[dict(beat=0,value=2)])
        s=state();failed=raw('apply',{'projectID':s['projectID'],'expectedRevision':s['revision'],'operations':[dict(op,automationPoints=[dict(beat=0,value=.4)]),bad]})
        assert not failed['ok'] and inspect(state())['graph']==after['graph'] and state()['revision']==s['revision']
        write('apply',{'operations':[dict(kind='set_automation',**address,parameter='gain',enabled=False)]})
        node=next(n for n in inspect(state())['graph']['nodes'] if n['id']==address['nodeID']);assert next(c for c in node['automation'] if c['parameter']=='gain')['enabled'] is False
        write('undo');assert inspect(state())['graph']==after['graph']
        write('undo');assert inspect(state())['lanes']==before['lanes'] and inspect(state())['graph']==before['graph']
        result['commands']={'setCurve':True,'sameCurveNoOp':True,'invalidBatchAtomic':True,'bypassPreservesPoints':True,'undoRestored':True}
    if a.bounce_audio:
        import shutil
        assert not a.export
        before=capture();address=before['state']['selection']['music'];detail=before['inspection']
        node=next(n for n in detail['graph']['nodes'] if n['id']==address['nodeID']);lane_id=node['content']['audio']['laneID'];lane=next(l for l in detail['lanes'] if l['id']==lane_id)
        job=wait(write('bounce',dict(arrangementID=address['arrangementID'],useID=address['useID'],trackID=lane['trackID'])))
        after=capture();new=next(n for n in after['inspection']['graph']['nodes'] if n['id']==job['nodeID']);clip=next(c for l in after['inspection']['lanes'] for c in l['audio'] if c['id']==new['content']['audio']['clipID'])
        asset=next(a for a in after['state']['assets'] if a['id']==clip['assetID']);source=Path(asset['path']);source=source if source.is_absolute() else EXPECTED/source
        target_audio=OUT/(a.name+'.wav');assert not target_audio.exists();shutil.copy2(source,target_audio)
        write('undo');restored=inspect(state());assert restored['lanes']==before['inspection']['lanes'] and restored['graph']==before['inspection']['graph']
        result['bounce']={'job':job,'audio':str(target_audio),'seconds':asset['duration'],'undoRestored':True}
    if a.export:
        path=OUT/(a.name+'.wav');wait(write('export',{'path':str(path)}));state()
        actual=hashlib.sha256(path.read_bytes()).hexdigest();expected=hashlib.sha256((ROOT/'music/f0r-h3r/v4/f0r h3r.wav').read_bytes()).hexdigest();assert actual==expected
        result['audioSHA256']=actual
    target.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n');print(json.dumps({'path':str(target),'commands':result.get('commands'),'export':a.export}))
if __name__=='__main__':main()
