#!/usr/bin/env python3
"""Read/save the exact integration QA app. Does not start playback or recording."""
import argparse
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from mcp.server import call_tool

OUT = ROOT / 'qa/generated/integration'
SOCKET = Path.home() / 'Library/Application Support/circlr-integration-qa/Agent/agent.sock'
FIXTURE = Path.home() / 'Library/Application Support/circlr-integration-qa/fixtures/studio.circlr'
PROJECT_ID = 'B29AF867-91DE-55DB-9958-EC7EFCF0ADDF'


def call(name, args=None):
    reply = call_tool(str(SOCKET), 'circlr_' + name, args or {})['structuredContent']
    if not reply.get('ok'):
        raise RuntimeError(reply)
    return reply['result']


def state():
    s = call('snapshot')
    assert s['runtime']['bundleID'] == 'com.circlr.integrationqa' and s['runtime']['version'] == '0.20.0'
    assert s['path'] == str(FIXTURE) and s['projectID'] == PROJECT_ID
    assert not s['recording']['midi'] and not s['recording']['busy']
    return s


def write(name, args=None):
    assert name != 'record', 'This helper never starts microphone recording'
    s = state()
    return call(name, dict(args or {}, projectID=s['projectID'], expectedRevision=s['revision']))


def capture(save=False):
    if save:
        write('save')
    s = state()
    result = {'state': s}
    if save:
        result['manifest'] = json.loads((FIXTURE / 'manifest.json').read_text())
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('name')
    parser.add_argument('--save', action='store_true')
    args = parser.parse_args()
    assert re.fullmatch('[a-z0-9-]{1,64}', args.name)
    path = OUT / (args.name + '.json')
    with path.open('x') as file:
        json.dump(capture(args.save), file, ensure_ascii=False, indent=2)
        file.write('\n')
    print(path)
