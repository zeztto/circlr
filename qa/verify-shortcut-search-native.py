#!/usr/bin/env python3
"""Read/save the owned shortcut-search project; no audio output or recording."""
import importlib.util
import json
from pathlib import Path
import re
import sys
import uuid
spec=importlib.util.spec_from_file_location('integration_qa',Path(__file__).with_name('verify-integration-native.py'))
qa=importlib.util.module_from_spec(spec);spec.loader.exec_module(qa)
qa.OUT=qa.ROOT/'qa/generated/shortcut-search';qa.FIXTURE=qa.FIXTURE.with_name('shortcut-search.circlr')
qa.PROJECT_ID=str(uuid.uuid5(uuid.NAMESPACE_URL,'circlr-integration-qa/shortcut-search')).upper()
if __name__=='__main__':
    assert len(sys.argv)==2 and re.fullmatch('[a-z0-9-]{1,64}',sys.argv[1])
    assert qa.state()['runtime']['build']=='75'
    r=qa.capture(save=True);assert r['state']['output']['attempts']==r['state']['audition']['attempts']==0
    with (qa.OUT/(sys.argv[1]+'.json')).open('x') as f:json.dump(r,f,ensure_ascii=False,indent=2)
