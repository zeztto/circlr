#!/usr/bin/env python3
"""Capture only the owned build 65 project; never starts playback or recording."""
import importlib.util
import json
from pathlib import Path
import re
import sys
import uuid

spec=importlib.util.spec_from_file_location('integration_qa',Path(__file__).with_name('verify-integration-native.py'))
qa=importlib.util.module_from_spec(spec);spec.loader.exec_module(qa)
qa.OUT=qa.ROOT/'qa/generated/music-settings'
qa.FIXTURE=qa.FIXTURE.with_name('music-settings.circlr')
qa.PROJECT_ID=str(uuid.uuid5(uuid.NAMESPACE_URL,'circlr-integration-qa/music-settings')).upper()

if __name__=='__main__':
    assert len(sys.argv) in (2,3) and re.fullmatch('[a-z0-9-]{1,64}',sys.argv[1])
    assert len(sys.argv)==2 or sys.argv[2]=='--save'
    before=qa.state();assert before['runtime']['build']=='65'
    result=qa.capture(save=len(sys.argv)==3);result['beforeSave']=before
    assert result['state']['output']['attempts']==result['state']['audition']['attempts']==0
    with (qa.OUT/(sys.argv[1]+'.json')).open('x') as file:json.dump(result,file,ensure_ascii=False,indent=2)
