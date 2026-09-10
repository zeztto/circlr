#!/usr/bin/env python3
"""Capture only the isolated feedback QA project; compare cancel identity/music offline."""
import argparse
import copy
import importlib.util
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'qa/generated/midi-import-return'
spec = importlib.util.spec_from_file_location('feedback', Path(__file__).with_name('verify-midi-import-feedback-qa.py'))
f = importlib.util.module_from_spec(spec)
spec.loader.exec_module(f)


def idle(state, build, revision):
    assert state['projectID'] == f.PROJECT_ID
    assert str(state['runtime']['build']) == str(build) and state['revision'] == revision
    assert state['output']['attempts'] == state['audition']['attempts'] == 0
    assert state['output']['phase'] == state['audition']['phase'] == 'idle'
    assert state['audition']['heldNotes'] == 0 and not state['playback']['playing']
    assert not any(state['recording'][key] for key in ('busy', 'audio', 'midi'))
    assert not state.get('job') or state['job']['state'] != 'running'


def capture(args):
    assert re.fullmatch('[a-z0-9-]{1,64}', args.name)
    directory = OUT / args.candidate
    assert re.fullmatch('[a-z0-9-]{1,32}', args.candidate)
    target = directory / (args.name + '.json')
    assert not target.exists()
    package = json.loads((directory / 'package.json').read_text())
    app = directory / '써클러 통합 검증.app'
    assert package['app'] == str(app) and str(package['build']) == str(args.build)
    binary = app / 'Contents/MacOS/circlr'
    assert f.sha(binary) == package['mainSHA256']
    assert subprocess.check_output(['dwarfdump', '--uuid', str(binary)], text=True).split()[1] == package['sourceUUID']
    assert set(package['helpers']) == f.HELPERS
    for name, checksum in package['helpers'].items():
        assert f.sha(binary.parent / name) == checksum
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True, capture_output=True, timeout=60)
    pid = f.assert_candidate_process(app)
    before = f.q.state()
    idle(before, args.build, args.expected_revision)
    f.q.call('save', dict(projectID=f.PROJECT_ID, expectedRevision=args.expected_revision))
    after = f.q.state()
    idle(after, args.build, args.expected_revision)
    assert f.assert_candidate_process(app) == pid and not after['dirty']
    manifest = json.loads((f.FIXTURE / 'manifest.json').read_text())
    assert manifest['id'] == f.PROJECT_ID and manifest['musicRevision'] == args.expected_revision
    baseline = json.loads((f.OUT / f.BASELINE_NAME).read_text())
    actual = {asset['id']: asset for asset in manifest['assets']}
    assert len(actual) == len(manifest['assets'])
    assert all(actual.get(asset['id']) == asset for asset in baseline['assets'])
    for asset in manifest['assets']:
        path = Path(asset['path'])
        assert not path.is_absolute() and '..' not in path.parts
        assert f.sha(f.FIXTURE / path) == asset['checksum']
    target.write_text(json.dumps(dict(state=after, manifest=manifest, candidatePID=pid,
        validationScope='QA identity, package, no-I/O, assets. Compare persisted hierarchyView separately; AX/JPEG verifies visible restoration.'), ensure_ascii=False, indent=2) + '\n')
    print(target)


def music(manifest):
    result = copy.deepcopy(manifest)
    # Separate the actual persisted workspace field; all remaining fields must stay exact.
    assert 'hierarchyView' in result
    del result['hierarchyView']
    return result


def compare(args):
    before, after = [json.loads(path.read_text()) for path in (args.before, args.after)]
    a, b = before['state'], after['state']
    assert a['projectID'] == b['projectID'] == f.PROJECT_ID
    for key in ('revision', 'activeArrangementID', 'selection', 'selectedNoteIDs'):
        assert a[key] == b[key], key
    assert music(before['manifest']) == music(after['manifest']), 'Musical manifest changed'
    assert before['manifest']['hierarchyView'] == after['manifest']['hierarchyView'], 'Persisted workspace/editor/camera changed'
    print('PASS: same project/revision/address/note selection/music and full hierarchyView. Verify visible restoration in AX/JPEG.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    c = commands.add_parser('capture')
    c.add_argument('name'); c.add_argument('--candidate', required=True)
    c.add_argument('--build', type=int, required=True); c.add_argument('--expected-revision', type=int, required=True)
    c.set_defaults(run=capture)
    c = commands.add_parser('compare-cancel')
    c.add_argument('before', type=Path); c.add_argument('after', type=Path)
    c.set_defaults(run=compare)
    args = parser.parse_args(); args.run(args)
