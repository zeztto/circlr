#!/usr/bin/env python3
"""Record a read-only snapshot of the exact packaged outward-orbit QA app."""
import argparse
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from mcp.server import call_tool


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('name')
    parser.add_argument('--build', default='166')
    args = parser.parse_args()
    assert re.fullmatch(r'[a-z0-9-]{1,64}', args.name)
    assert re.fullmatch(r'[0-9]{1,8}', args.build)
    directory = ROOT / 'qa/generated/outward-orbit' / ('build' + args.build)
    package = json.loads((directory / 'package.json').read_text())
    socket = Path.home() / 'Library/Application Support/circlr-integration-qa/Agent/agent.sock'
    reply = call_tool(str(socket), 'circlr_snapshot', {})['structuredContent']
    assert reply['ok'], reply
    state = reply['result']
    assert state['runtime']['bundleID'] == package['bundleID'] == 'com.circlr.integrationqa'
    assert state['runtime']['version'] == package['version']
    assert state['runtime']['build'] == package['build'] == args.build
    assert state['path'] == package['fixture'] and state['projectID'] == package['projectID']
    assert not state['recording']['busy'] and not state['recording']['midi']
    target = directory / (args.name + '.json')
    with target.open('x') as file:
        json.dump(state, file, ensure_ascii=False, indent=2)
        file.write('\n')
    print(json.dumps({'evidence': str(target), 'canvasSize': state['playback']['canvasSize'],
                      'playing': state['playback']['playing'], 'dirty': state['dirty']}))


if __name__ == '__main__':
    main()
