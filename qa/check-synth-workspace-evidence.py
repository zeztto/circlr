#!/usr/bin/env python3
"""Check saved build119 synth UI evidence without launching an app or calling MCP.

Image signature/dimensions prove artifact presence only, never visual quality or visibility.
The native screenshots require separate direct visual review.
"""
import copy
import importlib.util
import json
from pathlib import Path
import re
import struct

spec = importlib.util.spec_from_file_location('synth_package', Path(__file__).with_name('prepare-synth-workspace-qa.py'))
p = importlib.util.module_from_spec(spec)
spec.loader.exec_module(p)
D = p.OUT / 'final119'
TRACK = '7E0D9016-E91D-4325-B807-033F233E32EA'
REVISIONS = dict(before=14, navigated=14, cancelled=14, edited=15, restored=16,
                 **{'engine-one': 17, 'engine-two': 18, 'final-restored': 20, 'reopened': 20})


def read(name):
    return json.loads((D / (name + '.json')).read_text())


def music(manifest):
    return {k: v for k, v in manifest.items() if k not in ['musicRevision', 'layoutRevision', 'hierarchyView', 'modifiedAt']}


def synth(manifest):
    return next(t for t in manifest['tracks'] if t['id'] == TRACK)['instrument']['synth']


def main():
    package = read('package'); injection = read('qa-injection')
    scenario = json.loads((p.OUT / 'baseline/scenario.json').read_text())
    seed = json.loads((p.OUT / 'baseline/fixture-initial.json').read_text())
    assert package['build'] == '119' and package['projectID'] == p.PROJECT_ID
    assert package['fixture'] == str(p.FIXTURE)
    assert package['sourceSHA256'] == scenario['sourceSHA256'] == p.digest(p.SOURCE / 'manifest.json')
    app = D / '써클러 통합 검증.app'; macos = app / 'Contents/MacOS'
    assert package['app'] == str(app)
    assert p.digest(macos / 'circlr') == package['packagedMainSHA256']
    assert p.run(['dwarfdump', '--uuid', str(macos / 'circlr')]).split()[1] == package['sourceBinaryUUID'] == package['packagedMainUUID']
    # Verify exact original source binaries too; fail if a later build replaces this evidence source.
    for name, checksum in package['sourceBinarySHA256'].items():
        assert p.digest(Path(package['binaryDirectory']) / name) == checksum
    assert injection['qaOnlyMock'] and injection['denyAllAudioHelpers'] and injection['helperExit'] == 78
    assert injection['candidate'] == 'final119'
    assert set(injection['packagedHelperSHA256']) == set(p.HELPERS)
    for helper in p.HELPERS:
        assert p.digest(macos / helper) == injection['packagedHelperSHA256'][helper]
        assert injection['productionHelperSHA256'][helper] == package['sourceBinarySHA256'][helper]
        assert injection['packagedHelperSHA256'][helper] != injection['productionHelperSHA256'][helper]
    p.run(['codesign', '--verify', '--deep', '--strict', str(app)])
    resources = app / 'Contents/Resources/Codex'
    assert p.digest(resources / 'manifest.json') == package['codexManifestSHA256']
    for name, checksum in json.loads((resources / 'manifest.json').read_text())['files'].items():
        assert p.digest(resources / name) == checksum
    captures = {name: read(name) for name in REVISIONS}
    for name, capture in captures.items():
        state = capture['state']; manifest = capture['manifest']
        assert capture['saved'] and capture['packageBuild'] == '119'
        assert state['runtime']['build'] == '119' and state['runtime']['version'] == '0.20.0'
        assert state['runtime']['bundleID'] == 'com.circlr.integrationqa'
        assert state['projectID'] == manifest['id'] == p.PROJECT_ID and state['path'] == str(p.FIXTURE)
        assert state['revision'] == manifest['musicRevision'] == REVISIONS[name] and not state['dirty']
        assert state['output']['attempts'] == state['audition']['attempts'] == 0
        assert state['output']['phase'] == state['audition']['phase'] == 'idle'
        assert state['audition']['heldNotes'] == 0 and not state['playback']['playing']
        assert not any(state['recording'][k] for k in ['busy', 'audio', 'midi'])
        assert manifest['assets'] == seed['assets']
        p.assets(manifest, p.FIXTURE)
        assert state['selection']['music']['nodeID'] == p.NODE
    baseline = captures['before']['manifest']
    for name in ['navigated', 'cancelled', 'restored', 'final-restored', 'reopened']:
        assert music(captures[name]['manifest']) == music(baseline), name
    expected = copy.deepcopy(baseline)
    assert synth(expected)['motion'] == 0.55
    synth(expected)['motion'] = 0.7
    assert music(captures['edited']['manifest']) == music(expected)
    for name, engine in [('engine-one', 1), ('engine-two', 2)]:
        expected = copy.deepcopy(baseline)
        synth(expected).update(engineVersion=engine, voice=0)
        assert music(captures[name]['manifest']) == music(expected)
    assert synth(captures['final-restored']['manifest'])['engineVersion'] == 3
    assert synth(captures['final-restored']['manifest'])['voice'] == 6
    disk = json.loads((p.FIXTURE / 'manifest.json').read_text())
    assert captures['final-restored']['manifest'] == captures['reopened']['manifest'] == disk
    assert synth(captures['cancelled']['manifest'])['cutoff'] == 10000
    chains = {
        'tab-chain': ['0', '0.003', '2.8', '0.08', '0.3', '0.12', '0.65', '0', '0.6', '0.55'],
        'reverse-chain': ['0.6', '0', '0.65', '0.12', '0.3', '0.08', '2.8', '0.003', '0', '10000'],
        'engine-one-chain': ['0', '0.003', '2.8', '0.08', '0.3'],
        'engine-two-chain': ['0', '0.003', '2.8', '0.08', '0.3', '0.12', '0.65', '0'],
    }
    for name, expected in chains.items():
        text = (D / (name + '.ax.txt')).read_text()
        assert re.findall(r'Selected text: ```\n(.*?)\n```', text, re.S) == expected, name
        if name != 'reverse-chain':
            assert re.search(r'The focused UI element.*Description: 필터 Hz,.*Value: 10000(?:\n|$)', text)
    draft = (D / 'draft-resized.ax.txt').read_text()
    assert re.search(r'The focused UI element.*Description: 필터 Hz,.*Value: 1000\.(?:\n|$)', draft)
    images = ['before', 'draft-resized', 'edited', 'engine-one', 'engine-two', 'final-restored', 'reopened', 'tab-first', 'tab-last']
    formats = {}
    for name in images:
        raw = (D / (name + '.jpg')).read_bytes()
        if raw[:8] == b'\x89PNG\r\n\x1a\n':
            assert raw[12:16] == b'IHDR'
            dimensions = struct.unpack('>II', raw[16:24]); kind = 'PNG'
        else:
            # Inspect actual capture bytes; filenames do not establish encoding.
            assert raw[:2] == b'\xff\xd8' and raw[-2:] == b'\xff\xd9'
            offset = 2; dimensions = None; kind = 'JPEG'
            while offset < len(raw):
                assert raw[offset] == 0xff
                while raw[offset] == 0xff: offset += 1
                marker = raw[offset]; offset += 1
                if marker in [0xd9, 0xda]: break
                length = struct.unpack('>H', raw[offset:offset + 2])[0]
                assert length >= 2 and offset + length <= len(raw)
                if marker in [0xc0, 0xc1, 0xc2]:
                    height, width = struct.unpack('>HH', raw[offset + 3:offset + 7])
                    dimensions = (width, height); break
                offset += length
            assert dimensions is not None
        assert all(dimension > 0 for dimension in dimensions)
        formats[name] = dict(format=kind, width=dimensions[0], height=dimensions[1])
    print(json.dumps(dict(status='PASS', build='119', snapshots=len(captures), axChains=len(chains),
        imageArtifacts=formats, revisions=REVISIONS, physicalAudioAttempts=0,
        visualScope='Image headers and dimensions only. Separate direct screenshot review is required.',
        limitations='Selected-value chains verify captured ordering; they do not independently prove pixel visibility or physical audio.'), ensure_ascii=False))


if __name__ == '__main__':
    main()
