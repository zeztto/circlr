#!/usr/bin/env python3
"""Compare complete music documents after native audio-layout operations."""
from pathlib import Path
import copy,hashlib,json,subprocess,unicodedata,runpy
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'qa/generated/audio-layout'
def load(n):return json.loads((OUT/(n+'.json')).read_text())
def music(p):
 p=copy.deepcopy(p)
 for k in ['hierarchyView','musicRevision']:p.pop(k,None)
 return p
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 base=music(load('fixture-initial'));laneID='7F32786A-C5A8-5B33-BEA3-0D5D029F3C14';nodeID='DDB48BA6-04EC-5F78-8AB1-7CC61F46EAC7'
 names={'baseline':14,'trimmed':15,'fades':17,'tempo':22,'split':25,'split-undo':26,'duplicate-fit':28,'restored':30,'zoomed':30,'reopened':30,'small-restored':30}
 for name,rev in names.items():
  d=load(name);s=d['state'];p=d['manifest'];expected=copy.deepcopy(base);u=expected['arrangements'][0]['uses'][0]
  assert s['projectID']==p['id']=='F85AA82A-2452-580B-ABFA-222C0F886186'
  assert s['runtime']['build']=='73' and s['runtime']['bundleID']=='com.circlr.integrationqa'
  assert s['revision']==p['musicRevision']==rev and not s['dirty']
  assert not s['playback']['playing'] and s['output']['attempts']==s['audition']['attempts']==0
  assert not s['recording']['midi'] and not s['recording']['busy']
  if name in ['trimmed','fades','tempo','split','duplicate-fit']:
   lane=copy.deepcopy(next(l for l in expected['sections'][0]['lanes'] if l['id']==laneID));clip=lane['audio'][0];u['laneOverrides'][laneID]=lane
   if name in ['trimmed','fades']:clip.update(sourceStart=2,duration=30)
   if name=='fades':clip.update(fadeIn=.1,fadeOut=.2)
   if name=='tempo':clip.update(sourceBPM=90,followsTempo=True)
   if name in ['split','duplicate-fit']:
    actual=p['arrangements'][0]['uses'][0];newClip=actual['laneOverrides'][laneID]['audio'][1]['id'];newNode=actual['graphEdits']['addedNodes'][-1]['id'];newEdge=actual['graphEdits']['addedEdges'][-1]['id']
    assert newClip!=clip['id'] and newNode not in [n['id'] for n in u['graphEdits']['addedNodes']]
    if name=='split':
     clip['renderWindow']=dict(automaticEdges=False,cycleBeat=0,duration=32,envelopes=[],sourceStart=0)
     other=copy.deepcopy(clip);clip['duration']=7.25;other.update(id=newClip,beat=14.5,sourceStart=7.25,duration=24.75)
    else:
     clip['duration']=16;other=copy.deepcopy(clip);other.update(id=newClip,beat=32)
    lane['audio'].append(other)
    node=copy.deepcopy(next(n for n in expected['sections'][0]['graph']['nodes'] if n['id']==nodeID))
    node.update(id=newNode,name='검증 톤 1 · '+('뒤' if name=='split' else '복제'));node['content']['audio']['clipID']=newClip
    edits=u['graphEdits'];edits['addedNodes'].append(node)
    edits['addedEdges'].append(dict(id=newEdge,**{'from':newNode},fromPortID='out.audio.main',gain=1,sidechain=False,signal='audio',to='FC5544DC-54E1-5CBB-80C3-514C5087D9C1',toPortID='in.audio.bus1'))
    edits['layout']['positions'][newNode]=dict(x=-270,y=-70)
    edits['layout']['groups'][0]['members'].append(newNode)
  assert music(p)==expected,name
  ax=(OUT/(name+'.ax.txt')).read_text()
  for label in ['배치 박','원본 시작 초','원본 끝 초','분할 위치 초','볼륨 dB','페이드 인 ms','페이드 아웃 ms','원본 BPM']:
   assert 'Description: 오디오 '+label in ax,(name,label)
  assert (OUT/(name+'.jpg')).stat().st_size>10000
 assert load('trimmed')['manifest']['hierarchyView']['workspace']['selection']['audioSourcePosition']==7.25
 assert load('reopen-completed')['job']['id']==load('reopen-job')['jobID'] and load('reopen-completed')['job']['state']=='completed'
 assert load('zoomed')['manifest']['hierarchyView']['workspace']['editor']['audio']==load('reopened')['manifest']['hierarchyView']['workspace']['editor']['audio']
 for n,h in load('source-hashes').items():assert digest(ROOT/n)==h,n
 app=OUT/'써클러 통합 검증.app';subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True,capture_output=True)
 sections=runpy.run_path(str(ROOT/'qa/check-library-evidence.py'))['sections']
 assert sections(ROOT/'.build/integration-release/release/circlr')==sections(app/'Contents/MacOS/circlr')
 kit=json.loads((app/'Contents/Resources/Codex/manifest.json').read_text())
 for n,h in kit['files'].items():assert digest(app/'Contents/Resources/Codex'/n)==h
 fixture=Path(load('package')['fixture']);source=fixture.with_name('studio.circlr')
 assert digest(source/'manifest.json')==load('package')['sourceSHA256']
 assert music(json.loads((fixture/'manifest.json').read_text()))==base
 for asset in base['assets']:assert digest(source/asset['path'])==digest(fixture/asset['path'])==asset['checksum']
 assert 'Executed 14 tests, with 0 failures' in (ROOT/'.build/audio-layout-tests.log').read_text()
 processes=unicodedata.normalize('NFC',subprocess.check_output(['ps','-axo','command='],text=True))
 assert not any(str(OUT) in l and '/Contents/MacOS/circlr' in l for l in processes.splitlines())
 print(json.dumps(dict(status='passed',snapshots=len(names),sourceFiles=2,kitFiles=len(kit['files']),physicalAudioAttempts=0)))
if __name__=='__main__':main()
