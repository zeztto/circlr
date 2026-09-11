#!/usr/bin/env python3
"""Package build65 and an authored project with distinct inherited and stored values."""
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import uuid

spec=importlib.util.spec_from_file_location('packager',Path(__file__).with_name('prepare-automation-workspace-qa.py'))
packager=importlib.util.module_from_spec(spec);spec.loader.exec_module(packager)
packager.NAME='music-settings';packager.BUILD='65'
packager.OUT=packager.ROOT/'qa/generated/music-settings';packager.APP=packager.OUT/'써클러 통합 검증.app'
packager.FIXTURE=packager.SOURCE.with_name('music-settings.circlr')

if __name__=='__main__':
    packager.main()
    if '--candidate' not in sys.argv:
        path=packager.FIXTURE/'manifest.json';p=json.loads(path.read_text())
        p['album']['compositions'][0]['settings']['tempo']={'source':'local','value':90}
        p['sections'][0]['settings']['tempo']={'source':'local','value':100}
        use=p['arrangements'][0]['uses'][0];use['settings']['tempo']={'source':'inherit','value':132}
        pattern=str(uuid.uuid5(uuid.NAMESPACE_URL,'circlr-integration-qa/music-settings/pattern')).upper()
        p['patterns']=[dict(id=pattern,name='직접 만든 4박 킥',length=4,meter=dict(numerator=4,denominator=4),trackID=p['tracks'][0]['id'],
            notes=[dict(id=str(uuid.uuid5(uuid.NAMESPACE_URL,'circlr-integration-qa/music-settings/note/'+str(i))).upper(),beat=i,length=.25,pitch=36,velocity=96) for i in range(4)],audio=[])]
        use['settings']['rhythm']={'source':'inherit','value':{'patternID':pattern}}
        path.write_text(json.dumps(p,ensure_ascii=False,indent=2)+'\n');(packager.OUT/'fixture-initial.json').write_bytes(path.read_bytes())
    sources=['Resources/Info.plist','Sources/CirclrApp/MusicContextEditor.swift','Sources/CirclrApp/InlineCircleEditor.swift','Sources/CirclrApp/PortKeyboardControls.swift']
    (packager.OUT/'source-hashes.json').write_text(json.dumps({name:hashlib.sha256((packager.ROOT/name).read_bytes()).hexdigest() for name in sources},indent=2)+'\n')
