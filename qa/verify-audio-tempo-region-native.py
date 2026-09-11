#!/usr/bin/env python3
"""Save/snapshot the isolated audio-tempo-region QA app; never play or record.

  python3 qa/verify-audio-tempo-region-native.py before --candidate final
  python3 qa/verify-audio-tempo-region-native.py reopened --candidate final

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
OUT = q.ROOT / 'qa/generated/audio-tempo-region'


def capture(name, candidate='final', allow_render_asset=False):
    assert re.fullmatch('[a-z0-9-]{1,64}', name)
    assert re.fullmatch('[a-z0-9-]{1,32}', candidate)
    directory = OUT / candidate
    package = json.loads((directory / 'package.json').read_text())
    injection_path = directory / 'qa-injection.json'
    assert injection_path.exists(), 'UI-only tempo-region QA requires deny-output package'
    if injection_path.exists():
        injection = json.loads(injection_path.read_text())
        assert injection['qaOnlyMock'] and injection['denyOutput']
        assert injection['candidate'] == candidate and injection['outputWorkerExit'] == 78
        macos = Path(package['app']) / 'Contents/MacOS'
        for helper, checksum in injection['packagedHelperSHA256'].items():
            assert hashlib.sha256((macos / helper).read_bytes()).hexdigest() == checksum
        preserved = directory / 'production-helpers/circlr-output-worker'
        assert hashlib.sha256(preserved.read_bytes()).hexdigest() == injection['productionHelperSHA256']['circlr-output-worker']
    expected_build = '113'
    assert candidate != 'baseline', 'Baseline is seed metadata, not a packaged candidate'
    assert package['build'] == expected_build
    assert package['projectID'] == str(uuid.uuid5(uuid.NAMESPACE_URL, 'circlr-integration-qa/audio-tempo-region')).upper()
    q.FIXTURE = Path(package['fixture'])
    assert q.FIXTURE == Path.home() / 'Library/Application Support/circlr-integration-qa/fixtures/audio-tempo-region.circlr'
    q.PROJECT_ID = package['projectID']
    target = directory / (name + '.json')
    assert not target.exists(), 'Preserve existing evidence before saving'
    state = q.state()
    before_revision = state['revision']
    assert state['runtime']['build'] == expected_build
    assert state['output']['attempts'] == state['audition']['attempts'] == 0
    assert not state['playback']['playing']
    assert not any(state['recording'][key] for key in ['busy', 'audio', 'midi'])
    result = q.capture(save=True)
    state = result['state']
    assert state['revision'] == before_revision, 'Music changed while saving capture'
    assert state['runtime']['build'] == expected_build
    assert state['output']['attempts'] == state['audition']['attempts'] == 0
    assert not state['playback']['playing']
    assert not any(state['recording'][key] for key in ['busy', 'audio', 'midi'])
    assert state['revision'] == result['manifest']['musicRevision'] and not state['dirty']
    initial = json.loads((OUT / 'baseline/fixture-initial.json').read_text())
    original_assets = {a['id']:a for a in initial['assets']}
    current_assets = {a['id']:a for a in result['manifest']['assets']}
    assert all(current_assets.get(k) == v for k,v in original_assets.items())
    assert len(current_assets) == (3 if allow_render_asset else 2)
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
    parser.add_argument('--allow-render-asset',action='store_true',help='Require exactly one additional offline-render asset')
    args = parser.parse_args()
    capture(args.name,args.candidate,args.allow_render_asset)
