#!/usr/bin/env python3
"""Package an isolated save/focus candidate with the authored fixture."""
import hashlib,importlib.util,json
from pathlib import Path
spec=importlib.util.spec_from_file_location('packager',Path(__file__).with_name('prepare-automation-workspace-qa.py'))
p=importlib.util.module_from_spec(spec);spec.loader.exec_module(p)
p.NAME='save-focus';p.BUILD='78';p.OUT=p.ROOT/'qa/generated/save-focus'
p.APP=p.OUT/'써클러 통합 검증.app';p.FIXTURE=p.SOURCE.with_name('save-focus.circlr')
if __name__=='__main__':
 p.main()
 (p.OUT/'source-hashes.json').write_text(json.dumps({n:hashlib.sha256((p.ROOT/n).read_bytes()).hexdigest() for n in ['Resources/Info.plist','Sources/CirclrApp/AlbumCanvas.swift']},indent=2)+'\n')
