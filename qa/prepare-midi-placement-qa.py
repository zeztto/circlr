#!/usr/bin/env python3
"""Package build 42 and generate only authored MIDI for position validation."""
import hashlib
import importlib.util
import json
from pathlib import Path
import struct
import sys

spec = importlib.util.spec_from_file_location('packager', Path(__file__).with_name('prepare-automation-workspace-qa.py'))
packager = importlib.util.module_from_spec(spec)
spec.loader.exec_module(packager)
packager.NAME = 'midi-placement'
packager.BUILD = '42'
packager.OUT = packager.ROOT / 'qa/generated/midi-placement'
packager.APP = packager.OUT / '써클러 통합 검증.app'
packager.FIXTURE = packager.SOURCE.with_name('midi-placement.circlr')


def variable(value):
    result = [value & 127]
    while value >> 7:
        value >>= 7
        result.insert(0, (value & 127) | 128)
    return bytes(result)


if __name__ == '__main__':
    packager.main()
    if '--candidate' not in sys.argv:
        tracks = []
        for channel, name in [(0, 'Authored keys with initial rest'), (9, 'Authored drums with initial rest')]:
            title = name.encode()
            data = b'\x00\xff\x03' + variable(len(title)) + title
            if channel == 0:
                data += b'\x00\xff\x51\x03' + int(60_000_000 / 116).to_bytes(3, 'big')
            previous = 0
            for beat, length, pitch, velocity in [(0.5, 0.75, 60, 81), (2.25, 1, 67, 105), (60, 1, 64, 91)]:
                start, end = round(beat * 480), round((beat + length) * 480)
                data += variable(start - previous) + bytes([0x90 | channel, pitch, velocity])
                data += variable(end - start) + bytes([0x80 | channel, pitch, 0])
                previous = end
            data += b'\x00\xff\x2f\x00'
            tracks.append(b'MTrk' + struct.pack('>I', len(data)) + data)
        (packager.OUT / 'authored.mid').write_bytes(b'MThd' + struct.pack('>IHHH', 6, 1, 2, 480) + b''.join(tracks))
    sources = ['Resources/Info.plist', 'Sources/CirclrCore/MIDIEditing.swift', 'Sources/CirclrApp/MIDIImportView.swift',
               'Sources/CirclrApp/CanvasFileDrop.swift', 'Sources/CirclrApp/MediaLibraryView.swift', 'Sources/CirclrApp/InlineCircleEditor.swift']
    (packager.OUT / 'source-hashes.json').write_text(json.dumps({name: hashlib.sha256((packager.ROOT / name).read_bytes()).hexdigest() for name in sources}, indent=2) + '\n')
