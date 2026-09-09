#!/usr/bin/env python3
"""Package build 44 with authored long names and three adjacent buses; no device use."""
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
packager.NAME = 'canvas-labels'
packager.BUILD = '44'
packager.OUT = packager.ROOT / 'qa/generated/canvas-labels'
packager.APP = packager.OUT / '써클러 통합 검증.app'
packager.FIXTURE = packager.SOURCE.with_name('canvas-labels.circlr')


if __name__ == '__main__':
    packager.main()
    if '--candidate' not in sys.argv:
        path = packager.FIXTURE / 'manifest.json'
        project = json.loads(path.read_text())
        edits = project['arrangements'][0]['uses'][0]['graphEdits']
        names = {
            'instrument': '북유럽의 긴 밤을 지나 돌아오는 시티팝 키보드 · f0r h3r / Midnight Chorus Layer',
            'midi': '다시 만나는 여름밤의 멜로디 · MIDI 16마디 / Extended Future Bass Chorus',
            'mix': '공백없는아주긴한글이름과MidnightCityPopFutureBassExtendedInstrumentLayer2026',
        }
        for node in edits['addedNodes']:
            for kind, name in names.items():
                if kind in node['content']:
                    node['name'] = name
        edits['layout']['groups'][0]['name'] = '북유럽 신스와 시티팝을 연결하는 공간 · 오디오와 멀티 입력 그룹'
        template = next(n for n in edits['addedNodes'] if 'mix' in n['content'])
        for index in range(1, 4):
            node = copy.deepcopy(template)
            node['id'] = str(uuid.uuid5(uuid.NAMESPACE_URL, f'circlr-integration-qa/canvas-labels/bus-{index}')).upper()
            node['name'] = f'공간 버스 {index:02d} · 깊고 넓은 후렴의 리버브와 딜레이'
            edits['addedNodes'].append(node)
            edits['layout']['positions'][node['id']] = dict(x=640, y=-220+(index-1)*220)
        path.write_text(json.dumps(project, ensure_ascii=False, indent=2) + '\n')
    sources = ['Resources/Info.plist', 'Sources/CirclrCore/CanvasLabelLayout.swift',
               'Sources/CirclrApp/CanvasPresentation.swift', 'Sources/CirclrApp/AlbumCanvas.swift',
               'Sources/CirclrApp/PlaybackVisualization.swift']
    (packager.OUT / 'source-hashes.json').write_text(json.dumps({name: hashlib.sha256((packager.ROOT / name).read_bytes()).hexdigest() for name in sources}, indent=2) + '\n')
