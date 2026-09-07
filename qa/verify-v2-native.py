"""Native QA on an explicitly named QA socket. Never uses the production app socket."""
from pathlib import Path
import json
import sys
import time
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from mcp.server import call_tool

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'qa/generated/0.13-final'
SOCKET=Path.home()/'Library/Application Support/circlr-hierarchy-qa/Agent/agent.sock'
SESSION_ID=None
EXPECTED_PATH=None


def call(name,args=None):
    result=call_tool(str(SOCKET),'circlr_'+name,args or {})['structuredContent']
    if not result.get('ok'):raise RuntimeError(result)
    return result['result']


def revision():
    state=call('snapshot')
    assert state['projectID']==SESSION_ID and state['path']==EXPECTED_PATH, 'QA project changed during verification'
    return {'projectID':state['projectID'],'expectedRevision':state['revision']}


def wait(result):
    deadline=time.monotonic()+120
    while time.monotonic()<deadline:
        job=call('job',{'jobID':result['jobID']})['job']
        if job['state']!='running':
            assert job['state']=='completed',job
            return job
        time.sleep(1)
    raise TimeoutError(result)


if __name__=='__main__':
    state=call('snapshot');assert state['name']=='f0r h3r' and len(state['tracks'])==9,state['name']
    assert state['runtime']['bundleID']=='com.circlr.hierarchyqa'
    assert all(t['instrument']['synth']['engineVersion']==2 for t in state['tracks'] if t['instrument']['kind']=='synthesizer')
    SESSION_ID=state['projectID'];EXPECTED_PATH=str(ROOT/'music/f0r-h3r/v2/f0r h3r.circlr')
    assert state['path']==EXPECTED_PATH
    target=OUT/'f0r h3r QA.circlr';assert not target.exists()
    call('save',{**revision(),'path':str(target)})
    EXPECTED_PATH=str(target)
    arrangement=next(a for a in state['arrangements'] if a['uses'])
    use=next(u for u in arrangement['uses'] if u['name']=='f0r h3r · Chorus')
    scope={'arrangementID':arrangement['id'],'useID':use['id']}
    track=next(t for t in state['tracks'] if t['name']=='빛의 코드')
    before=call('inspect',scope)
    (OUT/'v2-before.json').write_text(json.dumps(before,ensure_ascii=False,indent=2))
    print('native v2 loaded; exporting before bounce',flush=True)
    before_job=wait(call('export',{**revision(),'path':str(OUT/'before.wav')}))
    print('native export complete; bouncing chorus supersaw with kick sidechain',flush=True)
    bounced=wait(call('bounce',{**revision(),**scope,'trackID':track['id']}))
    after=call('inspect',scope)
    (OUT/'v2-after.json').write_text(json.dumps(after,ensure_ascii=False,indent=2))
    print('bounce complete; exporting integrated result',flush=True)
    after_job=wait(call('export',{**revision(),'path':str(OUT/'after.wav')}))
    call('save',revision())
    result={'runtime':state['runtime'],'projectID':state['projectID'],'before':before_job,'bounce':bounced,'after':after_job,'scope':scope,'trackID':track['id']}
    (OUT/'native-v2-result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2))
    print('native v2 render/bounce/export verified',flush=True)
