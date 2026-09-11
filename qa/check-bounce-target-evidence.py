#!/usr/bin/env python3
"""Check actual bounce, rejected preflight, restoration and owned package."""
import hashlib,importlib.util,json,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];p=ROOT/'qa/generated/bounce-target'
def read(name):return json.loads((p/(name+'.json')).read_text())
def music(m):return {k:v for k,v in m.items() if k not in ('hierarchyView','musicRevision')}
b=read('baseline')['manifest']
for name in ['baseline','bounced','source-restored','bounce-undone','disconnected','connection-restored','reopened']:
 d=read(name);s=d['state'];assert s['runtime']['build']=='80' and s['projectID']==read('package')['projectID']
 assert s['output']['attempts']==s['audition']['attempts']==0
 assert not s['recording']['busy'] and not s['recording']['midi']
 if name in ['baseline','bounce-undone','connection-restored','reopened']:assert music(d['manifest'])==music(b),name
m=read('bounced')['manifest'];assert len(m['assets'])==len(b['assets'])+1
assert m['tracks']==b['tracks'] and m['sections']==b['sections']
assert read('bounced')['state']['job']['state']=='completed'
new=next(a for a in m['assets'] if a['id'] not in {a['id'] for a in b['assets']});assert new['duration']==34
r=read('rejected');assert not r['reply']['ok'] and r['reply']['error']=='출력에 연결된 연주가 없습니다'
assert r['before']['job']==r['after']['job'] and r['before']['revision']==r['after']['revision']
assert 'button Description: 바운스 · 출력 1' in (p/'audio-ready.ax.txt').read_text()
assert 'button (disabled) Description: 바운스 · 출력 1, Help: 출력에 연결된 연주가 없습니다' in (p/'disconnected.ax.txt').read_text()
assert read('reopen-job')['job']['state']=='completed'
for name,digest in read('source-hashes').items():assert hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==digest
spec=importlib.util.spec_from_file_location('mach',ROOT/'qa/check-library-evidence.py');mach=importlib.util.module_from_spec(spec);spec.loader.exec_module(mach)
app=Path(read('package')['app'])
for name in ['circlr','circlr-output-worker']:assert mach.sections(app/'Contents/MacOS'/name)==mach.sections(ROOT/'.build/integration-release/release'/name)
subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
source=Path.home()/'Library/Application Support/circlr-integration-qa/fixtures/studio.circlr'
assert hashlib.sha256((source/'manifest.json').read_bytes()).hexdigest()==read('package')['sourceSHA256']
print('PASS: 7 native snapshots, completed bounce, rejected without a job, music restoration, source/package identity')
