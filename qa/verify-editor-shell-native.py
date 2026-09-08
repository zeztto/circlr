#!/usr/bin/env python3
"""Guarded client for the build 39 authored fixture; no microphone capture."""
import importlib.util
import json
from pathlib import Path
import re
import sys
import uuid

spec = importlib.util.spec_from_file_location('integration_qa', Path(__file__).with_name('verify-integration-native.py'))
qa = importlib.util.module_from_spec(spec)
spec.loader.exec_module(qa)
qa.OUT = qa.ROOT / 'qa/generated/editor-shell'
qa.FIXTURE = qa.FIXTURE.with_name('editor-shell.circlr')
qa.PROJECT_ID = str(uuid.uuid5(uuid.NAMESPACE_URL, 'circlr-integration-qa/editor-shell')).upper()

if __name__ == '__main__':
    assert len(sys.argv) in (2, 3) and re.fullmatch('[a-z0-9-]{1,64}', sys.argv[1])
    assert len(sys.argv) == 2 or sys.argv[2] == '--save'
    with (qa.OUT / (sys.argv[1] + '.json')).open('x') as file:
        json.dump(qa.capture(save=len(sys.argv) == 3), file, ensure_ascii=False, indent=2)
        file.write('\n')
