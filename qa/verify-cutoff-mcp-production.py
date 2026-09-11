#!/usr/bin/env python3
"""Isolated build129 cutoff production evidence; no physical output commands."""
import importlib.util,json,sys,time,wave,hashlib
from pathlib import Path
spec=importlib.util.spec_from_file_location('cutoff_qa',Path(__file__).with_name('verify-cutoff-automation-qa.py'))
x=importlib.util.module_from_spec(spec);spec.loader.exec_module(x)
q=x.q
OUT=x.OUT/'final129'
USE='C958E497-716C-5DA2-B597-B55375AE2A90'
OTHER='33728378-FA9A-5ABB-9CDD-1645F190EE8D'
TRACK='7E0D9016-E91D-4325-B807-033F233E32EA'
NODE='instrument:'+TRACK
AUDIO='DDB48BA6-04EC-5F78-8AB1-7CC61F46EAC7'
def save(name,obj):
 with (OUT/(name+'.json')).open('x') as f:json.dump(obj,f,ensure_ascii=False,indent=2)
def capture(name):
 s=q.state();x.capture(name,'final129',s['revision']);return json.loads((OUT/(name+'.json')).read_text())
def op(use,points,original=False,node=NODE):
 return dict(kind='set_automation',arrangementID=x.A,useID=use,nodeID=node,parameter='synthCutoff',original=original,automationPoints=points)
def point(id,beat,value):return dict(id=id,beat=beat,value=value,shape='linear')
def inspect(use):return q.call('inspect',dict(arrangementID=x.A,useID=use))
def runjob(method,args,name):
 s=q.state();x.state(s['revision'])
 reply=q.write(method,args);save(name+'-started',reply)
 jobid=reply['jobID'];deadline=time.monotonic()+300
 while True:
  result=q.call('job',dict(jobID=jobid));job=result['job']
  if job['state']!='running':break
  if time.monotonic()>deadline:raise RuntimeError('Job still running; poll same jobID '+jobid)
  time.sleep(0.2)
 save(name+'-terminal',result)
 assert job['state']=='completed',result
 return job
if __name__=='__main__':
 command=sys.argv[1]
 if command=='setup':
  before=capture('mcp-before');assert before['state']['revision']==76
  original=before['manifest']['sections'][0]['graph']['nodes'];assert next(n for n in original if n['id']==NODE).get('automation') is None
  operations=[op(USE,[]),op(OTHER,[point('qa-cutoff-other-1200',0,1200)]),op(USE,[point('qa-cutoff-source-400',0,400),point('qa-cutoff-source-6400',4,6400)],True)]
  save('mcp-setup-reply',q.write('apply',dict(operations=operations)))
  after=capture('mcp-sweep');j=after['manifest']
  a=j['arrangements'][0]['uses'][0];assert NODE not in a.get('graphEdits',{}).get('nodeOverrides',{})
  for use,expected in [(USE,[400,6400]),(OTHER,[1200])]:
   found=next(n for n in inspect(use)['graph']['nodes'] if n['id']==NODE)
   assert [p['value'] for lane in found['automation'] if lane['parameter']=='synthCutoff' for p in lane['points']]==expected
 elif command=='negative':
  before=capture('mcp-negative-before');revision=before['state']['revision']
  bad=op(USE,[point('qa-invalid-audio',0,400)],node=AUDIO)
  packets=[('unsupported',[bad],revision),('stale',[op(USE,[point('qa-stale',0,800)])],revision-1),('atomic',[op(OTHER,[point('qa-atomic',0,1600)]),bad],revision)]
  for name,operations,rev in packets:
   from mcp.server import call_tool
   result=call_tool(str(q.SOCKET),'circlr_apply',dict(projectID=x.PROJECT_ID,expectedRevision=rev,operations=operations))
   save('mcp-rejected-'+name,result);assert result['isError']
   assert q.state()['revision']==revision
  after=capture('mcp-negative-after');assert after['manifest']==before['manifest']
 elif command=='before':
  runjob('export',dict(path=str(OUT/'mcp-before.wav')),'mcp-export-before');capture('mcp-exported-before')
 elif command=='bounce':
  runjob('bounce',dict(arrangementID=x.A,useID=USE,trackID=TRACK),'mcp-bounce');capture('mcp-bounced')
  runjob('export',dict(path=str(OUT/'mcp-after.wav')),'mcp-export-after');capture('mcp-exported-after')
 elif command=='restore':
  job=json.loads((OUT/'mcp-bounce-terminal.json').read_text())['job']
  save('mcp-restore-reply',q.write('restore_bounce',dict(arrangementID=x.A,useID=USE,nodeID=job['nodeID'])))
  capture('mcp-restored')
  runjob('export',dict(path=str(OUT/'mcp-restored.wav')),'mcp-export-restored');capture('mcp-exported-restored')
  q.call('focus',dict(arrangementID=x.A,useID=USE,nodeID=NODE,detail=True))
 elif command=='compare':
  import numpy as np
  def pcm(name):
   path=OUT/name
   with wave.open(str(path),'rb') as f:
    metadata=dict(channels=f.getnchannels(),sampleWidth=f.getsampwidth(),sampleRate=f.getframerate(),frames=f.getnframes())
    assert (metadata['channels'],metadata['sampleWidth'],metadata['sampleRate'])==(2,3,48000)
    b=np.frombuffer(f.readframes(f.getnframes()),dtype=np.uint8).reshape(-1,3).astype(np.int32)
   data=(b[:,0]|(b[:,1]<<8)|(b[:,2]<<16))<<8>>8
   return data,dict(metadata,SHA256=hashlib.sha256(path.read_bytes()).hexdigest())
  before,bmeta=pcm('mcp-before.wav');after,ameta=pcm('mcp-after.wav');restored,rmeta=pcm('mcp-restored.wav')
  assert before.shape==after.shape==restored.shape
  difference=int(np.max(np.abs(before-after)));restoredDifference=int(np.max(np.abs(before-restored)))
  assert np.max(np.abs(before))>0
  result=dict(before=bmeta,after=ameta,restored=rmeta,max24BitBounceDifference=difference,max24BitRestoreDifference=restoredDifference,nonzeroSamples=int(np.count_nonzero(before)),bound24BitLSB=4)
  save('mcp-pcm-comparison',result)
  assert difference<=4,result
  assert restoredDifference==0,result
  capture('mcp-final-focused')
  print(json.dumps(result))
 else:raise ValueError(command)
