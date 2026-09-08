#!/usr/bin/env python3
"""Capture the isolated port QA app. Never starts playback or recording."""
import argparse
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from mcp.server import call_tool

SOCKET = Path.home() / 'Library/Application Support/circlr-ports-qa/Agent/agent.sock'
PROJECT = Path.home() / 'Library/Application Support/circlr-ports-qa/fixtures/ports.circlr'
OUT = ROOT / 'qa/generated/ports-ui'

def call(name, args=None):
    response = call_tool(str(SOCKET), 'circlr_' + name, args or {})['structuredContent']
    if not response.get('ok'):
        raise RuntimeError(response)
    return response['result']

def state():
    s = call('snapshot')
    assert s['runtime']['bundleID'] == 'com.circlr.portsqa' and s['path'] == str(PROJECT)
    assert not s['recording']['audio'] and not s['recording']['midi']
    return s

def write(name, args=None):
    s = state()
    return call(name, dict(args or {}, projectID=s['projectID'], expectedRevision=s['revision']))

def capture(save=False):
    if save:
        write('save')
    s = state()
    selected = s['selection'].get('music') or s['selection'].get('section')
    result = {'state': s}
    if selected:
        result['inspection'] = call('inspect', {k: selected[k] for k in ['arrangementID', 'useID']})
    if save:
        result['manifest'] = json.loads((PROJECT / 'manifest.json').read_text())
    return result

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('name')
    parser.add_argument('--save', action='store_true')
    args = parser.parse_args()
    assert re.fullmatch('[a-z0-9-]{1,64}', args.name)
    path = OUT / (args.name + '.json')
    assert not path.exists(), 'Keep previous QA evidence'
    result = capture(args.save)
    path.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'path': str(path), 'revision': result['state']['revision'], 'saved': args.save}))
