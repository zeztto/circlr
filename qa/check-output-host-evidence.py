#!/usr/bin/env python3
"""Compare native output recovery, full music preservation, and signed helper packaging."""
from pathlib import Path
import copy,hashlib,json,runpy,subprocess,tempfile,unicodedata
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'qa/generated/output-host'
def load(name):return json.loads((OUT/(name+'.json')).read_text())
def music(p):
 p=copy.deepcopy(p)
 for k in ['hierarchyView','musicRevision']:p.pop(k,None)
 return p
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 base=music(load('fixture-initial'))
 names={'baseline':14,'first-ready':14,'second-ready':14,'keyboard-cancelled':14,'pending-edited':15,'pending-undo':16,'final':16,'final-baseline':16,'final-ready':16,'final-cancelled':16}
 for name,rev in names.items():
  d=load(name);s=d['state'];p=d['manifest'];expected=copy.deepcopy(base)
  if name=='pending-edited':expected['tracks'][1]['gain']=0.65
  assert music(p)==expected,name
  assert s['projectID']==p['id']=='B39C2A06-779B-5C82-BFC8-A1CB76844977'
  assert s['revision']==p['musicRevision']==rev and not s['dirty']
  assert s['runtime']['build']=='76' and s['runtime']['bundleID']=='com.circlr.integrationqa'
  assert not s['playback']['playing'] and not s['output']['transport']['didStart']
  assert s['audition']['attempts']==0 and not s['recording']['midi'] and not s['recording']['busy']
 assert load('pending-edited')['state']['output']['phase']=='connecting'
 assert load('pending-undo')['state']['output']['attemptID']==load('pending-edited')['state']['output']['attemptID']
 for ready,pending,attempt,request in [('final-ready','final-pending',1,'timedOut'),('final-cancelled','final-retry',2,'cancelled'),('keyboard-cancelled','keyboard-pending',5,'cancelled')]:
  a=load(ready)['state']['output'];b=load(pending)['output']
  assert a['attemptID']==b['attemptID'] and a['attempts']==attempt and a['request']==request
  assert a['phase']=='idle' and a['transport']['phase']=='idle'
  assert b['phase']=='connecting' and b['request']=='waiting'
 assert load('final-pending')['output']['attemptID']!=load('final-retry')['output']['attemptID']
 assert '재생 준비 취소' in (OUT/'final-retry.ax.txt').read_text()
 for n,text in [('final-pending','재생 준비 취소'),('final-ready','이전 출력 정리가 끝났습니다')]:
  assert text in (OUT/(n+'.ax.txt')).read_text();assert (OUT/(n+'.jpg')).stat().st_size>10000
 for n,h in load('final/source-hashes').items():assert digest(ROOT/n)==h,n
 for n,h in load('final/review-source-hashes').items():assert digest(ROOT/n)==h,n
 app=OUT/'final/써클러 통합 검증.app'
 subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True,capture_output=True)
 sections=runpy.run_path(str(ROOT/'qa/check-library-evidence.py'))['sections']
 counts={}
 for binary in ['circlr','circlr-output-worker']:
  a=sections(ROOT/'.build/integration-release/release'/binary);assert a==sections(app/'Contents/MacOS'/binary);counts[binary]=len(a)
 kit=json.loads((app/'Contents/Resources/Codex/manifest.json').read_text())
 for n,h in kit['files'].items():assert digest(app/'Contents/Resources/Codex'/n)==h
 fixture=Path(load('package')['fixture']);source=fixture.with_name('studio.circlr')
 assert digest(source/'manifest.json')==load('package')['sourceSHA256']
 assert music(json.loads((fixture/'manifest.json').read_text()))==base
 for asset in base['assets']:assert digest(source/asset['path'])==digest(fixture/asset['path'])==asset['checksum']
 for f in OUT.glob('*.json'):
  d=json.loads(f.read_text())
  if isinstance(d,dict):
   s=d.get('state',d)
   if isinstance(s,dict) and isinstance(s.get('output'),dict) and s['output'].get('attemptID'):
    assert not (Path(tempfile.gettempdir())/('circlr-output-'+s['output']['attemptID'])).exists(),f.name
 processes=unicodedata.normalize('NFC',subprocess.check_output(['ps','-axo','command='],text=True))
 assert not any(str(OUT) in l and '/Contents/MacOS/circlr' in l for l in processes.splitlines())
 assert 'Executed 513 tests, with 0 failures' in (ROOT/'.build/output-host-final-all-tests.log').read_text()
 assert 'Ran 16 tests' in (ROOT/'.build/output-host-helper-tests.log').read_text()
 assert json.loads((ROOT/'.build/output-host-packaging-tests.log').read_text())['packaging']=='passed'
 print(json.dumps(dict(status='passed',musicSnapshots=len(names),machOSections=counts,kitFiles=len(kit['files']),actualOutputStarted=False)))
if __name__=='__main__':main()
