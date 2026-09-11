#!/usr/bin/env python3
"""Verify build 38 local native evidence, authored audio and final package provenance."""
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
OUT = ROOT / 'qa/generated/audio-workspace'
FINAL = OUT / 'readable'
PROJECT = '74FCAE6F-29F8-597B-A5FE-2A095681E4F3'
LANE = '7F32786A-C5A8-5B33-BEA3-0D5D029F3C14'
KEYS = ['global', 'tracks', 'sections', 'arrangements', 'assets', 'patterns', 'portLayout', 'circleLayout']


def read(name):
    return json.loads((OUT / (name + '.json')).read_text())


def capture(name, revision):
    d = read(name)
    s = d['state']
    assert s['projectID'] == PROJECT and s['revision'] == revision
    assert s['runtime']['bundleID'] == 'com.circlr.integrationqa'
    assert not s['dirty'] and not s['recording']['busy'] and not s['recording']['midi']
    assert not s['playback'].get('playing', False) and s['output']['attempts'] == 0
    return d


def use(d):
    return d['manifest']['arrangements'][0]['uses'][0]


def clips(d):
    return use(d)['laneOverrides'][LANE]['audio']


def ax(name):
    return (OUT / ('final-' + name + '-ax.txt')).read_text()


def main():
    before = capture('before', 14)
    chain = capture('final-ordered-input', 40)
    value = clips(chain)[0]
    assert (value['sourceStart'], value['duration'], value['fadeIn'], value['fadeOut'], value['sourceBPM']) == (8, 8, .1, .2, 100)
    assert math.isclose(value['gain'], 10 ** (-6 / 20), abs_tol=1e-12)
    linear = capture('final-linear-trim', 42)
    precise = capture('final-precision-preserved', 42)
    assert precise['manifest'] == linear['manifest']
    raw = clips(linear)[0]
    assert math.isclose(raw['sourceStart'], 9.031723049869933, abs_tol=1e-10)
    assert raw['sourceStart'] + raw['duration'] == 16
    assert 'Value: 9.032' in ax('precision-preserved')
    assert 'Value: 8.010' in ax('trim-undo') and 'MCP 연결 가능 r43' in ax('trim-undo')
    orbit = capture('final-orbit', 44)
    trimmed = capture('final-orbit-trim', 45)
    assert clips(orbit)[0]['sourceStart'] == 8.01 and clips(orbit)[0]['followsTempo']
    assert math.isclose(clips(trimmed)[0]['duration'], 6.982094858761899, abs_tol=1e-10)
    assert clips(trimmed)[0]['sourceStart'] == 8.01
    for name in ['ordered-input', 'linear-trim', 'precision-preserved', 'orbit', 'orbit-trim']:
        assert '원본 표시 7.360부터 16.640초' in ax(name)
        assert '편집기' in ax(name).split('The focused UI element is')[-1]
    for d in [linear, orbit, trimmed]:
        assert d['state']['playback']['editorFrame'] == chain['state']['playback']['editorFrame']
    invalid = capture('final-invalid-tab', 45)
    assert invalid['manifest'] == trimmed['manifest']
    assert '입력 범위:' in ax('invalid-tab') and 'ms' in ax('invalid-tab')
    assert '오디오 페이드 인 ms' in ax('invalid-tab').split('The focused UI element is')[-1]
    assert '편집 대상이 변경되었습니다' in ax('stale-rejected')
    assert '오디오 볼륨 dB' in ax('stale-rejected').split('The focused UI element is')[-1]
    split = capture('final-split', 47)
    left, right = clips(split)
    assert left['duration'] == 2 and right['sourceStart'] == 10.01
    assert math.isclose(left['duration'] + right['duration'], clips(trimmed)[0]['duration'], abs_tol=1e-12)
    assert left['renderWindow'] == right['renderWindow']
    assert left['renderWindow']['envelopes'][0]['fadeIn'] == .3
    assert right['renderWindow']['envelopes'][0]['fadeOut'] == .4
    assert right['gain'] == value['gain']  # The stale -9 dB draft never applied.
    duplicate = capture('final-duplicate', 48)
    first, second, third = clips(duplicate)
    assert [first, second] == [left, right] and len({c['id'] for c in clips(duplicate)}) == 3
    assert third['sourceStart'] == right['sourceStart'] and third['duration'] == right['duration']
    assert math.isclose(third['beat'], right['beat'] + right['duration'] / 1.2 * 2, abs_tol=1e-10)
    for d in [chain, linear, orbit, trimmed, split, duplicate]:
        p, original = d['manifest'], before['manifest']
        for key in ['global', 'tracks', 'sections', 'assets', 'patterns']:
            assert p[key] == original[key], key
        assert p['arrangements'][0]['uses'][1] == original['arrangements'][0]['uses'][1]
        assert use(d)['addedLanes'] == use(before)['addedLanes']
    bounced = capture('final-bounce', 49)
    restored_bounce = capture('final-bounce-restored', 50)
    node_id = bounced['state']['selection']['music']['nodeID']
    graph = use(restored_bounce)['graphEdits']
    node = next(n for n in graph['addedNodes'] if n['id'] == node_id)
    assert node['muted'] and 'bounce' not in node
    assert not any(e['from'] == node_id for e in graph['addedEdges'])
    assert len(bounced['manifest']['assets']) == len(before['manifest']['assets']) + 1
    for name, revision in [('first-restored', 34), ('final-before', 34), ('final-restored', 66), ('final-reopened', 66)]:
        d = capture(name, revision)
        for key in KEYS:
            assert d['manifest'].get(key) == before['manifest'].get(key), (name, key)
    source = Path.home() / 'Library/Application Support/circlr-integration-qa/fixtures/studio.circlr'
    assert hashlib.sha256((source / 'manifest.json').read_bytes()).hexdigest() == '12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d'
    for asset in before['manifest']['assets']:
        for folder in [source, source.with_name('audio-workspace.circlr')]:
            assert hashlib.sha256((folder / asset['path']).read_bytes()).hexdigest() == asset['checksum']
    wav = OUT / 'bounce.wav'
    assert hashlib.sha256(wav.read_bytes()).hexdigest() == read('bounce-asset')['sha256']
    with wave.open(str(wav), 'rb') as f:
        assert (f.getnchannels(), f.getframerate(), f.getsampwidth(), f.getnframes()) == (2, 48000, 3, 1632000)
        pcm = f.readframes(f.getnframes())
    peak, energy, nonzero = 0, 0, 0
    for i in range(0, len(pcm), 3):
        v = int.from_bytes(pcm[i:i + 3], 'little', signed=True)
        peak = max(peak, abs(v)); energy += v * v; nonzero += v != 0
    rms = math.sqrt(energy / (len(pcm) // 3)) / 2**23
    assert 0 < rms < peak / 2**23 < 1 and nonzero == read('bounce-pcm')['nonzeroSamples']
    app = FINAL / '써클러 통합 검증.app'
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    assert info['CFBundleVersion'] == '38' and info['CFBundleIdentifier'] == 'com.circlr.integrationqa'
    sections = runpy.run_path(str(ROOT / 'qa/check-library-evidence.py'))['sections']
    compiled = sections(ROOT / '.build/integration-release/release/circlr')
    assert compiled == sections(app / 'Contents/MacOS/circlr')
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    hashes = json.loads((FINAL / 'source-hashes.json').read_text())
    for name, digest in hashes.items():
        assert hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == digest
    kit = app / 'Contents/Resources/Codex'
    files = json.loads((kit / 'manifest.json').read_text())['files']
    for name, digest in files.items():
        assert hashlib.sha256((kit / name).read_bytes()).hexdigest() == digest
    assert 'Executed 325 tests, with 0 failures' in (OUT / 'swift-tests-final.log').read_text()
    assert 'Ran 26 tests' in (OUT / 'python-tests.log').read_text()
    screenshots = {}
    for name in ['ordered-input', 'linear-trim', 'precision-preserved', 'trim-undo', 'orbit', 'orbit-trim', 'invalid-tab', 'stale-rejected', 'split', 'duplicate', 'bounce', 'bounce-restored']:
        path = OUT / ('final-' + name + '.jpg'); raw = path.read_bytes()
        assert raw[:3] == b'\xff\xd8\xff'
        metadata = subprocess.check_output(['sips', '-g', 'pixelWidth', '-g', 'pixelHeight', str(path)], text=True)
        size = [int(re.search(label + r': (\d+)', metadata)[1]) for label in ['pixelWidth', 'pixelHeight']]
        assert size == [1019, 768]
        screenshots[name] = dict(size=size, sha256=hashlib.sha256(raw).hexdigest())
    result = dict(result='passed', revision=66, sourceFiles=len(hashes), kitFiles=len(files),
                  fileBackedSections=len(compiled), screenshots=screenshots, bounceSeconds=34,
                  scope='Native audio editing and offline rendering; no physical output or microphone',
                  uuid=subprocess.check_output(['dwarfdump', '--uuid', str(app / 'Contents/MacOS/circlr')], text=True).strip())
    (FINAL / 'verification.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({k: v for k, v in result.items() if k != 'screenshots'}, ensure_ascii=False))


if __name__ == '__main__':
    main()
