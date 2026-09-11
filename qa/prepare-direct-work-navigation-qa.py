#!/usr/bin/env python3
"""Package build 59 and authored repeated/empty sections for direct navigation QA."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import uuid

spec = importlib.util.spec_from_file_location('packager', Path(__file__).with_name('prepare-automation-workspace-qa.py'))
packager = importlib.util.module_from_spec(spec); spec.loader.exec_module(packager)
packager.NAME = 'direct-work-navigation'; packager.BUILD = '59'
packager.OUT = packager.ROOT / 'qa/generated/direct-work-navigation'
packager.APP = packager.OUT / '써클러 통합 검증.app'
packager.FIXTURE = packager.SOURCE.with_name('direct-work-navigation.circlr')


def identifier(name):
    return str(uuid.uuid5(uuid.NAMESPACE_URL, 'circlr-integration-qa/direct-work-navigation/' + name)).upper()


if __name__ == '__main__':
    packager.main()
    if '--candidate' not in sys.argv:
        path = packager.FIXTURE / 'manifest.json'; project = json.loads(path.read_text())
        arrangement = project['arrangements'][0]
        for number in range(3, 13):
            use = copy.deepcopy(arrangement['uses'][0]); use['id'] = identifier('use/' + str(number))
            use['name'] = 'Nordic 후렴 ' + str(number)
            if number in [11, 12]:
                use['name'] = '북유럽 겨울밤의 도시 불빛과 바다 위로 퍼지는 긴 이름의 후렴 — 같은 이름을 가진 두 번째 편곡 구간'
            arrangement['uses'].append(use)
            arrangement['layout']['positions'][use['id']] = dict(x=(number-1)*700, y=0)
        empty = copy.deepcopy(project['sections'][0]); empty.update(id=identifier('empty-section'), name='비어 있는 브리지', lanes=[])
        empty['graph']['nodes'] = []; empty['graph']['edges'] = []
        empty['graph']['layout']['positions'] = {}; empty['graph']['layout']['groups'] = []
        project['sections'].append(empty)
        use = copy.deepcopy(arrangement['uses'][0])
        use.update(id=identifier('empty-use'), sectionID=empty['id'], name=empty['name'], addedLanes=[], laneOverrides={}, excludedLaneIDs=[])
        use.pop('graphEdits', None); arrangement['uses'].append(use)
        arrangement['layout']['positions'][use['id']] = dict(x=8400, y=0)
        path.write_text(json.dumps(project, ensure_ascii=False, indent=2) + '\n')
        (packager.OUT / 'fixture-initial.json').write_bytes(path.read_bytes())
    sources = ['Resources/Info.plist', 'Sources/CirclrCore/StudioNavigationSearch.swift', 'Sources/CirclrApp/StudioNavigationView.swift', 'Sources/CirclrApp/AppStore.swift', 'Sources/CirclrApp/RootView.swift']
    (packager.OUT / 'source-hashes.json').write_text(json.dumps({name: hashlib.sha256((packager.ROOT / name).read_bytes()).hexdigest() for name in sources}, indent=2) + '\n')
