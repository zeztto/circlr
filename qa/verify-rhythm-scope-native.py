#!/usr/bin/env python3
"""Save/snapshot the isolated rhythm-scope QA app; never play or record.

  python3 qa/verify-rhythm-scope-native.py compact --candidate final2
  python3 qa/verify-rhythm-scope-native.py reopened --candidate final2

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
OUT = q.ROOT / 'qa/generated/rhythm-scope'


def capture(name, candidate='final'):
    assert re.fullmatch('[a-z0-9-]{1,64}', name)
    assert re.fullmatch('[a-z0-9-]{1,32}', candidate)
    directory = OUT / candidate
    package = json.loads((directory / 'package.json').read_text())
    expected_build = '108' if candidate == 'baseline' else '109'
    assert package['build'] == expected_build
    assert package['projectID'] == str(uuid.uuid5(uuid.NAMESPACE_URL, 'circlr-integration-qa/rhythm-scope')).upper()
    q.FIXTURE = Path(package['fixture'])
    assert q.FIXTURE == Path.home() / 'Library/Application Support/circlr-integration-qa/fixtures/rhythm-scope.circlr'
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
    scenario = json.loads((OUT / 'baseline/scenario.json').read_text())
    assert hashlib.sha256((Path(scenario['source']) / 'manifest.json').read_bytes()).hexdigest() == scenario['sourceSHA256']
    assert len(result['manifest']['assets']) == scenario['assets']
    pattern = next(p for p in result['manifest']['patterns'] if p['id'] == scenario['patternID'])
    assert pattern['name'] == scenario['patternName']
    assert result['manifest']['global']['rhythm']['patternID'] == pattern['id']
    initial = json.loads((OUT / 'baseline/fixture-initial.json').read_text())
    assert result['manifest']['sections'] == initial['sections']
    assert result['manifest']['arrangements'] == initial['arrangements'], 'Pattern edit must not change either use'
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
