#!/usr/bin/env python3
"""Verify recorded source-circle QA evidence without changing the app or project."""
from pathlib import Path
import hashlib
import importlib.util
import json
import plistlib
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'qa/generated/source-circles'
FIELDS = ['name', 'tracks', 'assets', 'sections', 'arrangements', 'signal', 'patterns', 'portLayout']


def read(name):
    return json.loads((OUT / (name + '.json')).read_text())


def edits(record):
    return record['manifest']['arrangements'][0]['uses'][0]['graphEdits']


def music_equal(a, b):
    for field in FIELDS:
        assert a[field] == b[field], field


def main():
    before, batch = read('before'), read('batch')
    old = {n['id'] for n in edits(before)['addedNodes']}
    added = [n for n in edits(batch)['addedNodes'] if n['id'] not in old]
    assert len(added) == 8
    assert sorted(next(iter(n['content'])) for n in added) == sorted(['audio', 'mix', 'rhythmAudio', 'output'] * 2)
    assert len(batch['manifest']['tracks']) == len(before['manifest']['tracks']) + 2
    assert len(batch['manifest']['assets']) == len(before['manifest']['assets']) + 2
    assert batch['state']['revision'] == before['state']['revision'] + 1
    assert batch['manifest']['sections'] == before['manifest']['sections']
    assert batch['manifest']['portLayout'] == before['manifest']['portLayout']
    for identifier, position in before['manifest']['signal']['layout']['positions'].items():
        assert batch['manifest']['signal']['layout']['positions'][identifier] == position
    for identifier, position in edits(before)['layout']['positions'].items():
        assert edits(batch)['layout']['positions'][identifier] == position
    assert batch['state']['playback']['canvasSize'] == [1024, 673]
    assert batch['state']['playback']['editorAddress'] is None
    assert 'section' in batch['state']['selection']
    visible = {c['address'].get('music', {}).get('nodeID') for c in batch['state']['playback']['labelCircles']}
    assert len(visible.intersection(n['id'] for n in added)) == 6

    audio, output = read('audio-effect'), read('output-effect')
    audio_fx = audio['state']['selection']['music']['nodeID']
    output_fx = output['state']['selection']['music']['nodeID']
    track = next(t['id'] for t in batch['manifest']['tracks'] if t['name'] == 'tone-1.wav')
    source = next(n['id'] for n in added if n['content'].get('audio', {}).get('laneID') ==
                  next(l['id'] for l in batch['manifest']['arrangements'][0]['uses'][0]['addedLanes'] if l['trackID'] == track))
    for first, second, fx in [(batch, audio, audio_fx), (audio, output, output_fx)]:
        old_edges = {e['id']: e for e in edits(first)['addedEdges']}
        new_edges = {e['id']: e for e in edits(second)['addedEdges']}
        changed = [e for i, e in new_edges.items() if i in old_edges and e != old_edges[i]]
        new = [e for i, e in new_edges.items() if i not in old_edges]
        assert len(changed) == len(new) == 1
        assert set(old_edges).issubset(new_edges)
        if fx == audio_fx:
            assert changed[0]['from'] == fx and changed[0]['to'] == 'mix:' + track
            assert new[0]['from'] == source and new[0]['to'] == fx
        else:
            assert changed[0]['from'] == 'mix:' + track and changed[0]['to'] == fx
            assert new[0]['from'] == fx and new[0]['to'] == 'output:' + track
        assert first['manifest']['sections'] == second['manifest']['sections']
        assert first['manifest']['tracks'] == second['manifest']['tracks']
        assert first['manifest']['assets'] == second['manifest']['assets']

    pattern, step, midi = read('pattern'), read('pattern-note'), read('midi')
    assert pattern['manifest']['patterns'][0]['trackID'] == track
    assert pattern['state']['selection']['music']['nodeID'] == 'rhythm-midi:' + track
    assert not pattern['manifest']['patterns'][0]['notes']
    assert len(step['manifest']['patterns'][0]['notes']) == 1
    assert step['manifest']['patterns'][0]['notes'][0]['pitch'] == 71
    rhythm_edges = edits(pattern)['addedEdges']
    assert any(e['from'] == 'rhythm-midi:' + track and e['to'] == 'instrument:' + track for e in rhythm_edges)
    assert any(e['from'] == 'instrument:' + track and e['to'] == 'mix:' + track for e in rhythm_edges)
    midi_id = midi['state']['selection']['music']['nodeID']
    lane = next(l for l in midi['manifest']['arrangements'][0]['uses'][0]['addedLanes'] if 'midi:' + l['id'] == midi_id)
    assert len(lane['notes']) == 1 and lane['notes'][0]['pitch'] == 66 and len(lane['audio']) == 1
    assert any(e['from'] == midi_id and e['to'] == 'instrument:' + lane['trackID'] for e in edits(midi)['addedEdges'])
    assert any(e['from'] == 'instrument:' + lane['trackID'] and e['to'] == 'mix:' + lane['trackID'] for e in edits(midi)['addedEdges'])
    for name in ['audio-ax', 'shortcut-audio-ax']:
        text = (OUT / (name + '.txt')).read_text()
        assert '오디오 궤도 편집기' in text and 'menu button 이펙트 추가' in text
    assert '스텝 편집기' in (OUT / 'pattern-note-ax.txt').read_text()
    assert '1개 노트' in (OUT / 'midi-ax.txt').read_text()
    assert read('export-job')['job']['state'] == 'completed'
    audio_file = read('export-audio')
    assert audio_file['seconds'] == 34 and audio_file['rate'] == 48000 and audio_file['bits'] == 24
    assert audio_file['channels'] == 2 and 0.01 < audio_file['peak'] < 1
    assert hashlib.sha256((OUT / 'source-workflow.wav').read_bytes()).hexdigest() == audio_file['sha256']

    pairs = [('pattern-note', 'undo-midi'), ('pattern', 'undo-step'), ('output-effect', 'undo-pattern'),
             ('audio-effect', 'undo-output'), ('batch', 'undo-audio'), ('before', 'restored'), ('before', 'reopened')]
    for first, second in pairs:
        music_equal(read(first)['manifest'], read(second)['manifest'])
    assert not read('reopened')['state']['dirty'] and read('reopened')['state']['job']['state'] == 'completed'
    names = ['before', 'batch', 'audio-effect', 'output-effect', 'pattern', 'pattern-note', 'midi'] + [b for _, b in pairs]
    package = read('package')
    for name in names:
        s = read(name)['state']
        assert s['runtime']['bundleID'] == 'com.circlr.integrationqa' and s['runtime']['version'] == '0.20.0'
        assert s['projectID'] == package['projectID'] and s['path'] == package['fixture']
        assert not s['recording']['busy'] and not s['recording']['midi']

    app = Path(package['app'])
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    assert info['CFBundleVersion'] == '27'
    binary = app / 'Contents/MacOS/circlr'
    source = ROOT / '.build/integration-release/release/circlr'
    expected_uuid = '543B4F72-09DA-341A-8A18-7DB330F24AB4'
    for path in [source, binary]:
        assert expected_uuid in subprocess.check_output(['dwarfdump', '--uuid', str(path)], text=True)
    spec = importlib.util.spec_from_file_location('import_evidence', ROOT / 'qa/check-import-evidence.py')
    helper = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(helper)
    assert helper.sections(source) == helper.sections(binary)
    assert len(helper.sections(source)) == 37
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    kit = app / 'Contents/Resources/Codex'
    manifest = json.loads((kit / 'manifest.json').read_text())
    assert len(manifest['files']) == 25 and manifest['version'] == '0.20.0'
    for name, checksum in manifest['files'].items():
        assert hashlib.sha256((kit / name).read_bytes()).hexdigest() == checksum
    original = Path(package['fixture']).with_name('studio.circlr')
    assert hashlib.sha256((original / 'manifest.json').read_bytes()).hexdigest() == package['sourceSHA256']
    assert 'Executed 253 tests, with 0 failures' in (OUT / 'swift-tests.log').read_text()
    assert 'Ran 26 tests' in (OUT / 'python-tests.log').read_text() and '\nOK\n' in (OUT / 'python-tests.log').read_text()
    assert 'Build complete!' in (OUT / 'release.log').read_text()
    result = dict(status='passed', nativeSnapshots=len(set(names)), undoTransitions=6, fileBackedSections=37,
                  kitFiles=25, swiftTests=253, pythonTests=26, uuid=expected_uuid, audio=audio_file)
    (OUT / 'verification.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(result, ensure_ascii=False))


if __name__ == '__main__':
    main()
