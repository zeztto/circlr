#!/usr/bin/env python3
"""Check recorded Native UI outcomes and the final signed package, without operating an app."""
import hashlib
import json
from pathlib import Path
import plistlib
import struct
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'qa/generated/number-editing'


def capture(name):
    data = json.loads((OUT / (name + '.json')).read_text())
    assert data['state']['projectID'] == '422D68D8-8D07-577C-A021-F62F2DA9B82A'
    assert data['state']['runtime']['bundleID'] == 'com.circlr.integrationqa'
    assert not data['state']['recording']['busy'] and not data['state']['recording']['midi']
    return data


def manifest(name):
    return capture(name)['manifest']


def use(name):
    return manifest(name)['arrangements'][0]['uses'][0]


def synth(name):
    return manifest(name)['tracks'][1]['instrument']['synth']


def note(name):
    return use(name)['addedLanes'][0]['notes'][2]


def sections(path):
    data = path.read_bytes()
    assert struct.unpack_from('<I', data)[0] == 0xFEEDFACF
    offset = 32
    result = {}
    for _ in range(struct.unpack_from('<I', data, 16)[0]):
        command, size = struct.unpack_from('<II', data, offset)
        if command == 0x19:
            for index in range(struct.unpack_from('<I', data, offset + 64)[0]):
                section = offset + 72 + index * 80
                name, segment = struct.unpack_from('<16s16s', data, section)
                length, start = struct.unpack_from('<QI', data, section + 40)
                if start and length:
                    result[(segment + b'/' + name).replace(b'\0', b'').decode()] = [length, hashlib.sha256(data[start:start + length]).hexdigest()]
        offset += size
    return result


def main():
    initial = manifest('final-initial')
    assert note('final-midi-tab')['beat'] == 2.25 and note('final-midi-tab')['length'] == 0.75
    assert note('final-midi-tab')['velocity'] == 96
    assert note('final-midi-undo-velocity')['velocity'] == 74
    assert capture('final-midi-tab')['state']['revision'] == 51
    assert use('final-repeat')['repeatCount'] == use('final-repeat-button-undo')['repeatCount'] == 2
    assert use('final-repeat-restored')['repeatCount'] == 1
    assert manifest('final-tempo-draft')['global']['tempo'] == 120
    assert manifest('final-tempo-applied')['global']['tempo'] == 128
    assert synth('final-synth-tab')['cutoff'] == 1200 and synth('final-synth-tab')['detune'] == 12
    assert synth('final-synth-tab') == synth('final-synth-typed') == synth('final-stale')
    assert capture('final-synth-typed')['state']['revision'] == 62
    assert capture('final-stale')['state']['revision'] == 63
    assert manifest('final-target-changed')['tracks'] == initial['tracks']
    assert manifest('final-precision-before')['tracks'] == manifest('final-precision-after')['tracks']
    assert capture('final-precision-before')['state']['revision'] == capture('final-precision-after')['state']['revision'] == 67
    assert any(n['id'].startswith('mix:') and n['gain'] == 0.85 for n in use('final-output')['graphEdits']['addedNodes'])
    clip = use('final-audio-tab')['laneOverrides']['C02E0506-5351-553D-992A-688B212C4D62']['audio'][0]
    assert (clip['duration'], clip['gain']) == (12.25, 0.8)
    for key in ['global', 'tracks', 'sections', 'arrangements', 'assets']:
        assert initial[key] == manifest('final-restored')[key] == manifest('final-reopened')[key], key
    reopened = capture('final-reopened')['state']
    assert reopened['revision'] == 74 and not reopened['dirty'] and reopened['job']['state'] == 'completed'
    assert '정수를 입력하세요' in (OUT / 'final-midi-invalid-ax.txt').read_text()
    assert '정수를 입력하세요' in (OUT / 'final-count-invalid-ax.txt').read_text()
    assert '편집 대상이 변경되었습니다' in (OUT / 'final-stale-ax.txt').read_text()
    app = OUT / 'final/써클러 통합 검증.app'
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    assert info['CFBundleVersion'] == '29'
    source_sections = sections(ROOT / '.build/integration-release/release/circlr')
    assert source_sections == sections(app / 'Contents/MacOS/circlr')
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    kit = app / 'Contents/Resources/Codex'
    files = json.loads((kit / 'manifest.json').read_text())['files']
    for name, digest in files.items():
        assert hashlib.sha256((kit / name).read_bytes()).hexdigest() == digest
    result = dict(result='passed', restoredRevision=74, fileBackedSections=len(source_sections), kitFiles=len(files),
                  nativeScreens=['MIDI', 'synth', 'audio', 'output', 'repeat', 'global tempo'],
                  previousCandidates='First-letter loss and stale Tab reproduced; replaced by AppKit and live getters.')
    (OUT / 'verification.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(result, ensure_ascii=False))


if __name__ == '__main__':
    main()
