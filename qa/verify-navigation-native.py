#!/usr/bin/env python3
"""Capture native canvas geometry or verify saved QA audio against the v4 source."""
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
OUT=ROOT/'qa/generated/0.15'
SOCKET=Path.home()/'Library/Application Support/circlr-hierarchy-qa/Agent/agent.sock'
EXPECTED=OUT/'navigation-QA.circlr'

def call(name,args=None):
    result=call_tool(str(SOCKET),'circlr_'+name,args or {})['structuredContent']
    if not result.get('ok'):raise RuntimeError(result)
    return result['result']

def state():
    value=call('snapshot')
    if value['runtime']['bundleID']!='com.circlr.hierarchyqa' or value['runtime']['version']!='0.15.0' or value['path']!=str(EXPECTED):
        raise RuntimeError('Expected the dedicated 0.15 QA app and saved navigation-QA project')
    return value

def overlaps(a,b):
    return a[0]<b[0]+b[2] and b[0]<a[0]+a[2] and a[1]<b[1]+b[3] and b[1]<a[1]+a[3]

def contains(a,b):
    return a[0]-1e-5<=b[0] and a[1]-1e-5<=b[1] and a[0]+a[2]+1e-5>=b[0]+b[2] and a[1]+a[3]+1e-5>=b[1]+b[3]

def main():
    parser=argparse.ArgumentParser();parser.add_argument('capture',help='A unique local evidence name');parser.add_argument('--export',action='store_true');args=parser.parse_args()
    if not re.fullmatch(r'[a-z0-9-]{1,64}',args.capture):raise ValueError('Invalid capture name')
    target=OUT/(args.capture+'.json')
    if target.exists():raise FileExistsError(target)
    s=state();view=s['playback'];viewport=view['workspaceViewport'];editor=view['editorFrame'];labels=view['labels']
    if editor and not contains(viewport,editor):raise RuntimeError('Editor escapes workspace viewport')
    if editor and s['view']['consoleOpen'] and overlaps(editor,s['view']['consoleBounds']):raise RuntimeError('Editor overlaps console')
    for i,label in enumerate(labels):
        if not contains(viewport,label['rect']):raise RuntimeError('Label escapes viewport')
        if any(overlaps(label['rect'],other['rect']) for other in labels[i+1:]):raise RuntimeError('Labels overlap')
    result={'schema':'circlr-navigation-native-v1','state':s,'geometryPassed':True}
    if args.export:
        path=OUT/'navigation-native.wav'
        if path.exists():raise FileExistsError(path)
        s=state();job=call('export',{'projectID':s['projectID'],'expectedRevision':s['revision'],'path':str(path)})
        deadline=time.monotonic()+120
        while time.monotonic()<deadline:
            progress=call('job',{'jobID':job['jobID']})['job']
            if progress['state']!='running':
                if progress['state']!='completed':raise RuntimeError(progress)
                break
            time.sleep(.5)
        else:raise TimeoutError(job)
        state()
        actual=hashlib.sha256(path.read_bytes()).hexdigest();expected=hashlib.sha256((ROOT/'music/f0r-h3r/v4/f0r h3r.wav').read_bytes()).hexdigest()
        if actual!=expected:raise RuntimeError('Native audio differs from the v4 source')
        result['audioSHA256']=actual;result['nativeAudioMatchesV4']=True
    target.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({'path':str(target),'labels':len(labels),'canvas':view['canvasSize'],'geometryPassed':True,'audioCompared':args.export}))

if __name__=='__main__':main()
