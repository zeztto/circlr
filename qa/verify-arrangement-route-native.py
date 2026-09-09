#!/usr/bin/env python3
"""Capture only the owned build84 project; never starts playback or recording."""
import importlib.util,json,re,sys
from pathlib import Path
spec=importlib.util.spec_from_file_location('qa',Path(__file__).with_name('verify-integration-native.py'))
q=importlib.util.module_from_spec(spec);spec.loader.exec_module(q)
q.OUT=q.ROOT/'qa/generated/arrangement-route'
p=json.loads((q.OUT/'package.json').read_text());q.FIXTURE=Path(p['fixture']);q.PROJECT_ID=p['projectID']
def capture(name):
 assert re.fullmatch('[a-z0-9-]{1,64}',name)
 s=q.state();assert s['runtime']['build']=='84' and s['output']['attempts']==0 and s['audition']['attempts']==0
 with (q.OUT/(name+'.json')).open('x') as f:json.dump(q.capture(save=True),f,ensure_ascii=False,indent=2)
if __name__=='__main__':
 assert len(sys.argv)==2;capture(sys.argv[1])
