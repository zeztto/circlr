#!/usr/bin/env python3
"""Exercise the real stdio adapter against only the owned build 62 QA document."""
import copy
import json
from pathlib import Path
import subprocess
import sys
import uuid

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'qa/generated/agent-sounds'
SOCKET=Path.home()/'Library/Application Support/circlr-integration-qa/Agent/agent.sock'
FIXTURE=Path.home()/'Library/Application Support/circlr-integration-qa/fixtures/agent-sounds.circlr'
PROJECT_ID=str(uuid.uuid5(uuid.NAMESPACE_URL,'circlr-integration-qa/agent-sounds')).upper()


def exchange(method,params,read_only=True):
    packets=[{'jsonrpc':'2.0','id':1,'method':'initialize','params':{'protocolVersion':'2025-11-25'}},
             {'jsonrpc':'2.0','method':'notifications/initialized'},
             {'jsonrpc':'2.0','id':2,'method':method,'params':params}]
    command=[sys.executable,str(ROOT/'mcp/server.py'),'--socket',str(SOCKET)]
    if read_only:command+=['--read-only']
    reply=subprocess.run(command,input='\n'.join(map(json.dumps,packets))+'\n',text=True,capture_output=True,check=True,timeout=30)
    assert not reply.stderr,reply.stderr
    parsed=[json.loads(line) for line in reply.stdout.splitlines()]
    assert parsed[0]['result']['protocolVersion']=='2025-11-25'
    return parsed[1]['result']


def call(name,args=None,read_only=True):
    response=exchange('tools/call',{'name':'circlr_'+name,'arguments':args or {}},read_only)
    assert not response.get('isError'),response
    packet=response['structuredContent'];assert packet['ok'],packet
    return packet['result']


def state():
    s=call('snapshot')
    assert s['projectID']==PROJECT_ID and s['path']==str(FIXTURE)
    assert s['runtime']['bundleID']=='com.circlr.integrationqa' and s['runtime']['build']=='62'
    assert s['runtime']['capabilities']['soundCatalog']==1
    assert s['output']['attempts']==s['audition']['attempts']==0
    assert not s['recording']['busy'] and not s['recording']['midi'] and not s['playback']['playing']
    return s


def write(name,args=None):
    assert name in {'apply','save','undo'}
    s=state()
    return call(name,dict(args or {},projectID=s['projectID'],expectedRevision=s['revision']),False)


def save_capture(name):
    before=state();write('save');result={'beforeSave':before,'state':state(),'manifest':json.loads((FIXTURE/'manifest.json').read_text())}
    with (OUT/(name+'.json')).open('x') as file:json.dump(result,file,ensure_ascii=False,indent=2)
    return result


def reads(name):
    before=state();listed=exchange('tools/list',{})['tools']
    assert {item['name'] for item in listed}=={'circlr_'+m for m in ['snapshot','inspect','ports','sounds','events','job']}
    assert all(item['annotations']['readOnlyHint'] for item in listed)
    pages=[];args={'limit':37}
    while True:
        page=call('sounds',args);pages.append(page)
        assert len(page['items'])<=37
        if 'nextOffset' not in page:break
        assert len(pages)<100
        args.update(offset=page['nextOffset'],catalogID=page['catalogID'])
    items=[item for page in pages for item in page['items']]
    assert len(items)==pages[0]['total']==len({item['id'] for item in items})
    queries=[{'category':'soundBank','query':'#５'},{'category':'soundBank','query':'피아노'},
             {'category':'soundBank','bankDrums':True},{'category':'soundBank','bankDrums':True,'query':'#26'},
             {'category':'soundBank','bankDrums':True,'query':'#128'},{'soundTarget':'effect','query':'Apple'},
             {'category':'instrument','query':'Apple'},{'query':'E.Piano 1v'},{'query':'not a circlr sound 62'},
             {'offset':1000000}]
    results=[dict(arguments=query,result=call('sounds',query)) for query in queries]
    for result in results:
        assert result['result']['catalogID']==pages[0]['catalogID']
        for item in result['result']['items']:assert 'state' not in item.get('plugin',{})
    # The read-only adapter must reject a write without sending it to the native app.
    denied=exchange('tools/call',{'name':'circlr_apply','arguments':{}},True)
    assert denied['isError'] and 'read-only' in denied['content'][0]['text']
    after=state();assert before==after,'Successful reads changed app state'
    invalid=[]
    for query in [{'soundTarget':'effect','bankDrums':False},{'catalogID':'0'*64}]:
        result=exchange('tools/call',{'name':'circlr_sounds','arguments':query})
        assert result['isError'];invalid.append(result)
    after_errors=state()
    for key in ['projectID','revision','layoutRevision','dirty','tracks','assets','selection','view','runtime','output','audition','recording']:
        assert after_errors[key]==before[key],key
    result=dict(before=before,after=after,afterErrors=after_errors,pages=pages,queries=results,denied=denied,invalid=invalid)
    with (OUT/(name+'.json')).open('x') as file:json.dump(result,file,ensure_ascii=False,indent=2)
    print(json.dumps({'name':name,'pages':len(pages),'items':len(items),'queries':len(results),'revision':before['revision']}))


if __name__=='__main__':
    mode=sys.argv[1]
    if mode=='reads':reads(sys.argv[2])
    elif mode=='capture':save_capture(sys.argv[2])
    elif mode=='apply':
        s=state();item=call('sounds',{'category':'soundBank','query':'E.Piano 1v'})['items']
        assert len(item)==1 and item[0]['bankLSB']==16
        instrument=copy.deepcopy(s['tracks'][2]['instrument']);instrument.update(kind='soundBank',**{k:item[0][k] for k in ['program','bankLSB','drums']})
        write('apply',{'operations':[{'kind':'set_instrument','trackID':s['tracks'][2]['id'],'instrument':instrument}]})
        save_capture('applied')
    elif mode=='undo':write('undo');save_capture('undone')
    else:raise ValueError(mode)
