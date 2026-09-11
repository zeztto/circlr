#!/usr/bin/env python3
"""Snapshot/save only the exact isolated step target QA app. Never play, audition or record."""
import argparse
import importlib.util
import json
from pathlib import Path
import re


def module(name, filename):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(filename))
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


p = module('step_qa_package', 'prepare-step-target-qa.py')
q = module('step_qa_native', 'verify-integration-native.py')


def capture(name, candidate, save=False):
    assert re.fullmatch('[a-z0-9-]{1,64}', name)
    assert re.fullmatch('[a-z0-9-]{1,32}', candidate) and candidate != 'baseline'
    directory = p.OUT / candidate
    target = directory / (name + '.json')
    assert not target.exists(), 'Preserve previous evidence before saving'
    package = json.loads((directory / 'package.json').read_text())
    injection = json.loads((directory / 'qa-injection.json').read_text())
    assert package['projectID'] == p.PROJECT_ID and package['fixture'] == str(p.FIXTURE)
    assert package['build'] in ['121', '122']
    app = directory / '써클러 통합 검증.app'
    assert package['app'] == str(app)
    macos = app / 'Contents/MacOS'
    assert p.digest(macos / 'circlr') == package['packagedMainSHA256']
    assert p.run(['dwarfdump', '--uuid', str(macos / 'circlr')]).split()[1] == package['packagedMainUUID'] == package['sourceBinaryUUID']
    assert injection['qaOnlyMock'] and injection['denyAllAudioHelpers'] and injection['helperExit'] == 78
    assert injection['candidate'] == candidate
    assert set(injection['packagedHelperSHA256']) == set(p.HELPERS)
    for helper in p.HELPERS:
        assert p.digest(macos / helper) == injection['packagedHelperSHA256'][helper]
        assert injection['productionHelperSHA256'][helper] == package['sourceBinarySHA256'][helper]
        assert injection['packagedHelperSHA256'][helper] != injection['productionHelperSHA256'][helper]
    p.run(['codesign', '--verify', '--deep', '--strict', str(app)])
    resources = app / 'Contents/Resources/Codex'
    assert p.digest(resources / 'manifest.json') == package['codexManifestSHA256']
    for file, checksum in json.loads((resources / 'manifest.json').read_text())['files'].items():
        assert p.digest(resources / file) == checksum
    scenario = json.loads((p.OUT / 'baseline/scenario.json').read_text())
    seed = json.loads((p.OUT / 'baseline/fixture-initial.json').read_text())
    assert p.digest(p.SOURCE / 'manifest.json') == scenario['sourceSHA256'] == package['sourceSHA256']
    q.FIXTURE = p.FIXTURE; q.PROJECT_ID = p.PROJECT_ID

    def state():
        value = q.state()
        assert value['runtime']['build'] == package['build']
        assert value['revision'] == seed['musicRevision'], 'Step target navigation must not modify music'
        assert value['output']['attempts'] == value['audition']['attempts'] == 0
        assert not value['playback']['playing']
        assert not any(value['recording'][key] for key in ['busy', 'audio', 'midi'])
        return value

    initial = state()
    if save:
        # Validate build/no-I/O on the same snapshot supplying the optimistic save revision.
        q.call('save', dict(projectID=p.PROJECT_ID, expectedRevision=initial['revision']))
    final = state()
    assert final['revision'] == initial['revision'], 'Music changed during capture'
    result = dict(state=final, packageBuild=package['build'], saved=save)
    if save:
        manifest = json.loads((p.FIXTURE / 'manifest.json').read_text())
        seed = json.loads((p.OUT / 'baseline/fixture-initial.json').read_text())
        assert manifest['id'] == p.PROJECT_ID and manifest['musicRevision'] == final['revision']
        assert not final['dirty'] and manifest['assets'] == seed['assets']
        p.assets(manifest, p.FIXTURE)
        ignored = {'hierarchyView', 'layoutRevision', 'modifiedAt'}
        assert {k:v for k,v in manifest.items() if k not in ignored} == {k:v for k,v in seed.items() if k not in ignored}, 'Step target QA must preserve musical content'
        result['manifest'] = manifest
    p.exclusive(target, result)
    print(target)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('name'); parser.add_argument('--candidate', required=True)
    parser.add_argument('--save', action='store_true')
    args = parser.parse_args()
    capture(args.name, args.candidate, args.save)
