#!/usr/bin/env python3
"""Capture only the owned accessibility QA project; no playback or recording."""
import importlib.util
import json
from pathlib import Path
import re
import sys

spec=importlib.util.spec_from_file_location('integration_qa',Path(__file__).with_name('verify-integration-native.py'))
qa=importlib.util.module_from_spec(spec);spec.loader.exec_module(qa)
qa.OUT=qa.ROOT/'qa/generated/accessibility-geometry'
qa.FIXTURE=qa.FIXTURE.with_name('accessibility-geometry.circlr')
qa.PROJECT_ID='E95D8338-1A25-5D4B-A44C-5DEDDDB6B8F4'
if __name__=='__main__':
    assert len(sys.argv)==2 and re.fullmatch('[a-z0-9-]{1,64}',sys.argv[1])
    s=qa.state();assert s['runtime']['build'] in ['69','70']
    r=qa.capture(save=True)
    assert r['state']['output']['attempts']==r['state']['audition']['attempts']==0
    with (qa.OUT/(sys.argv[1]+'.json')).open('x') as f:json.dump(r,f,ensure_ascii=False,indent=2)
