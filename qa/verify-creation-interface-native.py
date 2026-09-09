#!/usr/bin/env python3
"""Validate the owned fresh-song workflow in the creation-interface candidate."""
import importlib.util,json,re,sys
from pathlib import Path
spec=importlib.util.spec_from_file_location('integration_qa',Path(__file__).with_name('verify-integration-native.py'))
qa=importlib.util.module_from_spec(spec);spec.loader.exec_module(qa)
qa.OUT=qa.ROOT/'qa/generated/creation-workflow'
identity=json.loads((qa.OUT/'identity.json').read_text());qa.PROJECT_ID=identity['projectID'];qa.FIXTURE=Path(identity['path'])
if __name__=='__main__':
 assert len(sys.argv)==2 and re.fullmatch('[a-z0-9-]{1,64}',sys.argv[1])
 s=qa.state();assert s['runtime']['build']=='77' and s['output']['attempts']==s['audition']['attempts']==0
 with (qa.OUT/(sys.argv[1]+'.json')).open('x') as f:json.dump(qa.capture(save=True),f,ensure_ascii=False,indent=2)
