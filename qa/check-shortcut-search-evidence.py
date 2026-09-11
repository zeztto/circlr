#!/usr/bin/env python3
"""Validate native shortcut-search evidence without starting audio or apps."""
from pathlib import Path
import copy, hashlib, json, runpy, subprocess, unicodedata
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'qa/generated/shortcut-search'
def load(n):return json.loads((OUT/(n+'.json')).read_text())
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def music(p):
 p=copy.deepcopy(p)
 for k in ['hierarchyView','musicRevision']:p.pop(k,None)
 return p
def main():
 base=music(load('fixture-initial'))
 names={'baseline':14,'command-saved':14,'race-restored':16,'second-race-restored':18,'ranked-help':18,'ranked-command-saved':18,'final':18}
 for n,rev in names.items():
  d=load(n);s=d['state'];p=d['manifest']
  assert s['projectID']==p['id']=='DCD0F727-3B58-543B-9024-F6D2CEE64261'
  assert s['runtime']['build']=='75' and s['runtime']['bundleID']=='com.circlr.integrationqa'
  assert s['revision']==p['musicRevision']==rev and not s['dirty']
  assert music(p)==base,n
  assert not s['playback']['playing'] and s['output']['attempts']==s['audition']['attempts']==0
  assert not s['recording']['midi'] and not s['recording']['busy']
 checks={'ranked-keyboard':['키보드 사용법','12개 명령'],'ranked-audio-help':['9개 조작'],'ranked-tab':['1개 조작','Tab'],'ranked-no-match':['일치하는 조작이 없습니다','전체 범위에서 찾기'],'ranked-piano':['피아노 롤','1개 조작'],'open-shortcut':['⌘O','1개 조작'],'keyboard-scroll':['54개 조작'],'midi-filter':['13개 조작'],'automation-filter':['3개 조작']}
 for n,terms in checks.items():
  ax=(OUT/(n+'.ax.txt')).read_text()
  assert all(t in ax for t in terms),n
  assert (OUT/(n+'.jpg')).stat().st_size>10000
 ax=(OUT/'ranked-empty.ax.txt').read_text();assert '0개 명령' in ax and '없는명령qa75xyz' in ax
 for n,h in load('ranked/source-hashes').items():assert digest(ROOT/n)==h,n
 app=OUT/'ranked/써클러 통합 검증.app'
 subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True,capture_output=True)
 sections=runpy.run_path(str(ROOT/'qa/check-library-evidence.py'))['sections']
 assert sections(ROOT/'.build/integration-release/release/circlr')==sections(app/'Contents/MacOS/circlr')
 kit=json.loads((app/'Contents/Resources/Codex/manifest.json').read_text())
 for n,h in kit['files'].items():assert digest(app/'Contents/Resources/Codex'/n)==h
 fixture=Path(load('package')['fixture']);source=fixture.with_name('studio.circlr')
 assert digest(source/'manifest.json')==load('package')['sourceSHA256']
 assert music(json.loads((fixture/'manifest.json').read_text()))==base
 for asset in base['assets']:assert digest(source/asset['path'])==digest(fixture/asset['path'])==asset['checksum']
 processes=unicodedata.normalize('NFC',subprocess.check_output(['ps','-axo','command='],text=True))
 assert not any(str(OUT) in l and '/Contents/MacOS/circlr' in l for l in processes.splitlines())
 print(json.dumps(dict(status='passed',snapshots=len(names),screens=len(checks),sourceFiles=2,kitFiles=len(kit['files']),physicalAudioAttempts=0)))
if __name__=='__main__':main()
