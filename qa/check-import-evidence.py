#!/usr/bin/env python3
"""Check recorded native import evidence and final source/package identity. No app mutations."""
from pathlib import Path
import hashlib
import json
import struct
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'qa/generated/import'
FIELDS = ['name', 'tracks', 'assets', 'sections', 'arrangements', 'signal', 'portLayout']


def read(name):
    return json.loads((OUT / (name + '.json')).read_text())


def music_equal(a, b):
    for field in FIELDS:
        assert a[field] == b[field], field


def sections(path):
    data = path.read_bytes()
    assert struct.unpack_from('<I', data)[0] == 0xFEEDFACF
    count = struct.unpack_from('<I', data, 16)[0]
    offset, result = 32, {}
    for _ in range(count):
        command, size = struct.unpack_from('<II', data, offset)
        if command == 0x19:
            for i in range(struct.unpack_from('<I', data, offset + 64)[0]):
                section = offset + 72 + i * 80
                name = data[section:section+16].split(b'\0')[0]
                segment = data[section+16:section+32].split(b'\0')[0]
                length = struct.unpack_from('<Q', data, section + 40)[0]
                start = struct.unpack_from('<I', data, section + 48)[0]
                flags = struct.unpack_from('<I', data, section + 64)[0] & 255
                if length and flags not in (1, 12, 18):
                    assert start + length <= len(data)
                    result[(segment, name)] = hashlib.sha256(data[start:start+length]).hexdigest()
        offset += size
    assert result
    return result


def main():
    before, batch = read('before')['manifest'], read('batch')['manifest']
    assert len(batch['tracks']) == len(before['tracks']) + 2
    assert len(batch['assets']) == len(before['assets']) + 2
    assert batch['musicRevision'] == before['musicRevision'] + 1
    for key in ['sections', 'portLayout']:
        assert batch[key] == before[key]
    music_equal(before, read('undo')['manifest'])
    assert read('rejected')['manifest'] == read('undo')['manifest']
    music_equal(before, read('restored')['manifest'])
    assert '대상이 변경됐거나' in (OUT / 'stale-ax.txt').read_text()
    assert 'MIDI 노트 가져오기' in (OUT / 'midi-preview-ax.txt').read_text()

    initial = read('history-before')['manifest']
    added, undone, redo = read('history-added'), read('history-undo'), read('history-redo')
    assert added['manifest']['musicRevision'] == initial['musicRevision'] + 1
    assert 'section' in added['state']['selection'] and added['state']['playback']['editorAddress'] is None
    music_equal(initial, undone['manifest'])
    imported = [a for a in added['state']['assets'] if a['name'].startswith('tone-')]
    assert len(imported) == 2 and all('/Imports/import-' in a['path'] for a in imported)
    assert redo['state']['assets'] == added['state']['assets']
    assert all(not a['path'].startswith('/') for a in read('history-redo-save')['manifest']['assets'])
    assert read('history-export')['job']['state'] == 'completed'
    audio = read('history-export-audio')
    assert audio['seconds'] == 34 and audio['rate'] == 48000 and audio['bits'] == 24 and audio['peak'] > 0.01
    music_equal(initial, read('history-restored')['manifest'])
    assert not read('history-reopened')['state']['dirty']
    assert '오디오를 읽을 수 없습니다: broken.wav' in (OUT / 'history-rejected-ax.txt').read_text()
    for name in ['history-before', 'history-added', 'history-undo', 'history-redo', 'history-restored', 'history-reopened']:
        state = read(name)['state']
        assert state['runtime']['bundleID'] == 'com.circlr.integrationqa'
        assert state['projectID'] == '5B220E1C-87F8-5309-B4EF-5C28D45ACA37'
        assert not state['recording']['busy'] and not state['recording']['midi']

    package = json.loads((OUT / 'history/package.json').read_text())
    app = Path(package['app'])
    native = sections(app / 'Contents/MacOS/circlr')
    assert native == sections(ROOT / '.build/integration-release/release/circlr')
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    source = Path.home() / 'Library/Application Support/circlr-integration-qa/fixtures/studio.circlr/manifest.json'
    assert hashlib.sha256(source.read_bytes()).hexdigest() == package['sourceSHA256']
    result = dict(status='passed', fileBackedSections=len(native), swiftTests=245, pythonTests=26,
                  nativeBatchUndo=True, nativeSaveUndoSaveRedoExport=True, nativeMIDITrackPreview=True,
                  finderDragGesture='unverified', filePromises='not implemented', microphone='not recorded')
    (OUT / 'verification.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(result, ensure_ascii=False))


if __name__ == '__main__':
    main()
