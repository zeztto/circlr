#!/usr/bin/env python3
"""Emulate external edits only in the owned, clean build67 QA document."""
import copy
import json
import runpy
from pathlib import Path
import sys

q=runpy.run_path(str(Path(__file__).with_name('verify-saved-workspace-native.py')))['qa']
mode=sys.argv[1];assert mode in {'missing-node','missing-reconnect','missing-transition','restore'}
s=q.state();assert s['runtime']['build']=='67' and not s['dirty'] and s['job']['state']=='completed'
assert s['output']['attempts']==s['audition']['attempts']==0 and not s['playback']['playing']
base=json.loads((q.OUT/'midi-step-reopened.json').read_text())['manifest']
current=json.loads((q.FIXTURE/'manifest.json').read_text())
# Require a captured copy of the current document; refuse unrecorded external changes.
assert any(json.loads(path.read_text()).get('manifest')==current for path in q.OUT.glob('*.json'))
p=copy.deepcopy(base);assert p['id']==q.PROJECT_ID
if mode=='missing-node':p['hierarchyView']['selection']['music']['nodeID']='qa-missing-node'
if mode=='missing-reconnect':
    p['hierarchyView']=json.loads((q.OUT/'connection-saved.json').read_text())['manifest']['hierarchyView']
    p['arrangements'][0]['edges'].pop(0);p['arrangements'][0]['chosenEdges']={};p['musicRevision']+=1
if mode=='missing-transition':
    p['hierarchyView']=json.loads((q.OUT/'transition-saved.json').read_text())['manifest']['hierarchyView']
    p['arrangements'][0]['edges'].pop(1);p['musicRevision']+=1
with (q.OUT/(mode+'-input.json')).open('x') as f:json.dump(p,f,ensure_ascii=False,indent=2)
(q.FIXTURE/'manifest.json').write_text(json.dumps(p,ensure_ascii=False,indent=2)+'\n')
print(q.write('open',{'path':str(q.FIXTURE)}))
