#!/usr/bin/env python3
"""Verify native focus/save and interrupted animation evidence against build78."""
import hashlib,importlib.util,json,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=ROOT/'qa/generated/save-focus'
def read(name):return json.loads((p/(name+'.json')).read_text())
def view(name):return read(name)['manifest']['hierarchyView']
def camera(name):return view(name)['camera']
b=read('baseline')['manifest']
names=['baseline','album-immediate','audio-immediate','audio-reopened','before-cancel','after-cancel','cancel-settled','cancel-reopened']
for name in names:
 d=read(name);s=d['state'];assert s['runtime']['build']=='78'
 assert s['projectID']==read('package')['projectID']
 assert s['output']['attempts']==s['audition']['attempts']==0
 assert not s['recording']['busy'] and not s['recording']['midi']
 assert {k:v for k,v in d['manifest'].items() if k!='hierarchyView'}=={k:v for k,v in b.items() if k!='hierarchyView'},name
assert camera('audio-immediate')==camera('audio-reopened')
assert view('audio-immediate')['selection']==view('audio-reopened')['selection']
assert camera('before-cancel')['zoom']<camera('after-cancel')['zoom']<camera('before-cancel')['zoom']*1.33
assert camera('after-cancel')==camera('cancel-settled')==camera('cancel-reopened')
for name in ['reopen-job','cancel-reopen-job']:assert read(name)['job']['state']=='completed'
for name,digest in read('source-hashes').items():assert hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==digest
spec=importlib.util.spec_from_file_location('mach',ROOT/'qa/check-library-evidence.py');mach=importlib.util.module_from_spec(spec);spec.loader.exec_module(mach)
app=Path(read('package')['app'])
for name in ['circlr','circlr-output-worker']:assert mach.sections(app/'Contents/MacOS'/name)==mach.sections(ROOT/'.build/integration-release/release'/name)
subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
source=Path.home()/'Library/Application Support/circlr-integration-qa/fixtures/studio.circlr'
assert hashlib.sha256((source/'manifest.json').read_bytes()).hexdigest()==read('package')['sourceSHA256']
print('PASS: 8 native states, destination and cancelled cameras, complete music preservation, source/package sections and signature')
