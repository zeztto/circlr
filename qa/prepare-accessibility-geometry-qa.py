#!/usr/bin/env python3
"""Package build 70 without replacing the baseline app or authored fixture."""
import hashlib
import importlib.util
import json
from pathlib import Path

spec=importlib.util.spec_from_file_location('packager',Path(__file__).with_name('prepare-automation-workspace-qa.py'))
p=importlib.util.module_from_spec(spec);spec.loader.exec_module(p)
p.NAME='accessibility-geometry';p.BUILD='70';p.OUT=p.ROOT/'qa/generated/accessibility-geometry'
p.APP=p.OUT/'써클러 통합 검증.app';p.FIXTURE=p.SOURCE.with_name('accessibility-geometry.circlr')
SOURCES=['Resources/Info.plist']+['Sources/CirclrApp/'+s+'.swift' for s in ['AccessibilityGeometry','StepEditor','EditorView','OrbitMIDIEditor','AutomationEditor','AlbumCanvas','CanvasConnectionNavigation']]
if __name__=='__main__':
    p.main()
    (p.OUT/'source-hashes.json').write_text(json.dumps({n:hashlib.sha256((p.ROOT/n).read_bytes()).hexdigest() for n in SOURCES},indent=2)+'\n')
