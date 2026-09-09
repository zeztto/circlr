#!/usr/bin/env python3
"""Package build 58 with 99 authored QA tracks; never modify the source project."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import uuid

spec = importlib.util.spec_from_file_location('packager', Path(__file__).with_name('prepare-automation-workspace-qa.py'))
packager = importlib.util.module_from_spec(spec)
spec.loader.exec_module(packager)
packager.NAME = 'library-track-search'
packager.BUILD = '58'
packager.OUT = packager.ROOT / 'qa/generated/library-track-search'
packager.APP = packager.OUT / '써클러 통합 검증.app'
packager.FIXTURE = packager.SOURCE.with_name('library-track-search.circlr')


def identifier(name):
    return str(uuid.uuid5(uuid.NAMESPACE_URL, 'circlr-integration-qa/library-track-search/' + name)).upper()


if __name__ == '__main__':
    packager.main()
    if '--candidate' not in sys.argv:
        path = packager.FIXTURE / 'manifest.json'
        project = json.loads(path.read_text())
        assert len(project['tracks']) == 3
        for number in range(4, 100):
            name = 'Nordic 패드' if number in (97, 98) else '편곡 레이어 ' + str(number)
            if number == 99:
                name = '북유럽 겨울밤의 도시 불빛과 바다 위로 퍼지는 아주 긴 이름의 신스웨이브 패드 레이어 — 후렴에서만 사용하는 넓고 부드러운 화성'
            track = copy.deepcopy(project['tracks'][0])
            track.update(id=identifier('track/' + str(number)), name=name)
            project['tracks'].append(track)
            node = copy.deepcopy(project['signal']['nodes'][1])
            node.update(id=identifier('node/' + str(number)), name=name, trackID=track['id'])
            project['signal']['nodes'].append(node)
            project['signal']['layout']['positions'][node['id']] = dict(x=100, y=(number-1)*220)
            edge = copy.deepcopy(project['signal']['edges'][0])
            edge.update(id=identifier('edge/' + str(number)))
            edge['from'] = node['id']
            project['signal']['edges'].append(edge)
        assert len(project['tracks']) == 99 and len({t['id'] for t in project['tracks']}) == 99
        path.write_text(json.dumps(project, ensure_ascii=False, indent=2) + '\n')
        (packager.OUT / 'fixture-initial.json').write_bytes(path.read_bytes())
    sources = ['Resources/Info.plist', 'Sources/CirclrCore/AudioImportPlacement.swift', 'Sources/CirclrApp/MediaLibraryController.swift', 'Sources/CirclrApp/MediaLibraryPlacement.swift', 'Sources/CirclrApp/MediaLibraryView.swift', 'Sources/CirclrApp/LibraryTrackChooser.swift']
    (packager.OUT / 'source-hashes.json').write_text(json.dumps({name: hashlib.sha256((packager.ROOT / name).read_bytes()).hexdigest() for name in sources}, indent=2) + '\n')
