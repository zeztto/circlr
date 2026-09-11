#!/usr/bin/env python3
"""Package build 41 with authored dense connections; preserve prior candidates."""
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
packager.NAME = 'connection-workspace'
packager.BUILD = '41'
packager.OUT = packager.ROOT / 'qa/generated/connection-workspace'
packager.APP = packager.OUT / '써클러 통합 검증.app'
packager.FIXTURE = packager.SOURCE.with_name('connection-workspace.circlr')


def identifier(name):
    return str(uuid.uuid5(uuid.NAMESPACE_URL, 'circlr-integration-qa/connection-workspace/' + name)).upper()


if __name__ == '__main__':
    packager.main()
    if '--candidate' not in sys.argv:
        path = packager.FIXTURE / 'manifest.json'
        project = json.loads(path.read_text())
        edits = project['arrangements'][0]['uses'][0]['graphEdits']
        source = 'instrument:7E0D9016-E91D-4325-B807-033F233E32EA'
        template = next(n for n in edits['addedNodes'] if 'mix' in n['content'])
        for index in range(1, 9):
            node = copy.deepcopy(template)
            node['id'] = identifier('bus-' + str(index))
            node['name'] = f'공간 버스 {index:02d} · 북유럽 신스와 시티팝 키보드의 긴 이름 검증'
            edits['addedNodes'].append(node)
            edits['layout']['positions'][node['id']] = dict(x=600 + (index % 3) * 180, y=(index // 3) * 200)
            if index <= 6:
                edits['addedEdges'].append(dict(id=identifier('edge-' + str(index)), **{'from': source, 'to': node['id']}, gain=1, sidechain=False, signal='audio'))
        path.write_text(json.dumps(project, ensure_ascii=False, indent=2) + '\n')
    sources = ['Resources/Info.plist', 'Sources/CirclrApp/PortConnectionsEditor.swift',
               'Sources/CirclrApp/PortKeyboardControls.swift', 'Sources/CirclrApp/PortTargetList.swift']
    (packager.OUT / 'source-hashes.json').write_text(json.dumps({name: hashlib.sha256((packager.ROOT / name).read_bytes()).hexdigest() for name in sources}, indent=2) + '\n')
