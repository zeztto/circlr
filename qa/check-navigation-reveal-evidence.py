#!/usr/bin/env python3
"""Verify selection-only group reveal, edit history, restored focus and signed build 57."""
import copy
import hashlib
import json
from pathlib import Path
import plistlib
import runpy
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'qa/generated/navigation-reveal'
CASES = {'baseline': 14, 'navigation-audio': 14, 'audio-edited': 15, 'outside-output': 15,
         'audio-redone': 17, 'parent-collapsed': 18, 'explicit-open': 18, 'explicit-undone': 19,
         'orbit-before-focus': 19, 'agent-focused': 19, 'reopened-inside': 19, 'restored': 19,
         'ui-saved': 19, 'final-restored': 19}
ORBIT = {'orbit-before-focus', 'agent-focused', 'reopened-inside', 'ui-saved'}
CLEAN_BEFORE_SAVE = {'baseline', 'navigation-audio', 'outside-output', 'agent-focused', 'reopened-inside', 'ui-saved', 'final-restored'}
AUDIO_ID = 'DDB48BA6-04EC-5F78-8AB1-7CC61F46EAC7'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def document(project):
    value = copy.deepcopy(project)
    for key in ['musicRevision', 'hierarchyView', 'circleLayout']:
        value.pop(key, None)
    return value


def field(name, title, value):
    ax = (OUT / (name + '.ax.txt')).read_text()
    assert any('Description: ' + title + ', Help:' in line and line.endswith('Value: ' + value)
               for line in ax.splitlines()), (name, title, value)


if __name__ == '__main__':
    captures = {n: json.loads((OUT / (n + '.json')).read_text()) for n in CASES}
    initial = document(captures['baseline']['manifest'])
    edited = copy.deepcopy(initial)
    lane = copy.deepcopy(next(l for l in initial['sections'][0]['lanes'] if l['id'] == '7F32786A-C5A8-5B33-BEA3-0D5D029F3C14'))
    lane['audio'][0]['beat'] = 8.5
    edited['arrangements'][0]['uses'][0]['laneOverrides'][lane['id']] = lane
    opened = copy.deepcopy(initial)
    opened['arrangements'][0]['uses'][0]['graphEdits']['layout']['groups'][0]['collapsed'] = False
    for name, revision in CASES.items():
        capture = captures[name]; state = capture['state']; project = capture['manifest']
        assert state['projectID'] == '2CDF95C6-B58F-5C90-A6AE-EE96F03F0EE6'
        assert state['revision'] == project['musicRevision'] == revision, name
        assert project['circleLayout'] == state['view']['layout'] == ('orbit' if name in ORBIT else 'freeform'), name
        assert not state['dirty'] and capture['beforeSave']['dirty'] == (name not in CLEAN_BEFORE_SAVE), name
        assert state['output']['attempts'] == state['audition']['attempts'] == 0
        assert not state['recording']['busy'] and not state['recording']['midi'] and not state['playback']['playing']
        assert state['runtime']['bundleID'] == 'com.circlr.integrationqa' and state['library']['folders'] == 1
        expected = edited if name in ['audio-edited', 'outside-output', 'audio-redone'] else opened if name == 'explicit-open' else initial
        assert document(project) == expected, name
    for name in ['navigation-audio', 'agent-focused', 'reopened-inside']:
        assert captures[name]['state']['selection']['music']['nodeID'] == AUDIO_ID
    for name in ['parent-collapsed', 'explicit-undone', 'final-restored']:
        assert captures[name]['state']['selection']['group']['id'] == '5B2E59F8-3337-5ABA-A844-4DCD09A2FFB6'
    assert captures['agent-focused']['manifest']['hierarchyView'] == captures['reopened-inside']['manifest']['hierarchyView']
    for name, visible in [('inside-scene', True), ('outside-scene', False), ('other-use-scene', False)]:
        scene = json.loads((OUT / (name + '.json')).read_text())['circles']
        assert any(c['address'].get('music', {}).get('nodeID') == AUDIO_ID for c in scene) == visible, name
    invalid = json.loads((OUT / 'invalid-focus.json').read_text())
    assert '이 서클은 현재 편곡에서 사용할 수 없습니다' in invalid['error']
    for key in ['projectID', 'revision', 'dirty', 'selection', 'album', 'view']:
        assert invalid['before'][key] == invalid['after'][key]
    before_save = json.loads((OUT / 'before-ui-save.json').read_text())['state']
    assert before_save['dirty'] and before_save['revision'] == 19 and before_save['view']['layout'] == 'orbit'
    assert '0개 명령' in (OUT / 'navigation-no-undo.ax.txt').read_text()
    assert 'button (selected) 다시 실행, ⇧⌘Z' in (OUT / 'navigation-redo-retained.ax.txt').read_text()
    for name in ['audio-edited', 'audio-redone']:
        field(name, '오디오 배치 박', '9.5'); field(name, '오디오 원본 끝 초', '32.000')
    for name in ['navigation-audio', 'audio-undone', 'audio-restored', 'agent-focused-orbit', 'reopened-inside']:
        field(name, '오디오 배치 박', '1'); field(name, '오디오 원본 끝 초', '32.000')
    for name in ['parent-collapsed', 'explicit-undone', 'reopened-parent', 'final-restored']:
        assert 'button (selected) 신스 그룹 · 2개 서클 · 접힘' in (OUT / (name + '.ax.txt')).read_text()
    assert 'button (selected) 신스 그룹 · 2개 서클\n' in (OUT / 'explicit-open-settled.ax.txt').read_text()
    fixture = Path(captures['final-restored']['state']['path']); source = fixture.with_name('studio.circlr')
    assert digest(source / 'manifest.json') == '12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d'
    final = json.loads((fixture / 'manifest.json').read_text())
    assert final == captures['final-restored']['manifest'] and document(final) == initial
    for asset in initial['assets']:
        for folder in [source, fixture]:
            assert digest(folder / asset['path']) == asset['checksum']
    app = OUT / '써클러 통합 검증.app'
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    assert (info['CFBundleVersion'], info['CFBundleShortVersionString'], info['CFBundleIdentifier']) == ('57', '0.20.0', 'com.circlr.integrationqa')
    sections = runpy.run_path(str(ROOT / 'qa/check-library-evidence.py'))['sections']
    compiled = sections(ROOT / '.build/integration-release/release/circlr')
    assert len(compiled) == 37 and compiled == sections(app / 'Contents/MacOS/circlr')
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    sources = json.loads((OUT / 'source-hashes.json').read_text()); assert len(sources) == 8
    for name, expected in sources.items():
        assert digest(ROOT / name) == expected
    kit = app / 'Contents/Resources/Codex'
    files = json.loads((kit / 'manifest.json').read_text())['files']; assert len(files) == 25
    for name, expected in files.items():
        assert digest(kit / name) == expected
    assert 'Executed 419 tests, with 0 failures' in (ROOT / '.build/navigation-reveal-clean-tests.log').read_text()
    assert 'Ran 26 tests' in (ROOT / '.build/navigation-reveal-python.log').read_text()
    preserve = json.loads((OUT / 'preservation.json').read_text())
    assert preserve['ownedQAProcesses'] == [] and preserve['userApp'] == ['0.19.0', '21']
    assert set(preserve['heads'].values()) == {'d88ea5d8d5d87cf49c5ef06154397c36ba1019d7', '1d304eb244f60a21c3598b89d05192d3512d719d'}
    assert 'Executed 6 tests, with 0 failures' in (ROOT / '.build/navigation-reveal-final-tests.log').read_text()
    for path, head in preserve['heads'].items():
        assert subprocess.check_output(['git', '-C', path, 'rev-parse', 'HEAD'], text=True).strip() == head
    processes = [line for line in subprocess.check_output(['ps', '-axo', 'pid=,command='], text=True).splitlines()
                 if len(line.split(None, 1)) == 2 and line.split(None, 1)[1].startswith(str(ROOT / 'qa/generated') + '/')
                 and '/Contents/MacOS/circlr' in line]
    assert not processes
    screenshots = {p.name: digest(p) for p in sorted(OUT.glob('*.jpg'))}
    assert len(screenshots) == 19 and len(list(OUT.glob('*.ax.txt'))) == 19
    result = dict(status='passed', revision=19, nativeSnapshots=15, sceneChecks=3, invalidFocusChecks=1,
                  axCaptures=19, screenshots=screenshots, sourceFiles=8, kitFiles=25,
                  executableSections=37, physicalAudioAttempts=0)
    (OUT / 'verification.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({k: v for k, v in result.items() if k != 'screenshots'}, ensure_ascii=False))
