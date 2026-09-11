#!/usr/bin/env python3
"""Package build 50 with the authored integration project; preserve earlier QA apps."""
import hashlib
import importlib.util
import json
from pathlib import Path

spec = importlib.util.spec_from_file_location('packager', Path(__file__).with_name('prepare-automation-workspace-qa.py'))
packager = importlib.util.module_from_spec(spec)
spec.loader.exec_module(packager)
packager.NAME = 'midi-group-drag'
packager.BUILD = '50'
packager.OUT = packager.ROOT / 'qa/generated/midi-group-drag'
packager.APP = packager.OUT / '써클러 통합 검증.app'
packager.FIXTURE = packager.SOURCE.with_name('midi-group-drag.circlr')

if __name__ == '__main__':
    packager.main()
    sources = ['Resources/Info.plist', 'Sources/CirclrCore/MIDINoteDrag.swift',
               'Sources/CirclrApp/MIDIWorkspace.swift', 'Sources/CirclrApp/OrbitMIDIEditor.swift',
               'Sources/CirclrApp/EditorView.swift', 'Sources/CirclrApp/EditorKeyboard.swift',
               'Sources/CirclrApp/MIDIOrbitWorkspace.swift', 'Sources/CirclrApp/MIDIGridWorkspace.swift',
               'Sources/CirclrApp/MIDINoteInspector.swift', 'Sources/CirclrApp/CanvasCommands.swift']
    (packager.OUT / 'source-hashes.json').write_text(json.dumps({name: hashlib.sha256((packager.ROOT / name).read_bytes()).hexdigest() for name in sources}, indent=2) + '\n')
