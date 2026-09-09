#!/usr/bin/env python3
"""Package build 53 with the authored integration project; preserve earlier QA apps."""
import hashlib
import importlib.util
import json
from pathlib import Path

spec = importlib.util.spec_from_file_location('packager', Path(__file__).with_name('prepare-automation-workspace-qa.py'))
packager = importlib.util.module_from_spec(spec)
spec.loader.exec_module(packager)
packager.NAME = 'library-folders'
packager.BUILD = '53'
packager.OUT = packager.ROOT / 'qa/generated/library-folders'
packager.APP = packager.OUT / '써클러 통합 검증.app'
packager.FIXTURE = packager.SOURCE.with_name('library-folders.circlr')

if __name__ == '__main__':
    packager.main()
    sources = ['Resources/Info.plist', 'Sources/CirclrAudio/MediaLibraryFolderDisplay.swift',
               'Sources/CirclrApp/MediaLibraryController.swift', 'Sources/CirclrApp/MediaLibraryView.swift']
    (packager.OUT / 'source-hashes.json').write_text(json.dumps({name: hashlib.sha256((packager.ROOT / name).read_bytes()).hexdigest() for name in sources}, indent=2) + '\n')
    if packager.OUT == packager.ROOT / 'qa/generated/library-folders':
        import struct
        project = json.loads((packager.SOURCE / 'manifest.json').read_text())
        samples = packager.OUT / 'samples'
        samples.mkdir()
        for index, asset in enumerate(project['assets']):
            target = samples / ('Nordic/Samples/Folder tone.wav' if index == 0 else 'Citypop/Samples/Folder tone.wav')
            target.parent.mkdir(parents=True, exist_ok=True)
            data = (packager.SOURCE / asset['path']).read_bytes()
            assert hashlib.sha256(data).hexdigest() == asset['checksum']
            target.write_bytes(data)
        (samples / 'Nordic/Samples/empty.wav').write_bytes(b'')
        body = bytes([0, 0x90, 60, 96, 0x83, 0x60, 0x80, 60, 0, 0, 0xff, 0x2f, 0])
        (samples / 'Citypop/Samples/keys.mid').write_bytes(b'MThd' + struct.pack('>IHHH', 6, 0, 1, 480) + b'MTrk' + struct.pack('>I', len(body)) + body)
        hashes = {str(p.relative_to(samples)): hashlib.sha256(p.read_bytes()).hexdigest() for p in samples.rglob('*') if p.is_file()}
        (packager.OUT / 'sample-hashes.json').write_text(json.dumps(hashes, indent=2) + '\n')
