#!/usr/bin/env python3
"""Check captured native color edits and inheritance regression evidence."""
import json
from pathlib import Path
root=Path(__file__).resolve().parents[1]/'qa/generated/circle-color/native'
def load(name):return json.loads((root/(name+'.json')).read_text())
names=['reset-before-open','reset-panel-open','reset-custom','reset-custom-undo','reset-reopened']
base=load(names[0])['manifest']
assert not base.get('circleColors')
for name in names:
 value=load(name);m=value['manifest']
 assert value['state']['runtime']['build']=='81'
 assert {k:v for k,v in m.items() if k!='circleColors'}==base,name
 if name=='reset-custom':assert m['circleColors'][1]==dict(red=0,green=0,blue=0)
 else:assert not m.get('circleColors'),name
assert load('preset')['manifest']['circleColors']==load('redo')['manifest']['circleColors']
assert not load('undo')['manifest'].get('circleColors')
assert load('custom-black')['manifest']['circleColors']==load('reopened-black')['manifest']['circleColors']
assert load('panel-switched-before')==load('panel-switched-after')
print('PASS: native colors, undo, persistence, panel initialization and stale target protection')
