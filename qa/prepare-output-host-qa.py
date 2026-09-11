#!/usr/bin/env python3
"""Package the isolated-output app with its signed helper and an authored QA project."""
import hashlib
import importlib.util
import json
from pathlib import Path
spec=importlib.util.spec_from_file_location('packager',Path(__file__).with_name('prepare-automation-workspace-qa.py'))
p=importlib.util.module_from_spec(spec);spec.loader.exec_module(p)
p.NAME='output-host';p.BUILD='76';p.OUT=p.ROOT/'qa/generated/output-host'
p.APP=p.OUT/'써클러 통합 검증.app';p.FIXTURE=p.SOURCE.with_name('output-host.circlr')
SOURCES=['Package.swift','Resources/Info.plist','Sources/CirclrAudio/PCM.swift','Sources/CirclrAudio/OutputWorkerProtocol.swift','Sources/CirclrAudio/OutputWorkerService.swift','Sources/CirclrAudio/OutputWorkerProcess.swift','Sources/CirclrAudio/Playback.swift','Sources/CirclrAudio/PlaybackTransport.swift','Sources/CirclrApp/PlaybackOutputStatus.swift','Sources/CirclrApp/RootView.swift','Tools/CirclrOutputWorker/main.swift']
if __name__=='__main__':
 p.main()
 if not (p.OUT/'fixture-initial.json').exists():(p.OUT/'fixture-initial.json').write_bytes((p.FIXTURE/'manifest.json').read_bytes())
 (p.OUT/'source-hashes.json').write_text(json.dumps({n:hashlib.sha256((p.ROOT/n).read_bytes()).hexdigest() for n in SOURCES},indent=2)+'\n')
