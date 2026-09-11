#!/usr/bin/env python3
"""Capture the isolated 0.30 candidate and authored fixture; never start audio."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess
import sys
import unicodedata

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from mcp.server import call_tool

SOCKET = Path.home() / 'Library/Application Support/circlr-integration-qa/Agent/agent.sock'
FIXTURE = Path.home() / 'Library/Application Support/circlr-integration-qa/fixtures/release030.circlr'


def call(name, arguments=None):
    value = call_tool(str(SOCKET), 'circlr_' + name, arguments or {})['structuredContent']
    if not value.get('ok'):
        raise RuntimeError(value)
    return value['result']


def candidate(app):
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    assert info['CFBundleIdentifier'] == 'com.circlr.integrationqa'
    assert info['CFBundleShortVersionString'] == '0.30.0'
    executable = unicodedata.normalize('NFC', str(app / 'Contents/MacOS/circlr'))
    processes = [line.strip().split(None, 1) for line in subprocess.check_output(['ps', '-axo', 'pid=,comm='], text=True).splitlines()]
    qa_processes = [(int(pid), unicodedata.normalize('NFC', path)) for pid, path in processes if unicodedata.normalize('NFC', path).endswith('/써클러 통합 검증.app/Contents/MacOS/circlr')]
    assert len(qa_processes) == 1 and qa_processes[0][1] == executable, 'Exactly one requested QA candidate must be running'
    matches = [qa_processes[0][0]]
    state = call('snapshot')
    assert state['runtime']['bundleID'] == info['CFBundleIdentifier']
    assert state['runtime']['version'] == info['CFBundleShortVersionString']
    assert state['runtime']['build'] == info['CFBundleVersion']
    assert state['output']['attempts'] == state['audition']['attempts'] == 0
    assert not state['playback']['playing'] and not any(state['recording'][key] for key in ('busy', 'audio', 'midi'))
    return state, matches[0]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('action', choices=('open', 'snapshot', 'capture'))
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    state, pid = candidate(args.app.resolve())
    if args.action == 'open':
        print(json.dumps(call('open', dict(projectID=state['projectID'], expectedRevision=state['revision'], path=str(FIXTURE)))))
        return
    assert state['projectID'] == 'R30-project' and state['path'] == str(FIXTURE)
    if args.action == 'snapshot':
        print(json.dumps(state, ensure_ascii=False))
        return
    assert args.output is not None and not args.output.exists()
    call('save', dict(projectID=state['projectID'], expectedRevision=state['revision']))
    after, next_pid = candidate(args.app.resolve())
    assert pid == next_pid and state['revision'] == after['revision'] and not after['dirty']
    manifest = json.loads((FIXTURE / 'manifest.json').read_text())
    for asset in manifest['assets']:
        path = Path(asset['path'])
        assert not path.is_absolute() and '..' not in path.parts
        assert hashlib.sha256((FIXTURE / path).read_bytes()).hexdigest() == asset['checksum']
    app_hash = hashlib.sha256((args.app / 'Contents/MacOS/circlr').read_bytes()).hexdigest()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open('x') as output:
        json.dump(dict(state=after, manifest=manifest, pid=pid, mainSHA256=app_hash), output, ensure_ascii=False, indent=2)
    print(args.output)


if __name__ == '__main__':
    main()
