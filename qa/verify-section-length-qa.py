#!/usr/bin/env python3
"""Single-writer build137 section length MCP QA; never launches app or audio."""
import argparse
import copy
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import uuid

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('length_return', Path(__file__).with_name('verify-midi-import-return-qa.py'))
r = importlib.util.module_from_spec(spec); spec.loader.exec_module(r)
f = r.f; q = f.q
from mcp.server import call_tool, rpc

A = '95B906AF-5A06-43F0-BF79-8EDB26A8973F'
USE = '33728378-FA9A-5ABB-9CDD-1645F190EE8D'


def run(args):
    assert args.build == 137 and args.expected_revision >= 0
    assert re.fullmatch('[a-z0-9-]{1,32}', args.candidate)
    assert re.fullmatch('[a-z0-9-]{1,64}', args.name)
    directory = r.OUT / args.candidate
    package = json.loads((directory / 'package.json').read_text())
    app = directory / '써클러 통합 검증.app'; binary = app / 'Contents/MacOS/circlr'
    assert package['app'] == str(app) and str(package['build']) == '137'
    assert f.sha(binary) == package['mainSHA256']
    assert subprocess.check_output(['dwarfdump', '--uuid', str(binary)], text=True, timeout=10).split()[1] == package['sourceUUID']
    assert set(package['helpers']) == f.HELPERS
    prior = json.loads((r.OUT / 'fileactions136-final/package.json').read_text())
    assert package['helpers'] == prior['helpers'], 'Require the previously verified five exit78 stub binaries'
    for helper, checksum in package['helpers'].items():
        assert f.sha(binary.parent / helper) == checksum
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True, capture_output=True, timeout=60)
    codex = app / 'Contents/Resources/Codex'
    manifest = json.loads((codex / 'manifest.json').read_text())
    assert {str(p.relative_to(codex)) for p in codex.rglob('*') if p.is_file()} == set(manifest['files']) | {'manifest.json'}
    for name, checksum in manifest['files'].items():
        path = Path(name); assert not path.is_absolute() and '..' not in path.parts
        assert f.sha(codex / path) == checksum
    assert f.sha(codex / 'skills/circlr-studio/scripts/mcp_server.py') == f.sha(ROOT / 'mcp/server.py')
    pid = f.assert_candidate_process(app)
    out = directory / args.name
    assert not out.exists()

    def state(revision=None):
        s = q.state(); r.idle(s, args.build, s['revision'] if revision is None else revision)
        assert s['path'] == str(f.FIXTURE)
        assert f.assert_candidate_process(app) == pid
        assert type(s['runtime']['capabilities']['sectionLengthEditing']) is int
        assert s['runtime']['capabilities']['sectionLengthEditing'] == 1
        return s

    state(args.expected_revision)  # No save/mutation until identity/revision/process gates pass.
    out.mkdir()

    def record(name, value):
        with (out / (name + '.json')).open('x') as handle:
            json.dump(value, handle, ensure_ascii=False, indent=2); handle.write('\n')

    def capture(name, revision):
        s = state(revision)
        q.call('save', dict(projectID=f.PROJECT_ID, expectedRevision=revision))
        after = state(revision); assert not after['dirty']
        m = json.loads((f.FIXTURE / 'manifest.json').read_text())
        assert m['id'] == f.PROJECT_ID and m['musicRevision'] == revision
        assert len({a['id'] for a in m['assets']}) == len(m['assets'])
        for asset in m['assets']:
            p = Path(asset['path']); assert not p.is_absolute() and '..' not in p.parts
            assert f.sha(f.FIXTURE / p) == asset['checksum']
        value = dict(state=after, manifest=m); record(name, value); return value

    def music(m):
        result = copy.deepcopy(m)
        result.pop('musicRevision'); result.pop('hierarchyView', None)
        return result

    def use(m):
        return next(u for a in m['arrangements'] if a['id'] == A for u in a['uses'] if u['id'] == USE)

    def assert_same(before, after):
        assert music(before['manifest']) == music(after['manifest'])
        for key in ('selection', 'selectedNoteIDs', 'activeArrangementID'):
            assert before['state'][key] == after['state'][key], key

    def assert_override(before, after, bars):
        expected = music(before['manifest']); target = use(expected)
        if bars is None: target.pop('barsOverride', None)
        else: target['barsOverride'] = bars
        assert expected == music(after['manifest']), 'Only the addressed use override may change'
        for key in ('selection', 'selectedNoteIDs', 'activeArrangementID'):
            assert before['state'][key] == after['state'][key], key

    def apply(op, before, name, increment=1):
        revision = before['state']['revision']; state(revision)
        reply = call_tool(str(q.SOCKET), 'circlr_apply', dict(projectID=f.PROJECT_ID, expectedRevision=revision, operations=[op]))
        record(name + '-reply', reply); assert not reply['isError'], reply
        return capture(name, revision + increment)

    baseline = capture('baseline', args.expected_revision)
    assert use(baseline['manifest']).get('barsOverride') not in (None, 20)
    assert max(c['beat'] for c in use(baseline['manifest'])['tempoOverride']['changes']) >= 6
    op = dict(kind='set_use_length_override', arrangementID=A, useID=USE, bars=20)
    changed = apply(op, baseline, 'set20'); assert_override(baseline, changed, 20)
    # AppStore.mutate returns before history/revision when candidate == project.
    same = apply(op, changed, 'set20-again', increment=0); assert_same(changed, same)
    cleared = apply(dict(kind='clear_use_length_override', arrangementID=A, useID=USE), same, 'cleared')
    assert_override(same, cleared, None); assert use(cleared['manifest']).get('barsOverride') is None
    current = cleared
    for name, expected in [('undo-clear', changed), ('undo-set', baseline)]:
        s = state(current['state']['revision'])
        q.call('undo', dict(projectID=f.PROJECT_ID, expectedRevision=s['revision'], expectedLayoutRevision=s['layoutRevision']))
        current = capture(name, s['revision'] + 1); assert_same(expected, current)

    # Python shape rejection must occur before transport; q.call shares MCP validation,
    # so the app-side probes below deliberately use rpc to bypass that preflight.
    for bars in (0, 4097):
        state(current['state']['revision'])
        try:
            call_tool(str(q.SOCKET), 'circlr_apply', dict(projectID=f.PROJECT_ID,
                expectedRevision=current['state']['revision'], operations=[dict(op, bars=bars)]))
        except ValueError as error:
            record('shape-' + str(bars) + '-reply', dict(rejected=True, error=str(error)))
        else: raise AssertionError('Invalid bars must fail Python schema validation')
        after = capture('shape-' + str(bars), current['state']['revision']); assert_same(current, after)

    negative = [
        ('known-extra', dict(op, name='unexpected'), f.PROJECT_ID, current['state']['revision']),
        ('wrong-use', dict(op, useID='00000000-0000-0000-0000-000000000000'), f.PROJECT_ID, current['state']['revision']),
        ('unsafe-shrink', dict(op, bars=1), f.PROJECT_ID, current['state']['revision']),
        ('stale-project', op, '00000000-0000-0000-0000-000000000000', current['state']['revision']),
        ('stale-revision', op, f.PROJECT_ID, current['state']['revision'] - 1)]
    for name, operation, project_id, revision in negative:
        state(current['state']['revision'])
        reply = rpc(str(q.SOCKET), dict(id=str(uuid.uuid4()), method='apply', projectID=project_id,
            expectedRevision=revision, arguments=dict(operations=[operation])))
        record(name + '-reply', reply); assert reply.get('ok') is False, reply
        after = capture(name, current['state']['revision']); assert_same(current, after)
    final = capture('final', current['state']['revision']); assert_same(baseline, final)
    record('result', dict(status='PASS', projectID=f.PROJECT_ID, baselineRevision=args.expected_revision,
        finalRevision=final['state']['revision'], candidatePID=pid, outputAttempts=0, auditionAttempts=0,
        scope='Actual MCP set/clear/no-op and Undo2; schema and direct app rejection; exact other music/assets/selection; no audio',
        mainSHA256=package['mainSHA256'], codexManifestSHA256=f.sha(codex / 'manifest.json')))
    print(out / 'result.json')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--candidate', default='sectionlength137')
    parser.add_argument('--build', type=int, default=137)
    parser.add_argument('--expected-revision', type=int, default=134)
    parser.add_argument('--name', default='mcp-check')
    run(parser.parse_args())
