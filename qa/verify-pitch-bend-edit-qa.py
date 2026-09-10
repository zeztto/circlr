#!/usr/bin/env python3
"""Build135 isolated native MCP edit/Undo QA. Never launches an app or audio I/O."""
import argparse
import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import uuid

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('bend_return', Path(__file__).with_name('verify-midi-import-return-qa.py'))
r = importlib.util.module_from_spec(spec); spec.loader.exec_module(r)
f = r.f; q = f.q
from mcp.server import call_tool, rpc

A = '95B906AF-5A06-43F0-BF79-8EDB26A8973F'
USE = '33728378-FA9A-5ABB-9CDD-1645F190EE8D'
LANE = '2BDE27E4-72A1-4B5C-88CA-9716B84CF90C'
PATTERN = '45811D74-B089-57F3-95EC-788AF57290CC'
TRACK = '7E0D9016-E91D-4325-B807-033F233E32EA'


def run(args):
    directory = args.package.parent.resolve()
    assert directory.is_relative_to(ROOT / 'qa/generated')
    package = json.loads(args.package.read_text())
    app = directory / '써클러 통합 검증.app'; binary = app / 'Contents/MacOS/circlr'
    assert package['app'] == str(app) and str(package['build']) == '135'
    assert f.sha(binary) == package['mainSHA256']
    assert subprocess.check_output(['dwarfdump', '--uuid', str(binary)], text=True).split()[1] == package['sourceUUID']
    assert set(package['helpers']) == f.HELPERS
    for name, checksum in package['helpers'].items(): assert f.sha(binary.parent / name) == checksum
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True, capture_output=True, timeout=60)
    pid = f.assert_candidate_process(app)
    out = args.output.resolve(); assert out.is_relative_to(ROOT / 'qa/generated') and not out.exists()
    out.mkdir(parents=True)

    def record(name, data):
        with (out / (name + '.json')).open('x') as handle: json.dump(data, handle, ensure_ascii=False, indent=2)

    def state(revision=None):
        s = q.state(); r.idle(s, 135, s['revision'] if revision is None else revision)
        assert f.assert_candidate_process(app) == pid
        assert s['runtime']['capabilities']['midiPitchBendEditing'] == 1
        return s

    def capture(name):
        s = state(); q.call('save', dict(projectID=f.PROJECT_ID, expectedRevision=s['revision']))
        after = state(s['revision']); assert not after['dirty']
        manifest = json.loads((f.FIXTURE / 'manifest.json').read_text())
        assert manifest['id'] == f.PROJECT_ID and manifest['musicRevision'] == after['revision']
        for asset in manifest['assets']:
            path = Path(asset['path']); assert not path.is_absolute() and '..' not in path.parts
            assert f.sha(f.FIXTURE / path) == asset['checksum']
        result = dict(state=after, manifest=manifest); record(name, result); return result

    def stable_music(manifest):
        music = copy.deepcopy(manifest)
        music.pop('musicRevision'); music.pop('hierarchyView', None)
        return music

    def unchanged(before, after):
        assert stable_music(before['manifest']) == stable_music(after['manifest'])
        for key in ('selection', 'selectedNoteIDs', 'activeArrangementID'):
            assert before['state'][key] == after['state'][key], key

    def apply(ops, name):
        s = state()
        result = call_tool(str(q.SOCKET), 'circlr_apply', dict(projectID=f.PROJECT_ID, expectedRevision=s['revision'], operations=ops))
        record(name + '-reply', result); assert not result['isError'], result
        after = state(s['revision'] + 1)
        assert after['selection'] == s['selection']
        return capture(name)

    def undo(before, name):
        s = state()
        q.call('undo', dict(projectID=f.PROJECT_ID, expectedRevision=s['revision'], expectedLayoutRevision=s['layoutRevision']))
        after = capture(name); unchanged(before, after)
        return after

    state(args.expected_revision)  # Reject the wrong starting revision before even saving.
    baseline = capture('baseline'); assert baseline['state']['revision'] == args.expected_revision
    normal = dict(kind='edit_pitch_bend', arrangementID=A, useID=USE, laneID=LANE, original=False)
    shared = dict(kind='edit_pitch_bend', patternID=PATTERN, trackID=TRACK)
    def inspected(): return q.call('inspect', dict(arrangementID=A, useID=USE))
    assert next(l for l in inspected()['lanes'] if l['id'] == LANE)['pitchBend']['events']
    assert next(p for p in baseline['manifest']['patterns'] if p['id'] == PATTERN)['trackID'] == TRACK
    changed = apply([dict(normal, change=dict(kind='setInitial', channel=0, rawValue=10240, range=dict(semitones=7, cents=25)))], 'normal')
    bend = next(l for l in inspected()['lanes'] if l['id'] == LANE)['pitchBend']
    assert bend['initialValue'] == 10240 and bend['initialRange'] == dict(semitones=7,cents=25)
    current = undo(baseline, 'normal-undone')
    changed = apply([dict(shared, change=dict(kind='insert', beat=0.5, rawValue=4096))], 'shared')
    pattern = next(p for p in changed['manifest']['patterns'] if p['id'] == PATTERN)
    assert pattern['pitchBend']['events'][-1] == dict(beat=0.5,kind=dict(value=dict(_0=4096)))
    assert pattern['trackID'] == TRACK
    current = undo(current, 'shared-undone')
    good = dict(normal, change=dict(kind='setInitial',channel=0,rawValue=10000,range=dict(semitones=2,cents=0)))
    bad = dict(normal, change=dict(kind='remove',index=99999))
    negative = [('stale', [good], current['state']['revision']-1),
                ('mixed-address', [dict(good,patternID=PATTERN,trackID=TRACK)], current['state']['revision']),
                ('atomic-batch', [good,bad], current['state']['revision'])]
    for name, operations, revision in negative:
        # Direct app RPC proves app-side rejection, independently of MCP schema preflight.
        reply = rpc(str(q.SOCKET), dict(id=str(uuid.uuid4()),method='apply',projectID=f.PROJECT_ID,expectedRevision=revision,arguments=dict(operations=operations)))
        record(name+'-reply',reply); assert reply.get('ok') is False, reply
        after = capture(name+'-unchanged'); assert after['state']['revision'] == current['state']['revision']
        unchanged(current, after)
    final = capture('final'); unchanged(baseline, final)
    record('result',dict(status='PASS',projectID=f.PROJECT_ID,baselineRevision=args.expected_revision,finalRevision=final['state']['revision'],selection=final['state']['selection'],candidatePID=pid,outputAttempts=0,auditionAttempts=0,scope='native MCP normal/shared edits, Undo musical restoration, app-side stale/mixed/atomic rejection; no playback/render'))
    print(out / 'result.json')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--expected-revision', type=int, default=102)
    run(parser.parse_args())
