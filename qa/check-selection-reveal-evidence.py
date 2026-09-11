#!/usr/bin/env python3
"""Validate captured selection navigation against full music and final package."""
from pathlib import Path
import copy,hashlib,json,subprocess,unicodedata,runpy
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'qa/generated/selection-reveal'
def load(n):return json.loads((OUT/(n+'.json')).read_text())
def music(p):
 p=copy.deepcopy(p)
 for k in ['hierarchyView','musicRevision']:p.pop(k,None)
 return p
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 base=music(load('fixture-initial'))
 names={'final-button':14,'final-keyboard':14,'empty-selection':14,'wide-selection':15,'undo-reveal':16,'low-pitch':17,'restored':18,'reopened':18,'upper-returned':18}
 ids=sorted(n['id'] for n in base['arrangements'][0]['uses'][0]['addedLanes'][0]['notes'])
 for name,rev in names.items():
  d=load(name);s=d['state'];p=d['manifest'];expected=copy.deepcopy(base)
  assert s['projectID']==p['id']=='7A768999-1E82-5E7B-BB16-E5CE8FFFF0DB'
  assert s['runtime']['build']=='72' and s['runtime']['bundleID']=='com.circlr.integrationqa'
  assert s['revision']==p['musicRevision']==rev and not s['dirty']
  assert not s['playback']['playing'] and s['output']['attempts']==s['audition']['attempts']==0
  assert not s['recording']['midi'] and not s['recording']['busy']
  notes=expected['arrangements'][0]['uses'][0]['addedLanes'][0]['notes']
  if name=='wide-selection':next(n for n in notes if n['pitch']==73)['beat']=60
  if name=='low-pitch':next(n for n in notes if n['pitch']==66)['pitch']=0
  assert music(p)==expected,name
  assert s['selectedNoteIDs']==([] if name=='empty-selection' else ids),name
  assert p['hierarchyView']['workspace']['selection']['noteIDs']==s['selectedNoteIDs']
  assert (OUT/(name+'.jpg')).stat().st_size>10000
  ax=(OUT/(name+'.ax.txt')).read_text()
  assert '선택 보기' in ax and '피아노 롤' in ax
 assert 'button (disabled) Description: 선택 보기' in (OUT/'empty-selection.ax.txt').read_text()
 assert load('reopen-completed')['job']['id']==load('reopen-job')['jobID']
 assert load('reopen-completed')['job']['state']=='completed'
 # Returning from a higher displayed range scrolls, without resetting that range.
 assert load('upper-returned')['manifest']['hierarchyView']['workspace']['editor']['topPitch']==86
 assert load('upper-returned')['manifest']['hierarchyView']['workspace']['editor']['scrolls']['piano']['y']>200
 for n,h in load('final/source-hashes').items():assert digest(ROOT/n)==h,n
 for candidate in ['', 'refined/', 'final/']:
  app=OUT/candidate/'써클러 통합 검증.app'
  subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True,capture_output=True)
 final=OUT/'final/써클러 통합 검증.app/Contents'
 sections=runpy.run_path(str(ROOT/'qa/check-library-evidence.py'))['sections']
 assert sections(ROOT/'.build/integration-release/release/circlr')==sections(final/'MacOS/circlr')
 assert 'Executed 496 tests, with 0 failures' in (ROOT/'.build/selection-reveal-tests.log').read_text()
 assert 'Ran 29 tests' in (ROOT/'.build/selection-reveal-python-tests.log').read_text()
 kit=json.loads((final/'Resources/Codex/manifest.json').read_text())
 for n,h in kit['files'].items():assert digest(final/'Resources/Codex'/n)==h
 fixture=Path(load('final/package')['fixture']);source=fixture.with_name('studio.circlr')
 assert digest(source/'manifest.json')==load('final/package')['sourceSHA256']
 assert music(json.loads((fixture/'manifest.json').read_text()))==base
 for asset in base['assets']:assert digest(source/asset['path'])==digest(fixture/asset['path'])==asset['checksum']
 processes=unicodedata.normalize('NFC',subprocess.check_output(['ps','-axo','command='],text=True))
 assert not any(str(OUT) in l and '/Contents/MacOS/circlr' in l for l in processes.splitlines())
 print(json.dumps(dict(status='passed',snapshots=len(names),sourceFiles=3,kitFiles=len(kit['files']),physicalAudioAttempts=0)))
if __name__=='__main__':main()
