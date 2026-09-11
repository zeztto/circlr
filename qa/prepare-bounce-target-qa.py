#!/usr/bin/env python3
"""Package an isolated bounce target candidate with the authored fixture."""
import hashlib,importlib.util,json
from pathlib import Path
spec=importlib.util.spec_from_file_location('packager',Path(__file__).with_name('prepare-automation-workspace-qa.py'))
p=importlib.util.module_from_spec(spec);spec.loader.exec_module(p)
p.NAME='bounce-target';p.BUILD='80';p.OUT=p.ROOT/'qa/generated/bounce-target'
p.APP=p.OUT/'써클러 통합 검증.app';p.FIXTURE=p.SOURCE.with_name('bounce-target.circlr')
if __name__=='__main__':
 p.main()
 (p.OUT/'source-hashes.json').write_text(json.dumps({n:hashlib.sha256((p.ROOT/n).read_bytes()).hexdigest() for n in ['Resources/Info.plist','Sources/CirclrApp/TrackBounceButton.swift','Sources/CirclrApp/AgentWorkspace.swift','Sources/CirclrCore/BounceEditing.swift','Sources/CirclrApp/AudioWorkspace.swift','Sources/CirclrApp/InlineCircleEditor.swift','Sources/CirclrApp/OutputEditor.swift','Sources/CirclrApp/MIDIGridWorkspace.swift','Sources/CirclrApp/MIDIOrbitWorkspace.swift']},indent=2)+'\n')
