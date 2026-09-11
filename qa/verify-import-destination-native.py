#!/usr/bin/env python3
"""Owned native import destination QA helpers; never starts an audio device."""
import importlib.util,json
from pathlib import Path
spec=importlib.util.spec_from_file_location('integration_qa',Path(__file__).with_name('verify-integration-native.py'))
qa=importlib.util.module_from_spec(spec);spec.loader.exec_module(qa)
qa.OUT=qa.ROOT/'qa/generated/import-destination'
p=json.loads((qa.OUT/'package.json').read_text());qa.PROJECT_ID=p['projectID'];qa.FIXTURE=Path(p['fixture'])
def capture(name):
 s=qa.state();assert s['runtime']['build']=='79' and s['output']['attempts']==s['audition']['attempts']==0
 c=qa.capture(save=True)
 with (qa.OUT/(name+'.json')).open('x') as f:json.dump(c,f,ensure_ascii=False,indent=2)
 return c
