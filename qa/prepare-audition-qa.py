#!/usr/bin/env python3
"""Build 43 QA package with an authored tone sampler; preserve user media."""
import hashlib
import importlib.util
import json
from pathlib import Path
import sys

spec = importlib.util.spec_from_file_location('packager', Path(__file__).with_name('prepare-automation-workspace-qa.py'))
packager = importlib.util.module_from_spec(spec)
spec.loader.exec_module(packager)
packager.NAME = 'audition-worker'
packager.BUILD = '43'
packager.OUT = packager.ROOT / 'qa/generated/audition-worker'
packager.APP = packager.OUT / '써클러 통합 검증.app'
packager.FIXTURE = packager.SOURCE.with_name('audition-worker.circlr')

if __name__ == '__main__':
    packager.main()
    if '--candidate' not in sys.argv:
        path = packager.FIXTURE / 'manifest.json'
        project = json.loads(path.read_text())
        track = next(t for t in project['tracks'] if t['id'] == '7E0D9016-E91D-4325-B807-033F233E32EA')
        track['instrument'] = dict(kind='sampler', program=0, drums=False,
                                   sample=dict(assetID=project['assets'][0]['id'], rootPitch=60, oneShot=False))
        path.write_text(json.dumps(project, ensure_ascii=False, indent=2) + '\n')
    sources = ['Resources/Info.plist', 'Sources/CirclrAudio/AuditionTransport.swift', 'Sources/CirclrAudio/ProductionInstrument.swift',
               'Sources/CirclrApp/AppStore.swift', 'Sources/CirclrApp/AuditionWorkspace.swift', 'Sources/CirclrApp/RootView.swift',
               'Sources/CirclrApp/PlaybackOutputStatus.swift', 'Sources/CirclrApp/AgentWorkspace.swift']
    (packager.OUT / 'source-hashes.json').write_text(json.dumps({name: hashlib.sha256((packager.ROOT / name).read_bytes()).hexdigest() for name in sources}, indent=2) + '\n')
