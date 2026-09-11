#!/usr/bin/env python3
"""Snapshot/save only the exact isolated bounce return QA app. Never play, audition or record."""
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


p = module('bounce_return_qa_package', 'prepare-bounce-return-qa.py')
q = module('bounce_return_qa_native', 'verify-integration-native.py')


def capture(name, candidate, save=False, restored=False, conflict=False):
    assert re.fullmatch('[a-z0-9-]{1,64}', name)
    assert re.fullmatch('[a-z0-9-]{1,32}', candidate) and candidate != 'baseline'
    directory = p.OUT / candidate
    target = directory / (name + '.json')
    assert not target.exists(), 'Preserve previous evidence before saving'
    package = json.loads((directory / 'package.json').read_text())
    injection = json.loads((directory / 'qa-injection.json').read_text())
    assert package['projectID'] == p.PROJECT_ID and package['fixture'] == str(p.FIXTURE)
    assert package['build'] in ['122', '123']
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
    assert p.digest(p.SOURCE) == package['sourceSHA256'] == scenario['sourceSHA256']
    baseline = p.OUT / ('conflict-baseline' if conflict else 'baseline')
    if conflict:
        assert not restored, 'Conflict scenario expects rejection and unchanged music'
        scenario = json.loads((baseline / 'scenario.json').read_text())
        assert scenario['fixture'] == str(p.FIXTURE.with_name('bounce-return-conflict.circlr'))
        p.FIXTURE = Path(scenario['fixture']); p.PROJECT_ID = scenario['projectID']
    q.FIXTURE = p.FIXTURE; q.PROJECT_ID = p.PROJECT_ID

    def state():
        value = q.state()
        assert value['runtime']['build'] == package['build']
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
        seed = json.loads((baseline / 'fixture-initial.json').read_text())
        assert manifest['id'] == p.PROJECT_ID and manifest['musicRevision'] == final['revision']
        assert not final['dirty'] and manifest['assets'] == seed['assets']
        for asset in manifest['assets']:
            path = Path(asset['path']); assert not path.is_absolute() and '..' not in path.parts
            assert p.digest(p.FIXTURE / path) == asset['checksum']
        import copy
        expected = copy.deepcopy(seed)
        if restored:
            arrangement = next(a for a in expected['arrangements'] if a['id'] == scenario['arrangementID'])
            use = next(u for u in arrangement['uses'] if u['id'] == scenario['useID'])
            graph = use['graphEdits']; node = next(n for n in graph['addedNodes'] if n['id'] == scenario['nodeID'])
            bounce = node.pop('bounce'); node['muted'] = True
            removed = [e for e in graph['addedEdges'] if e['from'] == scenario['nodeID'] and e['to'] == scenario['outputNodeID']]
            assert len(removed) == 1
            graph['addedEdges'].remove(removed[0]); graph['addedEdges'].extend(bounce['replacedInputs'])
        ignore = {'hierarchyView','musicRevision','layoutRevision','modifiedAt'}
        assert {k:v for k,v in manifest.items() if k not in ignore} == {k:v for k,v in expected.items() if k not in ignore}, 'Unexpected structural change'
        result['restoredSource'] = restored
        result['manifest'] = manifest
    p.exclusive(target, result)
    print(target)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('name'); parser.add_argument('--candidate', required=True)
    parser.add_argument('--save', action='store_true')
    parser.add_argument('--restored', action='store_true', help='Require exact source edge restoration and muted archive')
    parser.add_argument('--conflict', action='store_true', help='Capture exact conflict copy with unchanged music')
    args = parser.parse_args()
    capture(args.name, args.candidate, args.save, args.restored, args.conflict)
