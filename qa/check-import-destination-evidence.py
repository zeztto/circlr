#!/usr/bin/env python3
"""Validate actual import target selection, undo and owned package evidence."""
import hashlib,importlib.util,json,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];p=ROOT/'qa/generated/import-destination'
def read(name):return json.loads((p/(name+'.json')).read_text())
def music(m):return {k:v for k,v in m.items() if k not in ('hierarchyView','musicRevision')}
b=read('baseline')['manifest']
for name in ['baseline','panel-cancelled','imported','undone','reopened']:
 d=read(name);s=d['state'];assert s['runtime']['build']=='79' and s['projectID']==read('package')['projectID']
 assert s['output']['attempts']==s['audition']['attempts']==0
 assert not s['recording']['busy'] and not s['recording']['midi']
 if name!='imported':assert music(d['manifest'])==music(b),name
m=read('imported')['manifest'];assert len(m['tracks'])==len(b['tracks'])+1 and len(m['assets'])==len(b['assets'])+1
assert m['tracks'][:len(b['tracks'])]==b['tracks'] and m['sections']==b['sections']
for old,new in zip(b['arrangements'],m['arrangements']):
 for use in old['uses'][1:]:assert use in new['uses']
assert '새 트랙 · 1박 · 이번 사용' in (p/'new-track-panel.ax.txt').read_text()
assert '1 · 출력 1 · 1박 · 이번 사용' in (p/'existing-track-panel.ax.txt').read_text()
assert read('reopen-job')['job']['state']=='completed'
for name,digest in read('source-hashes').items():assert hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==digest
spec=importlib.util.spec_from_file_location('mach',ROOT/'qa/check-library-evidence.py');mach=importlib.util.module_from_spec(spec);spec.loader.exec_module(mach)
app=Path(read('package')['app'])
for name in ['circlr','circlr-output-worker']:assert mach.sections(app/'Contents/MacOS'/name)==mach.sections(ROOT/'.build/integration-release/release'/name)
subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
source=Path.home()/'Library/Application Support/circlr-integration-qa/fixtures/studio.circlr'
assert hashlib.sha256((source/'manifest.json').read_bytes()).hexdigest()==read('package')['sourceSHA256']
print('PASS: 5 native states, target labels, actual new track, existing music and other use preservation, Undo/reopen, package identity')
