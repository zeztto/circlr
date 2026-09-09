#!/usr/bin/env python3
"""Package build 60 and authored fixture for sound selection QA."""
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import uuid

spec = importlib.util.spec_from_file_location('packager', Path(__file__).with_name('prepare-automation-workspace-qa.py'))
packager = importlib.util.module_from_spec(spec); spec.loader.exec_module(packager)
packager.NAME = 'sound-selection'; packager.BUILD = '60'
packager.OUT = packager.ROOT / 'qa/generated/sound-selection'
packager.APP = packager.OUT / '써클러 통합 검증.app'
packager.FIXTURE = packager.SOURCE.with_name('sound-selection.circlr')


def identifier(name):
    return str(uuid.uuid5(uuid.NAMESPACE_URL, 'circlr-integration-qa/sound-selection/' + name)).upper()


if __name__ == '__main__':
    packager.main()
    if '--candidate' not in sys.argv:
        path=packager.FIXTURE / 'manifest.json'; project=json.loads(path.read_text())
        project['tracks'][2]['instrument']['synth']['cutoff']=731
        project['signal']['nodes'].append(dict(id=identifier('global-effect'), name='전역 공간', kind='effect', effect=dict(kind='reverb', amount=0.23, secondary=0.45, renderVersion=2)))
        path.write_text(json.dumps(project,ensure_ascii=False,indent=2)+'\n')
        (packager.OUT/'fixture-initial.json').write_bytes(path.read_bytes())
    sources = ['Resources/Info.plist', 'Sources/CirclrCore/SoundSelection.swift', 'Sources/CirclrAudio/AudioUnitHost.swift', 'Sources/CirclrApp/SoundPickerView.swift', 'Sources/CirclrApp/AppStore.swift', 'Sources/CirclrApp/RootView.swift', 'Sources/CirclrApp/InspectorView.swift', 'Sources/CirclrApp/InlineCircleEditor.swift', 'Sources/CirclrApp/EffectControls.swift', 'Sources/CirclrApp/EditorView.swift', 'Sources/CirclrApp/CanvasCommands.swift', 'Sources/CirclrApp/MediaLibraryView.swift', 'Sources/CirclrApp/StudioNavigationView.swift', 'Sources/CirclrApp/CanvasFileDrop.swift', 'Sources/CirclrApp/AlbumCanvas.swift']
    (packager.OUT / 'source-hashes.json').write_text(json.dumps({name: hashlib.sha256((packager.ROOT / name).read_bytes()).hexdigest() for name in sources}, indent=2) + '\n')
