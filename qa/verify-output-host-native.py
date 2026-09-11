#!/usr/bin/env python3
"""Snapshot the owned output-host app/project, without starting playback or inputs."""
import importlib.util,json,re,sys,uuid
from pathlib import Path
spec=importlib.util.spec_from_file_location('integration_qa',Path(__file__).with_name('verify-integration-native.py'))
qa=importlib.util.module_from_spec(spec);spec.loader.exec_module(qa)
qa.OUT=qa.ROOT/'qa/generated/output-host';qa.FIXTURE=qa.FIXTURE.with_name('output-host.circlr')
qa.PROJECT_ID=str(uuid.uuid5(uuid.NAMESPACE_URL,'circlr-integration-qa/output-host')).upper()
if __name__=='__main__':
 assert len(sys.argv)==2 and re.fullmatch('[a-z0-9-]{1,64}',sys.argv[1])
 assert qa.state()['runtime']['build']=='76'
 with (qa.OUT/(sys.argv[1]+'.json')).open('x') as f:json.dump(qa.capture(save=True),f,ensure_ascii=False,indent=2)
