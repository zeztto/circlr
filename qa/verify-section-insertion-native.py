#!/usr/bin/env python3
"""Save/snapshot the exact baseline or candidate QA app; never play or record.

  python3 qa/verify-section-insertion-native.py before --baseline
  python3 qa/verify-section-insertion-native.py disconnected --candidate final

Each snapshot is written exclusively under its selected package directory.
"""
import argparse
import importlib.util
import json
from pathlib import Path
import re

spec = importlib.util.spec_from_file_location('integration_qa', Path(__file__).with_name('verify-integration-native.py'))
q = importlib.util.module_from_spec(spec)
spec.loader.exec_module(q)
OUT = q.ROOT / 'qa/generated/section-insertion'


def capture(name, candidate='final'):
    assert re.fullmatch('[a-z0-9-]{1,64}', name)
    assert re.fullmatch('[a-z0-9-]{1,32}', candidate)
    directory = OUT / candidate
    package = json.loads((directory / 'package.json').read_text())
    expected_build = '87' if candidate == 'baseline' else '88'
    assert package['build'] == expected_build
    q.FIXTURE = Path(package['fixture'])
    q.PROJECT_ID = package['projectID']
    target = directory / (name + '.json')
    assert not target.exists(), 'Preserve existing evidence before saving'
    state = q.state()
    assert state['runtime']['build'] == expected_build
    assert state['output']['attempts'] == state['audition']['attempts'] == 0
    assert not state['playback']['playing']
    assert not any(state['recording'][key] for key in ['busy', 'audio', 'midi'])
    result = q.capture(save=True)
    state = result['state']
    assert state['runtime']['build'] == expected_build
    assert state['output']['attempts'] == state['audition']['attempts'] == 0
    assert not state['playback']['playing']
    assert not any(state['recording'][key] for key in ['busy', 'audio', 'midi'])
    with target.open('x') as file:
        json.dump(result, file, ensure_ascii=False, indent=2)
        file.write('\n')
    print(target)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('name')
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--baseline', action='store_true')
    mode.add_argument('--candidate')
    args = parser.parse_args()
    if args.candidate == 'baseline':
        parser.error('Use --baseline for the build87 package')
    capture(args.name, 'baseline' if args.baseline else args.candidate)
