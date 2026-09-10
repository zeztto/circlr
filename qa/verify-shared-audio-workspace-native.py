#!/usr/bin/env python3
"""Save/snapshot the isolated shared-audio-workspace QA app; never play or record.

  python3 qa/verify-shared-audio-workspace-native.py before --candidate final
  python3 qa/verify-shared-audio-workspace-native.py reopened --candidate final

Each snapshot is written exclusively under its selected package directory.
"""
import argparse
import uuid
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import struct

spec = importlib.util.spec_from_file_location('integration_qa', Path(__file__).with_name('verify-integration-native.py'))
q = importlib.util.module_from_spec(spec)
spec.loader.exec_module(q)
OUT = q.ROOT / 'qa/generated/shared-audio-workspace'


def capture(name, candidate='final'):
    assert re.fullmatch('[a-z0-9-]{1,64}', name)
    assert re.fullmatch('[a-z0-9-]{1,32}', candidate)
    directory = OUT / candidate
    package = json.loads((directory / 'package.json').read_text())
    if 'packagedMainSHA256' in package:
        main = (Path(package['app']) / 'Contents/MacOS/circlr').read_bytes()
        assert hashlib.sha256(main).hexdigest() == package['packagedMainSHA256']
        assert struct.unpack_from('<I',main)[0] == 0xfeedfacf
        offset=32; actual_uuid=None
        for _ in range(struct.unpack_from('<I',main,16)[0]):
            command,size=struct.unpack_from('<II',main,offset)
            assert size>=8 and offset+size<=len(main)
            if command==0x1b: actual_uuid=str(uuid.UUID(bytes=main[offset+8:offset+24])).upper()
            offset+=size
        assert actual_uuid == package['packagedMainUUID'] == package['sourceBinaryUUID']
        assert actual_uuid in package['uuid']
    injection_path = directory / 'qa-injection.json'
    assert injection_path.exists(), 'UI-only shared audio QA requires deny-output package'
    if injection_path.exists():
        injection = json.loads(injection_path.read_text())
        assert injection['qaOnlyMock'] and injection['denyOutput']
        assert injection['candidate'] == candidate and injection['outputWorkerExit'] == 78
        assert set(injection['packagedHelperSHA256']) == {'circlr-output-worker','circlr-au-effect-worker','circlr-au-instrument-worker','circlr-output-device-catalog'}
        macos = Path(package['app']) / 'Contents/MacOS'
        for helper, checksum in injection['packagedHelperSHA256'].items():
            assert hashlib.sha256((macos / helper).read_bytes()).hexdigest() == checksum
        preserved = directory / 'production-helpers/circlr-output-worker'
        assert hashlib.sha256(preserved.read_bytes()).hexdigest() == injection['productionHelperSHA256']['circlr-output-worker']
    expected_build = package['build']
    assert expected_build in ['115','116','117']
    assert candidate != 'baseline', 'Baseline is seed metadata, not a packaged candidate'
    assert package['build'] == expected_build
    assert package['projectID'] == str(uuid.uuid5(uuid.NAMESPACE_URL, 'circlr-integration-qa/shared-audio-workspace')).upper()
    q.FIXTURE = Path(package['fixture'])
    assert q.FIXTURE == Path.home() / 'Library/Application Support/circlr-integration-qa/fixtures/shared-audio-workspace.circlr'
    q.PROJECT_ID = package['projectID']
    target = directory / (name + '.json')
    assert not target.exists(), 'Preserve existing evidence before saving'
    state = q.state()
    before_revision = state['revision']
    assert state['runtime']['build'] == expected_build and state['runtime']['bundleID'] == 'com.circlr.integrationqa'
    assert state['projectID'] == q.PROJECT_ID and state['path'] == str(q.FIXTURE)
    assert state['output']['attempts'] == state['audition']['attempts'] == 0
    assert not state['playback']['playing']
    assert not any(state['recording'][key] for key in ['busy', 'audio', 'midi'])
    result = q.capture(save=True)
    state = result['state']
    assert state['revision'] == before_revision, 'Music changed while saving capture'
    assert state['runtime']['build'] == expected_build and state['runtime']['bundleID'] == 'com.circlr.integrationqa'
    assert state['projectID'] == q.PROJECT_ID and state['path'] == str(q.FIXTURE)
    assert state['output']['attempts'] == state['audition']['attempts'] == 0
    assert not state['playback']['playing']
    assert not any(state['recording'][key] for key in ['busy', 'audio', 'midi'])
    assert state['revision'] == result['manifest']['musicRevision'] and not state['dirty']
    assert len(result['manifest']['assets']) == 2
    assert result['manifest']['id'] == q.PROJECT_ID
    seed = json.loads((OUT / 'baseline/fixture-initial.json').read_text())
    assert result['manifest']['assets'] == seed['assets']
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
