#!/usr/bin/env python3
"""Check build 40's local native evidence, restoration and package provenance.

Requires the authored fixture run; this is not a portable CI UI test.
"""
import hashlib
import json
import math
from pathlib import Path
import plistlib
import re
import runpy
import subprocess
import wave

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'qa/generated/transition-effects'
FINAL = OUT / 'readable'
PROJECT = '0457F1E3-F712-52CC-90FA-EA30A2DF4CD3'
GLOBAL = '50AD093E-9B39-5EBF-87E4-88E47DDE0978'
TRACK = '7E0D9016-E91D-4325-B807-033F233E32EA'
CIRCLE = '8656DC5C-4A33-4CE8-A3BD-AC14DA82A905'
KEYS = ['global', 'tracks', 'sections', 'arrangements', 'assets', 'patterns', 'portLayout', 'circleLayout', 'signal']


def read(name):
    return json.loads((OUT / (name + '.json')).read_text())


def capture(name, revision):
    data = read(name)
    state = data['state']
    assert state['projectID'] == PROJECT and state['revision'] == revision, name
    assert state['runtime']['bundleID'] == 'com.circlr.integrationqa'
    assert not state['dirty'] and not state['recording']['busy'] and not state['recording']['midi']
    assert not state['playback'].get('playing', False) and state['output']['attempts'] == 0
    return data['manifest']


def transition(manifest):
    return manifest['arrangements'][0]['edges'][0]['transition']


def global_effect(manifest):
    return next(n['effect'] for n in manifest['signal']['nodes'] if n['id'] == GLOBAL)


def ax(name):
    return (OUT / ('final-' + name + '-ax.txt')).read_text()


def main():
    before = capture('before', 14)
    numbers = transition(capture('final-transition-numbers', 34))
    assert (numbers['anchor'], numbers['length'], numbers['mode']) == ('sourceBars', 1.5, 'within')
    assert math.isclose(numbers['effect']['amount'], 10 ** (-6 / 20), abs_tol=1e-12)
    precision = transition(capture('final-precision-after', 42))['effect']
    assert precision['kind'] == 'delay' and precision['amount'] == numbers['effect']['amount']
    assert 'Value: 516.152' in ax('precision-after')
    edited = capture('final-delay-tab', 44)
    effect = transition(edited)['effect']
    assert effect['kind'] == 'delay' and math.isclose(30 + 970 * effect['amount'], 400, abs_tol=1e-12)
    assert effect['secondary'] == .35
    stale = capture('final-stale-restored', 46)
    assert transition(stale) == transition(edited) and stale['global'] == before['global']
    gain = global_effect(capture('final-global-gain', 47))
    assert gain['kind'] == 'gain' and math.isclose(gain['amount'], 10 ** (-3 / 20), abs_tol=1e-12)
    reverb = global_effect(capture('final-global-reverb', 52))
    assert reverb == dict(kind='reverb', amount=.45, secondary=.30)
    added = capture('circle-added', 53)
    music = capture('final-circle-tab', 55)
    nodes = music['arrangements'][0]['uses'][0]['graphEdits']['addedNodes']
    compressor = next(n['content']['effect']['_0'] for n in nodes if n['id'] == CIRCLE)
    assert compressor == dict(kind='compressor', amount=.3, secondary=.4)
    assert music['arrangements'][0]['uses'][0]['addedLanes'] == before['arrangements'][0]['uses'][0]['addedLanes']
    assert len(nodes) == len(added['arrangements'][0]['uses'][0]['graphEdits']['addedNodes'])
    within = transition(capture('final-within-replace', 57))
    assert within['mode'] == 'within' and within['replaceTrackID'] == TRACK and within['effect'] == effect
    overlap = transition(capture('settled-overlap', 83))
    assert (overlap['mode'], overlap['anchor'], overlap['length']) == ('overlap', 'targetBars', 1.5)
    insert = transition(capture('settled-insert-rhythm', 85))
    assert insert['mode'] == 'insert' and insert['patternID'] in {p['id'] for p in before['patterns']}
    for name, revision in [('first-restored', 32), ('final-before', 32), ('final-restored', 80),
                           ('final-reopened', 80), ('settled-restored', 90), ('settled-reopened', 90)]:
        data = capture(name, revision)
        for key in KEYS:
            assert data.get(key) == before.get(key), (name, key)
    for name, count in [('final-restoration-log', 23), ('settled-restoration-log', 5)]:
        log = read(name)
        assert len(log) == count + 1 and log[-1]['changed'] == []
    for name in ['returned', 'transition-numbers', 'delay-tab', 'global-gain', 'global-reverb', 'circle-tab', 'within-replace']:
        assert '앨범 서클 캔버스' in ax(name).split('The focused UI element is')[-1], name
    assert '전환 4.500초' in ax('transition-numbers')
    assert '전환 3.281초' in ax('settled-target-bars')
    assert '3.281초 먼저' in ax('settled-overlap') and 'Description: 효과,' not in ax('settled-overlap')
    assert '3.281초 늦게' in ax('settled-insert-empty') and 'Description: 효과,' not in ax('settled-insert-empty')
    assert '삽입하는 리듬에 적용' in ax('settled-insert-rhythm') and 'Description: 효과,' in ax('settled-insert-rhythm')
    assert '선택 트랙의 전환 구간을 비웁니다' in ax('within-replace') and 'Description: 효과,' not in ax('within-replace')
    assert '입력 범위: 30–1000 ms' in ax('invalid-tab')
    assert '편집 대상이 변경되었습니다' in ax('stale-rejected')
    assert '전환 재생 불가' in ax('invalid-overlap')
    source = Path.home() / 'Library/Application Support/circlr-integration-qa/fixtures/studio.circlr'
    assert hashlib.sha256((source / 'manifest.json').read_bytes()).hexdigest() == '12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d'
    for asset in before['assets']:
        for folder in [source, source.with_name('transition-effects.circlr')]:
            assert hashlib.sha256((folder / asset['path']).read_bytes()).hexdigest() == asset['checksum']
    export = read('export-terminal')
    assert export['job']['state'] == 'completed' and export['revision'] == 46
    pcm = read('export-pcm')
    wav = OUT / 'transition-master.wav'
    assert hashlib.sha256(wav.read_bytes()).hexdigest() == pcm['sha256']
    with wave.open(str(wav)) as audio:
        assert (audio.getnchannels(), audio.getframerate(), audio.getsampwidth(), audio.getnframes()) == (2, 48000, 3, 3504000)
    assert 0 < pcm['rms'] < pcm['peak'] < 1 and pcm['nonzero'] > 0
    app = FINAL / '써클러 통합 검증.app'
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    assert (info['CFBundleVersion'], info['CFBundleShortVersionString'], info['CFBundleIdentifier']) == ('40', '0.20.0', 'com.circlr.integrationqa')
    sections = runpy.run_path(str(ROOT / 'qa/check-library-evidence.py'))['sections']
    compiled = sections(ROOT / '.build/integration-release/release/circlr')
    assert len(compiled) == 37 and compiled == sections(app / 'Contents/MacOS/circlr')
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    hashes = json.loads((FINAL / 'source-hashes.json').read_text())
    assert len(hashes) == 11
    for name, digest in hashes.items():
        assert hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == digest, name
    kit = app / 'Contents/Resources/Codex'
    files = json.loads((kit / 'manifest.json').read_text())['files']
    assert len(files) == 25
    for name, digest in files.items():
        assert hashlib.sha256((kit / name).read_bytes()).hexdigest() == digest
    assert 'Executed 330 tests, with 0 failures' in (OUT / 'swift-tests-final.log').read_text()
    python_log = (OUT / 'python-tests.log').read_text()
    assert 'Ran 26 tests' in python_log and '\nOK\n' in python_log
    screenshots = {}
    for path in sorted(OUT.glob('final-*.jpg')):
        raw = path.read_bytes()
        assert raw[:3] == b'\xff\xd8\xff'
        metadata = subprocess.check_output(['sips', '-g', 'pixelWidth', '-g', 'pixelHeight', str(path)], text=True)
        size = [int(re.search(label + r': (\d+)', metadata)[1]) for label in ['pixelWidth', 'pixelHeight']]
        assert size == [1019, 768], path.name
        screenshots[path.name] = dict(size=size, sha256=hashlib.sha256(raw).hexdigest())
    assert len(screenshots) == 27
    result = dict(result='passed', restoredRevision=90, sourceFiles=len(hashes), kitFiles=len(files),
                  fileBackedSections=len(compiled), screenshots=screenshots, exportSeconds=73,
                  scope='Native transition/effect editing and restoration; no device playback or capture. Settled captures supersede immediate post-menu captures.',
                  uuid=subprocess.check_output(['dwarfdump', '--uuid', str(app / 'Contents/MacOS/circlr')], text=True).strip())
    (FINAL / 'verification.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({k: v for k, v in result.items() if k != 'screenshots'}, ensure_ascii=False))


if __name__ == '__main__':
    main()
