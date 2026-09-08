#!/usr/bin/env python3
"""Build 40 package and authored two-section fixture, preserving previous candidates."""
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import uuid

spec = importlib.util.spec_from_file_location('packager', Path(__file__).with_name('prepare-automation-workspace-qa.py'))
packager = importlib.util.module_from_spec(spec)
spec.loader.exec_module(packager)
packager.NAME = 'transition-effects'
packager.BUILD = '40'
packager.OUT = packager.ROOT / 'qa/generated/transition-effects'
packager.APP = packager.OUT / '써클러 통합 검증.app'
packager.FIXTURE = packager.SOURCE.with_name('transition-effects.circlr')


def identifier(name):
    return str(uuid.uuid5(uuid.NAMESPACE_URL, 'circlr-integration-qa/transition-effects/' + name)).upper()


if __name__ == '__main__':
    packager.main()
    if '--candidate' not in sys.argv:
        path = packager.FIXTURE / 'manifest.json'
        project = json.loads(path.read_text())
        arrangement = project['arrangements'][0]
        source, target = arrangement['uses']
        source['name'] = '앞 섹션'; source['isEnd'] = False
        target['name'] = '뒤 섹션'
        target['settings']['tempo'] = dict(source='local', value=96)
        target['settings']['meter'] = dict(source='local', value=dict(numerator=7, denominator=8))
        project['sections'][0]['tempoChanges'] = [dict(beat=56, bpm=60)]
        project['sections'][0]['meterChanges'] = [dict(bar=14, meter=dict(numerator=3, denominator=4))]
        edge = dict(id=identifier('edge'), **{'from': source['id'], 'to': target['id']},
                    transition=dict(mode='within', anchor='sourceBars', length=1,
                                    effect=dict(kind='gain', amount=1, secondary=.25)))
        arrangement['edges'] = [edge]
        track = project['tracks'][2]['id']
        project['patterns'].append(dict(id=identifier('pattern'), name='전환 연주', length=4, meter=dict(numerator=4, denominator=4),
            trackID=track, notes=[dict(id=identifier('note'), beat=0, length=.5, pitch=66, velocity=75)], audio=[]))
        graph = project['signal']
        effect_id = identifier('global-effect')
        graph['nodes'].append(dict(id=effect_id, kind='effect', name='앨범 게인', effect=dict(kind='gain', amount=1, secondary=.25)))
        source_id = next(n['id'] for n in graph['nodes'] if n.get('trackID') == track)
        route = next(e for e in graph['edges'] if e['from'] == source_id)
        destination = route['to']; route['to'] = effect_id
        graph['edges'].append(dict(id=identifier('global-route'), **{'from': effect_id, 'to': destination}, gain=1, sidechain=False))
        graph['layout']['positions'][effect_id] = dict(x=400, y=240)
        path.write_text(json.dumps(project, ensure_ascii=False, indent=2) + '\n')
    sources = ['Resources/Info.plist', 'Sources/CirclrCore/TransitionTiming.swift', 'Sources/CirclrCore/Compiler.swift',
               'Sources/CirclrCore/GainScale.swift', 'Sources/CirclrCore/NumberEditSession.swift',
               'Sources/CirclrApp/TransitionWorkspace.swift', 'Sources/CirclrApp/EffectControls.swift',
               'Sources/CirclrApp/InlineEditorHeader.swift', 'Sources/CirclrApp/InlineCircleEditor.swift',
               'Sources/CirclrApp/InspectorView.swift', 'Sources/CirclrApp/CircleWorkspace.swift']
    hashes = {name: hashlib.sha256((packager.ROOT / name).read_bytes()).hexdigest() for name in sources}
    (packager.OUT / 'source-hashes.json').write_text(json.dumps(hashes, indent=2) + '\n')
