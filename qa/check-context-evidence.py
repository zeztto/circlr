#!/usr/bin/env python3
"""Assert recorded build 30 UI outcomes and signed package identity. No app mutation."""
import hashlib
import json
from pathlib import Path
import plistlib
import struct
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'qa/generated/context-editing'


def capture(name):
    data = json.loads((OUT / (name + '.json')).read_text())
    assert data['state']['projectID'] == 'BFE21996-2B65-5751-90D0-6C2F0A37A7A4'
    assert data['state']['runtime']['bundleID'] == 'com.circlr.integrationqa'
    assert not data['state']['recording']['busy'] and not data['state']['recording']['midi']
    return data


def manifest(name):
    return capture(name)['manifest']


def settings(name):
    return manifest(name)['arrangements'][0]['uses'][0]['settings']


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
    initial = manifest('initial')
    assert settings('tempo-meter')['tempo'] == {'source':'local','value':128}
    assert settings('tempo-meter')['meter']['value'] == {'numerator':7,'denominator':4}
    fields = settings('musical-fields')
    assert fields['meter']['value'] == {'numerator':7,'denominator':8}
    assert fields['scale']['value']['root'] == 2 and fields['scale']['value']['name'] == 'major'
    assert fields['beatGrid']['value'] == {'accents':[2,2,3],'subdivisions':8,'swing':0.3}
    assert settings('accent-invalid')['beatGrid'] == initial['arrangements'][0]['uses'][0]['settings']['beatGrid']
    assert capture('accent-invalid')['state']['revision'] == 19
    assert settings('source-album')['tempo'] == {'source':'global','value':128}
    assert settings('source-restored')['tempo'] == {'source':'local','value':128}
    assert manifest('final-global')['global']['tempo'] == 126
    assert manifest('final-global')['global']['beatGrid']['accents'] == [3,3,2]
    assert manifest('final-stale')['global'] == manifest('final-global')['global']
    assert capture('final-stale')['state']['revision'] == 37
    assert settings('final-section-tab')['tempo']['value'] == 130
    assert settings('final-section-tab')['meter']['value'] == {'numerator':5,'denominator':4}
    assert settings('final-rhythm-none')['rhythm']['value'] == {}
    assert settings('final-rhythm-undo')['rhythm'] == settings('final-pattern-created')['rhythm']
    assert manifest('final-rhythm-none')['patterns'] == manifest('final-pattern-created')['patterns']
    for name in ['restored','final-undo','final-restored','final-reopened']:
        for key in ['global','tracks','sections','arrangements','assets','patterns']:
            assert manifest(name)[key] == initial[key], (name,key)
    reopened = capture('final-reopened')['state']
    assert reopened['revision'] == 48 and not reopened['dirty'] and reopened['job']['state'] == 'completed'
    assert '강세는 1–64의 정수' in (OUT / 'accent-invalid-ax.txt').read_text()
    assert '설정이 변경되었습니다' in (OUT / 'final-stale-ax.txt').read_text()
    assert 'Description: 강세 적용' not in (OUT / 'final-accent-applied-ax.txt').read_text()
    app = OUT / 'final/써클러 통합 검증.app'
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    assert info['CFBundleVersion'] == '30'
    source_sections = sections(ROOT / '.build/integration-release/release/circlr')
    assert source_sections == sections(app / 'Contents/MacOS/circlr')
    subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
    kit = app / 'Contents/Resources/Codex'
    files = json.loads((kit / 'manifest.json').read_text())['files']
    for name,digest in files.items():
        assert hashlib.sha256((kit / name).read_bytes()).hexdigest() == digest
    source = Path.home() / 'Library/Application Support/circlr-integration-qa/fixtures/studio.circlr/manifest.json'
    assert hashlib.sha256(source.read_bytes()).hexdigest() == '12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d'
    result = dict(result='passed',restoredRevision=48,fileBackedSections=len(source_sections),kitFiles=len(files),
                  firstCandidate='Musical values passed; redundant accent draft buttons fixed before final package.')
    (OUT / 'verification.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(result,ensure_ascii=False))


if __name__ == '__main__':
    main()
