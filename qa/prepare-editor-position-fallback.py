#!/usr/bin/env python3
"""Emulate external edits only in the owned, clean build68 QA document."""
import copy
import json
import runpy
from pathlib import Path
import sys

q=runpy.run_path(str(Path(__file__).with_name('verify-editor-position-native.py')))['qa']
mode=sys.argv[1];assert mode in {'shorter','drum','low-pitch','restore','restore-final','restore-reviewed'}
s=q.state();assert s['runtime']['build']=='68' and not s['dirty'] and s['job']['state']=='completed'
assert s['output']['attempts']==s['audition']['attempts']==0 and not s['playback']['playing']
base=json.loads((q.OUT/'orbit-cold-saved.json').read_text())['manifest']
current=json.loads((q.FIXTURE/'manifest.json').read_text())
# Require a captured copy of the current document; refuse unrecorded external changes.
assert any(json.loads(path.read_text()).get('manifest')==current for path in q.OUT.glob('*.json'))
p=copy.deepcopy(base);assert p['id']==q.PROJECT_ID
if mode=='drum':p['hierarchyView']=json.loads((q.OUT/'drum-saved.json').read_text())['manifest']['hierarchyView']
if mode=='low-pitch':
    p['circleLayout']='freeform';p['hierarchyView']['midiStepMode']=False
    p['hierarchyView']['workspace']['editor']['topPitch']=-400
if mode=='shorter':
    p['arrangements'][0]['uses'][0]['barsOverride']=1;p['musicRevision']+=1
    p['hierarchyView']['workspace']['editor']['steps']['page']=15
with (q.OUT/(mode+'-input.json')).open('x') as f:json.dump(p,f,ensure_ascii=False,indent=2)
(q.FIXTURE/'manifest.json').write_text(json.dumps(p,ensure_ascii=False,indent=2)+'\n')
print(q.write('open',{'path':str(q.FIXTURE)}))
