#!/usr/bin/env python3
"""Package build 52 with the authored integration project; preserve earlier QA apps."""
import hashlib
import importlib.util
import json
from pathlib import Path

spec = importlib.util.spec_from_file_location('packager', Path(__file__).with_name('prepare-automation-workspace-qa.py'))
packager = importlib.util.module_from_spec(spec)
spec.loader.exec_module(packager)
packager.NAME = 'library-batch'
packager.BUILD = '52'
packager.OUT = packager.ROOT / 'qa/generated/library-batch'
packager.APP = packager.OUT / '써클러 통합 검증.app'
packager.FIXTURE = packager.SOURCE.with_name('library-batch.circlr')

if __name__ == '__main__':
    packager.main()
    sources = ['Resources/Info.plist', 'Sources/CirclrAudio/MediaLibrarySelection.swift',
               'Sources/CirclrApp/MediaLibraryController.swift', 'Sources/CirclrApp/MediaLibraryView.swift',
               'Sources/CirclrApp/MediaImportWorkspace.swift', 'Sources/CirclrApp/CanvasCommands.swift',
               'Sources/CirclrApp/AgentWorkspace.swift']
    (packager.OUT / 'source-hashes.json').write_text(json.dumps({name: hashlib.sha256((packager.ROOT / name).read_bytes()).hexdigest() for name in sources}, indent=2) + '\n')
    if packager.OUT == packager.ROOT / 'qa/generated/library-batch':
        import struct
        project = json.loads((packager.SOURCE / 'manifest.json').read_text())
        samples = packager.OUT / 'samples'
        samples.mkdir()
        for index, asset in enumerate(project['assets']):
            target = samples / ('A/Batch kick.wav' if index == 0 else 'B/Batch pad.wav')
            target.parent.mkdir(exist_ok=True)
            data = (packager.SOURCE / asset['path']).read_bytes()
            assert hashlib.sha256(data).hexdigest() == asset['checksum']
            target.write_bytes(data)
        (samples / 'A/broken.wav').write_bytes(b'Invalid authored audio for atomic failure QA')
        body = bytes([0, 0x90, 60, 96, 0x83, 0x60, 0x80, 60, 0, 0, 0xff, 0x2f, 0])
        (samples / 'B/keys.mid').write_bytes(b'MThd' + struct.pack('>IHHH', 6, 0, 1, 480) + b'MTrk' + struct.pack('>I', len(body)) + body)
        hashes = {str(p.relative_to(samples)): hashlib.sha256(p.read_bytes()).hexdigest() for p in samples.rglob('*') if p.is_file()}
        (packager.OUT / 'sample-hashes.json').write_text(json.dumps(hashes, indent=2) + '\n')
