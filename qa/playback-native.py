"""Read/control only the authorized circlr QA bundle and disposable 0.11 project."""
import argparse
import json
from pathlib import Path
import sys
import uuid

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'mcp'))
from server import rpc

SOCKET = str(Path.home() / 'Library/Application Support/circlr-hierarchy-qa/Agent/agent.sock')
QA = ROOT / 'qa/generated/0.11-visualizer'


def call(method, arguments=None, write=False):
    request = {'id': str(uuid.uuid4()), 'method': method, 'arguments': arguments or {}}
    if write:
        state = call('snapshot')
        request.update(projectID=state['projectID'], expectedRevision=state['revision'])
    reply = rpc(SOCKET, request)
    assert reply['ok'], reply
    return reply['result']


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('command', choices=['snapshot', 'open', 'play', 'stop', 'minimize', 'restore', 'focus', 'follow', 'unfollow'])
    parser.add_argument('--report')
    args = parser.parse_args()
    state = call('snapshot')
    assert state['runtime']['bundleID'] == 'com.circlr.hierarchyqa'
    assert state['runtime']['version'] == '0.11.0'
    if args.command == 'open':
        assert not state['dirty']
        result = call('open', {'path': str(QA / 'f0r-h3r.circlr')}, write=True)
    else:
        assert state['path'] == str(QA / 'f0r-h3r.circlr'), state['path']
        if args.command in ('minimize', 'restore'):
            result = call('focus', {'minimized': args.command == 'minimize'})
        elif args.command in ('follow', 'unfollow'):
            result = call('focus', {'follow': args.command == 'follow'})
        elif args.command == 'focus':
            result = call('focus')
        else:
            result = call(args.command)
    if args.report:
        assert Path(args.report).name == args.report
        (QA / args.report).write_text(json.dumps(result, ensure_ascii=False, indent=2)+'\n')
    if args.command == 'snapshot':
        visual = result.get('playback', {})
        print(json.dumps({'runtime': result['runtime'], 'dirty': result['dirty'], 'selection': result['selection'],
                          'playback': {k: v for k, v in visual.items() if k not in ['nodes', 'phases', 'edges']},
                          'activeNodes': len(visual.get('nodes', [])), 'activeEdges': len(visual.get('edges', {}))}, ensure_ascii=False))
    else:
        print(json.dumps(result, ensure_ascii=False))


if __name__ == '__main__':
    main()
