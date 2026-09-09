#!/usr/bin/env python3
"""Package build 61 and authored fixture for sound selection QA."""
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import uuid

spec = importlib.util.spec_from_file_location('packager', Path(__file__).with_name('prepare-automation-workspace-qa.py'))
packager = importlib.util.module_from_spec(spec); spec.loader.exec_module(packager)
packager.NAME = 'sound-bank-search'; packager.BUILD = '61'
packager.OUT = packager.ROOT / 'qa/generated/sound-bank-search'
packager.APP = packager.OUT / '써클러 통합 검증.app'
packager.FIXTURE = packager.SOURCE.with_name('sound-bank-search.circlr')


def identifier(name):
    return str(uuid.uuid5(uuid.NAMESPACE_URL, 'circlr-integration-qa/sound-bank-search/' + name)).upper()


if __name__ == '__main__':
    packager.main()
    if '--candidate' not in sys.argv:
        path=packager.FIXTURE / 'manifest.json'; project=json.loads(path.read_text())
        project['tracks'][2]['instrument']['synth']['cutoff']=731
        path.write_text(json.dumps(project,ensure_ascii=False,indent=2)+'\n')
        (packager.OUT/'fixture-initial.json').write_bytes(path.read_bytes())
    sources=['Resources/Info.plist','Sources/CirclrCore/Model.swift','Sources/CirclrCore/ProjectStore.swift','Sources/CirclrCore/SoundSelection.swift','Sources/CirclrCore/SoundBankPreset.swift','Sources/CirclrAudio/AudioUnitHost.swift','Sources/CirclrAudio/SoundBankCatalog.swift','Sources/CirclrApp/AppStore.swift','Sources/CirclrApp/SoundPickerView.swift','Sources/CirclrApp/InspectorView.swift','Sources/CirclrApp/EditorView.swift']
    (packager.OUT/'source-hashes.json').write_text(json.dumps({name:hashlib.sha256((packager.ROOT/name).read_bytes()).hexdigest() for name in sources},indent=2)+'\n')
