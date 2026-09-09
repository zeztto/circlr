#!/usr/bin/env python3
"""Check the build77 native creation workflow; generated evidence stays local."""
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=ROOT/'qa/generated/creation-workflow'
def read(name):return json.loads((p/(name+'.json')).read_text())
def music(m):return {k:v for k,v in m.items() if k not in ('hierarchyView','musicRevision')}
b=read('before')['manifest']
names=['opened','kick-entered','snare-entered','notes-undone','midi-created','creation-undone','before-reopen','reopened','editor-saved','editor-reopened']
for name in names:
 d=read(name);s=d['state'];assert s['runtime']['build']=='77'
 assert s['output']['attempts']==s['audition']['attempts']==0
 assert not s['recording']['midi'] and not s['recording']['busy']
 if name not in ('kick-entered','snare-entered','midi-created'):assert music(d['manifest'])==music(b),name
assert [read(n)['manifest']['musicRevision'] for n in names[:6]]==[1,2,3,5,6,7]
assert read('editor-saved')['manifest']['hierarchyView']==read('editor-reopened')['manifest']['hierarchyView']
for name,title in [('song','현재 곡·악장에 추가'),('section','현재 섹션에 추가'),('sound','앨범 사운드에 추가')]:
 assert title in (p/(name+'-add-after.ax.txt')).read_text()
assert 'text 1/8행' in (p/'snare-search.ax.txt').read_text()
assert 'text 8/8행' in (p/'editor-reopened.ax.txt').read_text()
assert read('editor-reopen-job')['job']['state']=='completed'
print('PASS: 10 native snapshots, contextual menus, search, Undo music preservation, saved editor restoration; no device attempts')
