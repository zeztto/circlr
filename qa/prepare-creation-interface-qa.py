#!/usr/bin/env python3
"""Package a separate creation-interface candidate and authored auxiliary fixture."""
import hashlib,importlib.util,json
from pathlib import Path
spec=importlib.util.spec_from_file_location('packager',Path(__file__).with_name('prepare-automation-workspace-qa.py'))
p=importlib.util.module_from_spec(spec);spec.loader.exec_module(p)
p.NAME='creation-interface';p.BUILD='77';p.OUT=p.ROOT/'qa/generated/creation-interface'
p.APP=p.OUT/'써클러 통합 검증.app';p.FIXTURE=p.SOURCE.with_name('creation-interface.circlr')
SOURCES=['Resources/Info.plist','Sources/CirclrApp/RootView.swift','Sources/CirclrApp/StepEditor.swift','Sources/CirclrApp/CanvasCommands.swift','Sources/CirclrCore/HierarchyScene.swift','Sources/CirclrCore/StepRows.swift']
if __name__=='__main__':
 p.main()
 (p.OUT/'source-hashes.json').write_text(json.dumps({n:hashlib.sha256((p.ROOT/n).read_bytes()).hexdigest() for n in SOURCES},indent=2)+'\n')
