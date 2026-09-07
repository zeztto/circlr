#!/usr/bin/env python3
"""Export and bounce the saved v4 in the dedicated QA app; guard identity every mutation."""
from pathlib import Path
import hashlib
import json
import sys
import time
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from mcp.server import call_tool

if not __debug__:
    raise RuntimeError("Native QA must run without Python optimization")

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'qa/generated/0.14'
SOCKET=Path.home()/'Library/Application Support/circlr-hierarchy-qa/Agent/agent.sock'
EXPECTED=ROOT/'music/f0r-h3r/v4/f0r h3r.circlr'
PROJECT_ID=None

def call(name,args=None):
    result=call_tool(str(SOCKET),'circlr_'+name,args or {})['structuredContent']
    if not result.get('ok'):raise RuntimeError(result)
    return result['result']

def revision():
    state=call('snapshot')
    assert state['projectID']==PROJECT_ID and state['path']==str(EXPECTED), 'QA project changed'
    return {'projectID':state['projectID'],'expectedRevision':state['revision']}

def wait(result):
    deadline=time.monotonic()+120
    while time.monotonic()<deadline:
        job=call('job',{'jobID':result['jobID']})['job']
        if job['state']!='running':
            assert job['state']=='completed',job
            return job
        time.sleep(.5)
    raise TimeoutError(result)

if __name__=='__main__':
    state=call('snapshot');assert state['path']==str(EXPECTED) and len(state['tracks'])==15
    assert state['runtime']['bundleID']=='com.circlr.hierarchyqa' and state['runtime']['version']=='0.14.0'
    PROJECT_ID=state['projectID'];target=OUT/'club-bounce-QA.circlr';assert not target.exists()
    call('save',{**revision(),'path':str(target)});EXPECTED=target
    arrangement=next(a for a in state['arrangements'] if a['uses']);use=arrangement['uses'][3]
    scope={'arrangementID':arrangement['id'],'useID':use['id']}
    track=next(t for t in state['tracks'] if t['name']=='빛의 코드')
    before=call('inspect',scope);(OUT/'before-bounce.json').write_text(json.dumps(before,ensure_ascii=False,indent=2))
    print('native v4 export started',flush=True)
    before_job=wait(call('export',{**revision(),'path':str(OUT/'native-before.wav')}))
    expected=hashlib.sha256((ROOT/'music/f0r-h3r/v4/f0r h3r.wav').read_bytes()).hexdigest()
    assert hashlib.sha256((OUT/'native-before.wav').read_bytes()).hexdigest()==expected
    print('native entire WAV matches CLI; bouncing supersaw with kick sidechain',flush=True)
    bounce_job=wait(call('bounce',{**revision(),**scope,'trackID':track['id']}))
    after=call('inspect',scope);(OUT/'after-bounce.json').write_text(json.dumps(after,ensure_ascii=False,indent=2))
    after_job=wait(call('export',{**revision(),'path':str(OUT/'native-after.wav')}))
    call('save',revision())
    result={'runtime':state['runtime'],'before':before_job,'bounce':bounce_job,'after':after_job,'sha256':expected,'nativeMatchesCLI':True,'project':str(target),'scope':scope,'trackID':track['id']}
    (OUT/'native-result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2))
    print('native export and bounce completed',flush=True)
