#!/usr/bin/env python3
"""Package build 54 with the authored integration project; preserve earlier QA apps."""
import hashlib
import importlib.util
import json
from pathlib import Path

spec = importlib.util.spec_from_file_location('packager', Path(__file__).with_name('prepare-automation-workspace-qa.py'))
packager = importlib.util.module_from_spec(spec)
spec.loader.exec_module(packager)
packager.NAME = 'library-placement'
packager.BUILD = '54'
packager.OUT = packager.ROOT / 'qa/generated/library-placement'
packager.APP = packager.OUT / '써클러 통합 검증.app'
packager.FIXTURE = packager.SOURCE.with_name('library-placement.circlr')

if __name__ == '__main__':
    packager.main()
    sources = ['Resources/Info.plist', 'Sources/CirclrCore/AudioImportPlacement.swift',
               'Sources/CirclrCore/AudioImportEditing.swift', 'Sources/CirclrApp/MediaLibraryPlacement.swift',
               'Sources/CirclrApp/MediaImportWorkspace.swift', 'Sources/CirclrApp/MediaLibraryController.swift',
               'Sources/CirclrApp/MediaLibraryView.swift', 'Sources/CirclrApp/CommittedNumberField.swift']
    (packager.OUT / 'source-hashes.json').write_text(json.dumps({name: hashlib.sha256((packager.ROOT / name).read_bytes()).hexdigest() for name in sources}, indent=2) + '\n')
    if packager.OUT == packager.ROOT / 'qa/generated/library-placement':
        import math
        import struct
        import wave
        samples = packager.OUT / 'inputs/Samples'
        samples.mkdir(parents=True)
        for name, frequency in [('Placement tone.wav', 330), ('Placement pad.wav', 220)]:
            with wave.open(str(samples / name), 'wb') as audio:
                audio.setparams((2, 2, 48000, 0, 'NONE', 'not compressed'))
                audio.writeframes(b''.join(struct.pack('<hh', value, value) for value in
                    (round(2000 * math.sin(2 * math.pi * frequency * i / 48000)) for i in range(96000))))
        body = bytes([0, 0x90, 60, 96, 0x83, 0x60, 0x80, 60, 0, 0, 0xff, 0x2f, 0])
        (samples / 'Placement.mid').write_bytes(b'MThd' + struct.pack('>IHHH', 6, 0, 1, 480) + b'MTrk' + struct.pack('>I', len(body)) + body)
        hashes = {str(p.relative_to(samples)): hashlib.sha256(p.read_bytes()).hexdigest() for p in samples.iterdir()}
        (packager.OUT / 'sample-hashes.json').write_text(json.dumps(hashes, indent=2) + '\n')
