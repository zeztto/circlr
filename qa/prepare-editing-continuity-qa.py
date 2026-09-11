#!/usr/bin/env python3
"""Reuse the authored-fixture packager with a separate project and build identity."""
import hashlib
import importlib.util
import json
from pathlib import Path

spec = importlib.util.spec_from_file_location('packager', Path(__file__).with_name('prepare-automation-workspace-qa.py'))
packager = importlib.util.module_from_spec(spec)
spec.loader.exec_module(packager)
packager.NAME = 'editing-continuity'
packager.BUILD = '35'
packager.OUT = packager.ROOT / 'qa/generated/editing-continuity'
packager.APP = packager.OUT / '써클러 통합 검증.app'
packager.FIXTURE = packager.SOURCE.with_name('editing-continuity.circlr')

if __name__ == '__main__':
    packager.main()
    sources = ['Resources/Info.plist', 'Sources/CirclrApp/AlbumCanvas.swift', 'Sources/CirclrApp/RootView.swift',
               'Sources/CirclrApp/AutomationEditor.swift', 'Sources/CirclrApp/AppStore.swift',
               'Sources/CirclrCore/HierarchyScene.swift', 'Sources/CirclrCore/AutomationDisplay.swift',
               'Sources/CirclrCore/AutomationViewport.swift']
    hashes = {name: hashlib.sha256((packager.ROOT / name).read_bytes()).hexdigest() for name in sources}
    (packager.OUT / 'source-hashes.json').write_text(json.dumps(hashes, ensure_ascii=False, indent=2) + '\n')
