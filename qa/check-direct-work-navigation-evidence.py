#!/usr/bin/env python3
"""Check exact navigation targets, music preservation, native filtering and build 59 package."""
import copy
import hashlib
import json
from pathlib import Path
import plistlib
import runpy
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'qa/generated/direct-work-navigation'
CASES = {'baseline': 15, 'direct-effect': 15, 'effect-edited': 16, 'direct-delay': 16,
         'effect-undone': 17, 'hidden-audio': 17, 'effect-redone': 18, 'direct-midi': 19,
         'empty-section': 19, 'long-section': 19, 'repeat-audio': 19, 'cache-renamed': 20,
         'cache-undone': 21, 'restored': 21, 'reopened': 21}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def document(value):
    value = copy.deepcopy(value)
    value.pop('musicRevision'); value.pop('hierarchyView')
    return value


def ax(name):
    return (OUT / (name + '.ax.txt')).read_text()


if __name__ == '__main__':
    captures = {n: json.loads((OUT / (n + '.json')).read_text()) for n in CASES}
    initial = document(captures['baseline']['manifest'])
    uses = initial['arrangements'][0]['uses']
    assert len(uses) == 13 and len(initial['sections']) == 2
    assert len(initial['tracks']) == 3 and len(initial['assets']) == 2
    assert initial['sections'][1]['lanes'] == [] and initial['sections'][1]['graph']['nodes'] == []
    effects = [n for n in uses[0]['graphEdits']['addedNodes'] if 'effect' in n['content']]
    assert len(effects) == 2 and all(n['name'] == 'Nordic 공간' for n in effects)
    reverb = next(n['id'] for n in effects if n['content']['effect']['_0']['kind'] == 'reverb')
    delay = next(n['id'] for n in effects if n['content']['effect']['_0']['kind'] == 'delay')
    edited = copy.deepcopy(initial); renamed = copy.deepcopy(initial)
    next(n for n in edited['arrangements'][0]['uses'][0]['graphEdits']['addedNodes'] if n['id'] == reverb)['content']['effect']['_0']['amount'] = 0.37
    next(n for n in renamed['arrangements'][0]['uses'][0]['graphEdits']['addedNodes'] if n['id'] == reverb)['name'] = '별빛 잔향'
    dirty_before = {'baseline', 'effect-edited', 'effect-undone', 'effect-redone', 'direct-midi', 'cache-renamed', 'cache-undone'}
    for name, revision in CASES.items():
        capture = captures[name]; state = capture['state']; project = capture['manifest']
        assert state['projectID'] == '94B5FD4A-2E8F-5508-BDD7-3B3D266AFEAC'
        assert state['revision'] == project['musicRevision'] == revision, name
        assert not state['dirty'] and capture['beforeSave']['dirty'] == (name in dirty_before), name
        assert state['output']['attempts'] == state['audition']['attempts'] == 0
        assert not state['recording']['busy'] and not state['recording']['midi'] and not state['playback']['playing']
        assert state['runtime']['bundleID'] == 'com.circlr.integrationqa' and state['library']['folders'] == 1
        assert project['circleLayout'] == 'freeform' and state['view']['consoleOpen']
        expected = edited if name in ['effect-edited', 'direct-delay', 'effect-redone'] else renamed if name == 'cache-renamed' else initial
        assert document(project) == expected, name  # Includes all other uses, source graphs, assets and view preferences.
    for name, target, use in [('direct-effect', reverb, uses[0]), ('direct-delay', delay, uses[0]),
                              ('hidden-audio', 'DDB48BA6-04EC-5F78-8AB1-7CC61F46EAC7', uses[0]),
                              ('repeat-audio', 'DDB48BA6-04EC-5F78-8AB1-7CC61F46EAC7', uses[11]),
                              ('direct-midi', 'midi:055F3787-2B9D-4DD1-9752-56106F8D94F5', uses[0])]:
        selected = captures[name]['state']['selection']['music']
        assert selected['nodeID'] == target and selected['useID'] == use['id'], name
    assert captures['empty-section']['state']['selection']['section']['useID'] == uses[12]['id']
    assert captures['long-section']['state']['selection']['section']['useID'] == uses[11]['id']
    assert captures['restored']['manifest'] == captures['reopened']['manifest']
    assert '137개 결과' in ax('navigation-open') and 'container 앨범 서클 캔버스' not in ax('navigation-open')
    assert '0개 결과' in ax('no-results') and '일치하는 작업이 없습니다' in ax('no-results')
    assert 'button (selected) 검증 톤 2 · 오디오' in ax('current-restored')
    assert '2개 결과' in ax('effect-results') and '이펙트 1/2' in ax('effect-results') and '이펙트 2/2' in ax('effect-results')
    assert '2 · 출력 2' in ax('effect-results') and '1 · 출력 1' not in ax('effect-results')
    assert 'Description: 효과, Value: Reverb' in ax('effect-open')
    assert 'Description: 효과, Value: Delay' in ax('delay-open')
    assert any('Description: 공간 크기 · %' in line and line.endswith('Value: 37') for line in ax('effect-edited').splitlines())
    for label in ['이 섹션', '이펙트']:
        assert 'button (selected) '+label in ax('route-filtered')
    assert '2개 결과' in ax('route-filtered') and 'button 트랙 제한 해제' in ax('route-filtered')
    assert '4개 결과' in ax('track-unrestricted') and 'button 트랙 제한 해제' not in ax('track-unrestricted')
    for label in ['이 섹션', 'MIDI']:
        assert 'button (selected) '+label in ax('midi-filter')
    assert '1개 결과' in ax('midi-filter') and '스텝 편집기' in ax('midi-open')
    assert '1개 결과' in ax('empty-section-result') and '비어 있는 브리지 · 섹션' in ax('empty-section-result')
    assert '2개 결과' in ax('long-sections') and '› 11 ·' in ax('long-sections') and '› 12 ·' in ax('long-sections')
    assert '2개 결과' in ax('repeat-audio-filter') and '› 12 ·' in ax('repeat-audio-filter')
    assert '4개 결과' in ax('cache-before') and '2개 결과' in ax('cache-refreshed') and '4개 결과' in ax('cache-restored')
    for name in ['route-filtered', 'midi-filter', 'repeat-audio-filter', 'track-unrestricted']:
        assert 'The focused UI element is 5 search text field' in ax(name), name
    assert '오디오 파형 편집기' in ax('reopened')
    fixture = Path(captures['reopened']['state']['path']); source = fixture.with_name('studio.circlr')
    assert json.loads((fixture / 'manifest.json').read_text()) == captures['reopened']['manifest']
    assert digest(source / 'manifest.json') == '12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d'
    for asset in initial['assets']:
        for folder in [source, fixture]:
            assert digest(folder / asset['path']) == asset['checksum']
    app = OUT / '써클러 통합 검증.app'; info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    assert (info['CFBundleVersion'], info['CFBundleShortVersionString'], info['CFBundleIdentifier']) == ('59', '0.20.0', 'com.circlr.integrationqa')
    sections = runpy.run_path(str(ROOT / 'qa/check-library-evidence.py'))['sections']
    compiled = sections(ROOT / '.build/integration-release/release/circlr')
    assert len(compiled) == 37 and compiled == sections(app / 'Contents/MacOS/circlr')
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    sources = json.loads((OUT / 'source-hashes.json').read_text()); assert len(sources) == 5
    for name, expected in sources.items():
        assert digest(ROOT / name) == expected
    kit = app / 'Contents/Resources/Codex'; files = json.loads((kit / 'manifest.json').read_text())['files']
    assert len(files) == 25
    for name, expected in files.items():
        assert digest(kit / name) == expected
    for log, count in [('direct-work-navigation-tests.log', 429), ('direct-work-navigation-final-tests.log', 6)]:
        assert 'Executed '+str(count)+' tests, with 0 failures' in (ROOT / '.build' / log).read_text()
    assert 'Ran 26 tests' in (ROOT / '.build/direct-work-navigation-python.log').read_text()
    preserve = json.loads((OUT / 'preservation.json').read_text())
    assert preserve['ownedQAProcesses'] == [] and preserve['userApp'] == ['0.19.0', '21']
    assert set(preserve['heads'].values()) == {'d88ea5d8d5d87cf49c5ef06154397c36ba1019d7', '1d304eb244f60a21c3598b89d05192d3512d719d'}
    for path, head in preserve['heads'].items():
        assert subprocess.check_output(['git', '-C', path, 'rev-parse', 'HEAD'], text=True).strip() == head
    processes = [line for line in subprocess.check_output(['ps', '-axo', 'pid=,command='], text=True).splitlines()
                 if len(line.split(None, 1)) == 2 and line.split(None, 1)[1].startswith(str(ROOT / 'qa/generated') + '/')
                 and '/Contents/MacOS/circlr' in line]
    assert not processes
    screenshots = {p.name: digest(p) for p in sorted(OUT.glob('*.jpg'))}
    assert len(screenshots) == len(list(OUT.glob('*.ax.txt'))) == 22
    result = dict(status='passed', nativeSnapshots=len(CASES), sectionUses=13, destinations=137, axCaptures=22,
                  screenshots=screenshots, sourceFiles=5, kitFiles=25, executableSections=37, physicalAudioAttempts=0)
    (OUT / 'verification.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({k: v for k, v in result.items() if k != 'screenshots'}, ensure_ascii=False))
