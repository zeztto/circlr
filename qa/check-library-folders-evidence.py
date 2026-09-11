#!/usr/bin/env python3
"""Verify build 53's exact local folder-management captures and package."""
import copy
import hashlib
import json
from pathlib import Path
import plistlib
import re
import runpy
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'qa/generated/library-folders'
FINAL = OUT / 'final'
KEYS = ['name', 'global', 'tracks', 'sections', 'arrangements', 'assets', 'patterns', 'signal', 'portLayout', 'circleLayout']
CASES = {'baseline': (14, 1, 1), 'first-folders': (14, 3, 1), 'final-escape': (14, 3, 1),
         'final-management-selection': (14, 3, 2), 'final-errors-resolved': (14, 3, 0),
         'final-imported': (15, 3, 2), 'final-unregistered': (15, 1, 0),
         'final-restored': (16, 1, 0), 'final-reopened': (16, 1, 0)}


def music(project):
    value = {k: copy.deepcopy(project[k]) for k in KEYS}
    value['portLayout'].pop('revision', None)
    return value


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def ax(name):
    return (FINAL / (name + '.ax.txt')).read_text()


if __name__ == '__main__':
    captures = {n: json.loads((OUT / (n + '.json')).read_text()) for n in CASES}
    initial = captures['baseline']['manifest']; imported = captures['final-imported']['manifest']
    for name, (revision, folders, selected) in CASES.items():
        s = captures[name]['state']; p = captures[name]['manifest']
        assert s['projectID'] == '80DD8E13-FF7D-50BD-A48B-F365F96E625B' and s['revision'] == revision
        assert s['runtime']['bundleID'] == 'com.circlr.integrationqa' and not s['dirty']
        assert s['library']['folders'] == folders and s['library']['selectedFiles'] == selected
        assert s['library']['files'] == (4 if folders == 1 else 7)
        assert s['output']['attempts'] == s['audition']['attempts'] == 0
        assert not s['recording']['busy'] and not s['recording']['midi'] and not s['playback']['playing']
        assert not any(s['library'][k] for k in ['scanning', 'searching', 'previewPending', 'previewPlaying', 'previewPreparing'])
        assert music(p) == music(imported if revision == 15 else initial), name
    assert not captures['final-escape']['state']['library']['open']
    assert len(imported['tracks']) == 5 and imported['tracks'][:3] == initial['tracks']
    assert len(imported['assets']) == 4 and imported['assets'][:2] == initial['assets']
    assert imported['arrangements'][0]['uses'][1] == initial['arrangements'][0]['uses'][1]
    assert len({a['id'] for a in imported['assets']}) == 4
    assert [a['name'] for a in imported['assets'][2:]] == ['Folder tone.wav', 'Folder tone.wav']
    assert len({a['checksum'] for a in imported['assets'][2:]}) == 2
    hashes = json.loads((OUT / 'import-media-hashes.json').read_text())
    assert len(hashes) == 4 and all(hashes[a['id']] == a['checksum'] for a in imported['assets'])
    for label, count in [('library-editing/samples', 4), ('Nordic/Samples', 1), ('Citypop/Samples', 2)]:
        assert label + ' 파일 보기' in ax('folders') and label + ' 등록 해제' in ax('folders')
        assert f'{count}개 파일' in ax('folders')
    assert '1개 파일 · 1개 항목을 읽지 못했습니다' in ax('folders')
    for name in ['two-selected', 'selection-return']:
        assert 'Value: Folder tone, Placeholder:' in ax(name) and '2개 선택' in ax(name)
        assert len(re.findall(r'checkbox Description: .*가져오기 선택, Value: 1', ax(name))) == 2
    assert 'Value: Citypop/Samples' in ax('folder-files') and 'Value: Folder tone, Placeholder:' not in ax('folder-files')
    assert '(disabled) 2개 가져오기 · Return' in ax('mixed')
    assert ax('mixed').count('MIDI는 한 파일씩 가져옵니다. 오디오와 따로 선택하세요') == 1
    for name in ['mixed-resolved', 'empty-resolved', 'notice-dismissed']:
        assert '가져오기 실패:' not in ax(name) and 'MIDI는 한 파일씩' not in ax(name)
        assert 'Nordic/Samples: 1개 항목을 읽지 못했습니다' in ax(name)
    assert '가져오기 실패: 한 번에 1–64개 파일을 선택하세요' in ax('empty-error')
    assert '라이브러리 안내 닫기' in ax('empty-error') and '라이브러리 안내 닫기' not in ax('notice-dismissed')
    assert 'Nordic/Samples' in ax('filter-menu') and 'Citypop/Samples' in ax('filter-menu')
    assert '목록에서 폴더 제거' not in ax('filter-menu')
    assert 'Nordic/Samples' not in ax('nordic-removed') and '읽지 못했습니다' not in ax('nordic-removed')
    assert 'samples 등록 해제' in ax('unregistered') and 'Citypop/Samples' not in ax('unregistered')
    fixture = Path.home() / 'Library/Application Support/circlr-integration-qa/fixtures/library-folders.circlr'
    source = fixture.with_name('studio.circlr')
    assert digest(source / 'manifest.json') == '12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d'
    assert music(json.loads((fixture / 'manifest.json').read_text())) == music(initial)
    for asset in initial['assets']:
        for folder in [source, fixture]:
            assert digest(folder / asset['path']) == asset['checksum']
    samples = json.loads((OUT / 'sample-hashes.json').read_text()); assert len(samples) == 4
    for name, expected in samples.items():
        assert digest(OUT / 'samples' / name) == expected
    app = FINAL / '써클러 통합 검증.app'; info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    assert (info['CFBundleVersion'], info['CFBundleShortVersionString'], info['CFBundleIdentifier']) == ('53', '0.20.0', 'com.circlr.integrationqa')
    sections = runpy.run_path(str(ROOT / 'qa/check-library-evidence.py'))['sections']
    compiled = sections(ROOT / '.build/integration-release/release/circlr')
    assert len(compiled) == 37 and compiled == sections(app / 'Contents/MacOS/circlr')
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    sources = json.loads((FINAL / 'source-hashes.json').read_text()); assert len(sources) == 4
    for name, expected in sources.items():
        assert digest(ROOT / name) == expected
    kit = app / 'Contents/Resources/Codex'; files = json.loads((kit / 'manifest.json').read_text())['files']; assert len(files) == 25
    for name, expected in files.items():
        assert digest(kit / name) == expected
    assert 'Executed 396 tests, with 0 failures' in (ROOT / '.build/library-folders-tests.log').read_text()
    assert 'Ran 26 tests' in (ROOT / '.build/library-folders-python.log').read_text()
    preserve = json.loads((FINAL / 'preservation.json').read_text())
    assert preserve['ownedQAProcesses'] == [] and preserve['userApp'] == ['0.19.0', '21']
    assert set(preserve['heads'].values()) == {'d88ea5d8d5d87cf49c5ef06154397c36ba1019d7', '1d304eb244f60a21c3598b89d05192d3512d719d'}
    result = dict(status='passed', revision=16, nativeSnapshots=len(captures), finalNativeSnapshots=7,
                  finalAXCaptures=len(list(FINAL.glob('*.ax.txt'))), sourceFiles=len(sources), sampleFiles=4,
                  kitFiles=25, executableSections=37, physicalAudioAttempts=0, voiceOverSpeech='not_verified',
                  screenshots={p.name: digest(p) for p in sorted(FINAL.glob('*.jpg'))})
    (FINAL / 'verification.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({k: v for k, v in result.items() if k != 'screenshots'}, ensure_ascii=False))
