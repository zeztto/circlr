#!/usr/bin/env python3
"""Package a separate audio-keyboard app and authored fixture."""
import hashlib
import importlib.util
import json
from pathlib import Path

spec=importlib.util.spec_from_file_location('packager',Path(__file__).with_name('prepare-automation-workspace-qa.py'))
p=importlib.util.module_from_spec(spec);spec.loader.exec_module(p)
p.NAME='audio-keyboard';p.BUILD='74';p.OUT=p.ROOT/'qa/generated/audio-keyboard'
p.APP=p.OUT/'써클러 통합 검증.app';p.FIXTURE=p.SOURCE.with_name('audio-keyboard.circlr')
SOURCES=['Resources/Info.plist','Sources/CirclrCore/AudioEditing.swift']+['Sources/CirclrApp/'+n+'.swift' for n in ['AudioWorkspace','OrbitAudioEditor','CommittedNumberField']]
if __name__=='__main__':
    p.main()
    if not (p.OUT/'fixture-initial.json').exists():(p.OUT/'fixture-initial.json').write_bytes((p.FIXTURE/'manifest.json').read_bytes())
    (p.OUT/'source-hashes.json').write_text(json.dumps({n:hashlib.sha256((p.ROOT/n).read_bytes()).hexdigest() for n in SOURCES},indent=2)+'\n')
