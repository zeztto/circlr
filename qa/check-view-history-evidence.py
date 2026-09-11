#!/usr/bin/env python3
"""Verify build 56 history separation, native edits, restoration and package evidence."""
import copy
import hashlib
import json
from pathlib import Path
import plistlib
import runpy
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'qa/generated/view-history'
CASES = {
    'baseline': (14, 'freeform', True, True),
    'view-only': (14, 'orbit', False, False),
    'midi-view-changed': (15, 'freeform', True, True),
    'midi-undone': (16, 'freeform', True, True),
    'redo-view': (16, 'orbit', False, False),
    'midi-redone': (17, 'orbit', False, False),
    'music-restored': (18, 'freeform', False, False),
    'circle-moved': (18, 'freeform', False, False),
    'circle-undone': (19, 'orbit', True, False),
    'reopened': (19, 'orbit', True, False),
    'restored': (19, 'freeform', True, True),
}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def document_without_view(project):
    result = copy.deepcopy(project)
    for key in ['musicRevision', 'hierarchyView', 'circleLayout']:
        result.pop(key, None)
    for key in ['grid', 'snap']:
        result['album']['layout'].pop(key)
    return result


def field(name, title, value):
    ax = (OUT / (name + '.ax.txt')).read_text()
    assert any('Description: ' + title + ', Help:' in line and line.endswith('Value: ' + value)
               for line in ax.splitlines()), (name, title, value)


if __name__ == '__main__':
    captures = {name: json.loads((OUT / (name + '.json')).read_text()) for name in CASES}
    baseline = captures['baseline']['manifest']
    initial = document_without_view(baseline)
    edited = copy.deepcopy(initial)
    edited['arrangements'][0]['uses'][0]['addedLanes'][0]['notes'][0]['beat'] = 8.5
    moved = copy.deepcopy(initial)
    second = '43A25C07-B922-5276-B28F-1077A48B3791'
    moved['arrangements'][0]['layout']['positions'][second] = {'x': 724, 'y': 0}
    for name, (revision, layout, grid, snap) in CASES.items():
        capture = captures[name]; state = capture['state']; project = capture['manifest']
        assert state['projectID'] == '6BBB382F-9A63-50C0-B8C7-C18514A751FE'
        assert state['revision'] == project['musicRevision'] == revision, name
        assert (project['circleLayout'], project['album']['layout']['grid'], project['album']['layout']['snap']) == (layout, grid, snap), name
        assert state['view']['layout'] == layout and not state['dirty']
        assert state['output']['attempts'] == state['audition']['attempts'] == 0
        assert not state['recording']['busy'] and not state['recording']['midi'] and not state['playback']['playing']
        assert state['runtime']['bundleID'] == 'com.circlr.integrationqa'
        assert state['library']['folders'] == 1
        expected = edited if name in ['midi-view-changed', 'midi-redone'] else moved if name == 'circle-moved' else initial
        assert document_without_view(project) == expected, name
        assert capture['beforeSave']['dirty'] == (name not in ['baseline', 'reopened', 'restored']), name
    before = json.loads((OUT / 'restored-before-ui-save.json').read_text())
    assert before['state']['dirty'] and before['state']['revision'] == 19
    assert '일치하는 명령이 없습니다' in (OUT / 'view-only-no-undo.ax.txt').read_text()
    assert 'button (selected) 다시 실행, ⇧⌘Z' in (OUT / 'redo-retained.ax.txt').read_text()
    for name in ['midi-edited', 'midi-view-changed', 'midi-redone']:
        field(name, 'MIDI 시작 박', '9.5'); field(name, 'MIDI 길이 박', '0.5')
    for name in ['midi-undone', 'redo-retained']:
        field(name, 'MIDI 시작 박', '1'); field(name, 'MIDI 길이 박', '0.5')
    assert '피아노 롤 · Tab 노트 선택' in (OUT / 'midi-undone.ax.txt').read_text()
    assert 'MIDI 궤도 편집기' in (OUT / 'midi-redone.ax.txt').read_text()

    fixture = Path(captures['restored']['state']['path']); source = fixture.with_name('studio.circlr')
    assert digest(source / 'manifest.json') == '12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d'
    final = json.loads((fixture / 'manifest.json').read_text())
    assert final == captures['restored']['manifest']
    assert document_without_view(final) == initial
    for asset in initial['assets']:
        for folder in [source, fixture]:
            assert digest(folder / asset['path']) == asset['checksum']
    app = OUT / '써클러 통합 검증.app'
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    assert (info['CFBundleVersion'], info['CFBundleShortVersionString'], info['CFBundleIdentifier']) == ('56', '0.20.0', 'com.circlr.integrationqa')
    sections = runpy.run_path(str(ROOT / 'qa/check-library-evidence.py'))['sections']
    compiled = sections(ROOT / '.build/integration-release/release/circlr')
    assert len(compiled) == 37 and compiled == sections(app / 'Contents/MacOS/circlr')
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    sources = json.loads((OUT / 'source-hashes.json').read_text()); assert len(sources) == 5
    for name, expected in sources.items():
        assert digest(ROOT / name) == expected
    kit = app / 'Contents/Resources/Codex'
    files = json.loads((kit / 'manifest.json').read_text())['files']; assert len(files) == 25
    for name, expected in files.items():
        assert digest(kit / name) == expected
    assert 'Executed 413 tests, with 0 failures' in (ROOT / '.build/view-history-fixed-tests.log').read_text()
    assert 'Ran 26 tests' in (ROOT / '.build/view-history-python.log').read_text()
    preserve = json.loads((OUT / 'preservation.json').read_text())
    assert preserve['ownedQAProcesses'] == [] and preserve['userApp'] == ['0.19.0', '21']
    assert set(preserve['heads'].values()) == {'d88ea5d8d5d87cf49c5ef06154397c36ba1019d7', '1d304eb244f60a21c3598b89d05192d3512d719d'}
    screenshots = {p.name: digest(p) for p in sorted(OUT.glob('*.jpg'))}
    assert len(screenshots) == 12 and len(list(OUT.glob('*.ax.txt'))) == 13
    result = dict(status='passed', revision=19, nativeSnapshots=12, axCaptures=13, screenshots=screenshots,
                  sourceFiles=5, kitFiles=25, executableSections=37, physicalAudioAttempts=0)
    (OUT / 'verification.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({k: v for k, v in result.items() if k != 'screenshots'}, ensure_ascii=False))
