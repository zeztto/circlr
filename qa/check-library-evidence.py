#!/usr/bin/env python3
"""Check captured library outcomes, immutable QA sources and signed source/package identity."""
import hashlib
import json
from pathlib import Path
import plistlib
import struct
import subprocess

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'qa/generated/library-editing'


def capture(name):
    data=json.loads((OUT/(name+'.json')).read_text())
    assert data['state']['projectID']=='183951BB-4FA4-5A4A-8BC4-E8136B507F0E'
    assert data['state']['runtime']['bundleID']=='com.circlr.integrationqa'
    assert not data['state']['recording']['busy'] and not data['state']['recording']['midi']
    return data


def manifest(name):
    return capture(name)['manifest']


def music_equal(left,right):
    for key in ['global','tracks','sections','arrangements','assets','patterns']:
        assert manifest(left)[key]==manifest(right)[key],(left,right,key)


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
    music_equal('initial','final-audio-undo')
    music_equal('final-audio-imported','final-audio-redo')
    music_equal('final-audio-redo','final-audio-reopened')
    music_equal('final-audio-redo','final-midi-undo')
    music_equal('final-midi-imported','final-folder-removed')
    music_equal('final-folder-removed','ready-reopened')
    music_equal('ready-reopened','verified-final')
    final=capture('verified-final')['state']
    assert final['revision']==22 and not final['dirty'] and not final['library']['open'] and not final['library']['previewPending']
    panel=capture('verified-panel-keyboard')['state']['library']
    assert panel['folders']==1 and panel['files']==4 and not panel['previewPending']
    assert capture('final-audio-imported')['state']['revision']==15
    assert capture('final-stale-rejected')['state']['revision']==18
    assert len(manifest('final-stale-rejected')['assets'])==3
    assert len(manifest('final-stale-rejected')['tracks'])==3
    added=manifest('final-midi-imported')['arrangements'][0]['uses'][0]['addedLanes'][-1]['notes']
    assert [n['pitch'] for n in added]==[60,64]
    assert [n['length'] for n in added]==[1,1]
    assert all(n['velocity']==96 for n in added)
    removed=capture('final-folder-removed')['state']
    assert removed['revision']==22 and removed['library']['folders']==removed['library']['files']==0
    reopened=capture('ready-reopened')['state']
    assert reopened['revision']==22 and not reopened['dirty'] and reopened['job']['state']=='completed'
    pending=capture('final-preview-pending')['state']['library']
    assert pending['previewPending'] and pending['previewPreparing'] and not pending['previewPlaying']
    importing=capture('final-audio-imported')['state']['library']
    assert importing['previewPending'] and not importing['previewPlaying'] and not importing['previewPreparing']
    assert not capture('final-stale-rejected')['state']['library']['previewPending']
    assert not capture('final-stale-rejected')['state']['library']['previewPlaying']
    assert 'button (selected) samples / Textures/Nordic pad.wav' in (OUT/'verified-keyboard-down-ax.txt').read_text()
    assert 'button (selected) samples / Citypop keys.mid' in (OUT/'verified-keyboard-up-ax.txt').read_text()
    assert '4개 파일' in (OUT/'final-bookmark-ax.txt').read_text()
    assert '앨범 서클 캔버스' not in (OUT/'final-bookmark-ax.txt').read_text()
    assert '형식과 손상 여부를 확인하세요' in (OUT/'final-bookmark-ax.txt').read_text()
    assert 'button (disabled) 가져오기' in (OUT/'final-target-stale-ax.txt').read_text()
    assert '일치하는 파일이 없습니다' in (OUT/'final-empty-search-ax.txt').read_text()
    assert '가져오기 대상을 갱신하고' not in (OUT/'ready-target-refreshed-ax.txt').read_text()
    hashes=json.loads((OUT/'source-hashes.json').read_text())
    for name,digest in hashes.items():
        assert hashlib.sha256((OUT/'samples'/name).read_bytes()).hexdigest()==digest
    imported=manifest('final-audio-imported')['assets'][-1]
    assert imported['checksum']==hashes['Textures/Nordic pad.wav'] and imported['duration']==32
    fixture=Path.home()/'Library/Application Support/circlr-integration-qa/fixtures/library-editing.circlr'
    assert hashlib.sha256((fixture/imported['path']).read_bytes()).hexdigest()==imported['checksum']
    source=fixture.with_name('studio.circlr')/'manifest.json'
    assert hashlib.sha256(source.read_bytes()).hexdigest()=='12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d'
    app=OUT/'verified/써클러 통합 검증.app'
    assert plistlib.loads((app/'Contents/Info.plist').read_bytes())['CFBundleVersion']=='31'
    source_sections=sections(ROOT/'.build/integration-release/release/circlr')
    assert source_sections==sections(app/'Contents/MacOS/circlr')
    subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
    kit=app/'Contents/Resources/Codex';files=json.loads((kit/'manifest.json').read_text())['files']
    for name,digest in files.items():assert hashlib.sha256((kit/name).read_bytes()).hexdigest()==digest
    result=dict(result='passed',revision=22,sourceFiles=len(hashes),fileBackedSections=len(source_sections),kitFiles=len(files),
                audioDevice='Delayed HAL preview start remains separate from catalog/import validation.')
    (OUT/'verification.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(result,ensure_ascii=False))


if __name__=='__main__':main()
