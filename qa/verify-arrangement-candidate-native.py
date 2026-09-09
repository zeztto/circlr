#!/usr/bin/env python3
"""Save exclusive snapshots of only the build99 owned fixture; no output or recording."""
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import sys
import uuid

spec = importlib.util.spec_from_file_location('qa', Path(__file__).with_name('verify-integration-native.py'))
q = importlib.util.module_from_spec(spec); spec.loader.exec_module(q)
OUT = q.ROOT / 'qa/generated/arrangement-candidate'


def capture(name):
    assert re.fullmatch('[a-z0-9-]{1,64}', name)
    package = json.loads((OUT / 'package.json').read_text())
    assert package['build'] == '99'
    assert package['projectID'] == str(uuid.uuid5(uuid.NAMESPACE_URL, 'circlr-integration-qa/arrangement-candidate')).upper()
    q.FIXTURE = Path(package['fixture']); q.PROJECT_ID = package['projectID']
    assert q.FIXTURE == Path.home() / 'Library/Application Support/circlr-integration-qa/fixtures/arrangement-candidate.circlr'
    target = OUT / (name + '.json'); assert not target.exists()
    def check(state):
        assert state['runtime']['build'] == '99'
        assert state['output']['attempts'] == state['audition']['attempts'] == 0
        assert not state['playback']['playing'] and not any(state['recording'][k] for k in ['audio', 'midi', 'busy'])
    check(q.state())
    capture = q.capture(save=True); check(capture['state'])
    assert capture['state']['revision'] == capture['manifest']['musicRevision'] and not capture['state']['dirty']
    assert len(capture['manifest']['assets']) == 2
    for asset in capture['manifest']['assets']:
        path = Path(asset['path']); assert not path.is_absolute() and '..' not in path.parts
        assert hashlib.sha256((q.FIXTURE / path).read_bytes()).hexdigest() == asset['checksum']
    with target.open('x') as file: json.dump(capture, file, ensure_ascii=False, indent=2)


if __name__ == '__main__':
    assert len(sys.argv) == 2
    capture(sys.argv[1])
