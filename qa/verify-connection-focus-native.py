#!/usr/bin/env python3
"""Save/snapshot the isolated connection-focus QA app; never play or record.

  python3 qa/verify-connection-focus-native.py compact --candidate final2
  python3 qa/verify-connection-focus-native.py reopened --candidate final2

Each snapshot is written exclusively under its selected package directory.
"""
import argparse
import uuid
import hashlib
import importlib.util
import json
from pathlib import Path
import re

spec = importlib.util.spec_from_file_location('integration_qa', Path(__file__).with_name('verify-integration-native.py'))
q = importlib.util.module_from_spec(spec)
spec.loader.exec_module(q)
OUT = q.ROOT / 'qa/generated/connection-focus'


def capture(name, candidate='final'):
    assert re.fullmatch('[a-z0-9-]{1,64}', name)
    assert re.fullmatch('[a-z0-9-]{1,32}', candidate)
    directory = OUT / candidate
    package = json.loads((directory / 'package.json').read_text())
    expected_build = '103' if candidate == 'baseline' else '104'
    assert package['build'] == expected_build
    assert package['projectID'] == str(uuid.uuid5(uuid.NAMESPACE_URL, 'circlr-integration-qa/connection-focus')).upper()
    q.FIXTURE = Path(package['fixture'])
    assert q.FIXTURE == Path.home() / 'Library/Application Support/circlr-integration-qa/fixtures/connection-focus.circlr'
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
    assert state['revision'] == result['manifest']['musicRevision'] and not state['dirty']
    assert len(result['manifest']['assets']) == 2
    for asset in result['manifest']['assets']:
        path = Path(asset['path'])
        assert not path.is_absolute() and '..' not in path.parts
        assert hashlib.sha256((q.FIXTURE / path).read_bytes()).hexdigest() == asset['checksum']
    with target.open('x') as file:
        json.dump(result, file, ensure_ascii=False, indent=2)
        file.write('\n')
    print(target)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('name')
    parser.add_argument('--candidate',required=True)
    args = parser.parse_args()
    capture(args.name,args.candidate)
