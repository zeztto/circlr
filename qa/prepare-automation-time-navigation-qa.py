#!/usr/bin/env python3
"""Package build 48 with the authored integration project; preserve earlier QA apps."""
import hashlib
import importlib.util
import json
from pathlib import Path

spec = importlib.util.spec_from_file_location('packager', Path(__file__).with_name('prepare-automation-workspace-qa.py'))
packager = importlib.util.module_from_spec(spec)
spec.loader.exec_module(packager)
packager.NAME = 'automation-time-navigation'
packager.BUILD = '48'
packager.OUT = packager.ROOT / 'qa/generated/automation-time-navigation'
packager.APP = packager.OUT / '써클러 통합 검증.app'
packager.FIXTURE = packager.SOURCE.with_name('automation-time-navigation.circlr')

if __name__ == '__main__':
    packager.main()
    sources = ['Resources/Info.plist', 'Sources/CirclrCore/Compiler.swift',
               'Sources/CirclrCore/AutomationRuler.swift', 'Sources/CirclrCore/AutomationViewport.swift',
               'Sources/CirclrApp/AutomationEditor.swift']
    (packager.OUT / 'source-hashes.json').write_text(json.dumps({name: hashlib.sha256((packager.ROOT / name).read_bytes()).hexdigest() for name in sources}, indent=2) + '\n')
