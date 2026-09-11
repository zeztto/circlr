#!/usr/bin/env python3
"""Read-only checks for build101 final2; failed earlier screenshots are excluded."""
import hashlib
import importlib.util
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'qa/generated/header-compact'
spec=importlib.util.spec_from_file_location('checks',Path(__file__).with_name('check-midi-compact-evidence.py'))
c=importlib.util.module_from_spec(spec);spec.loader.exec_module(c)

def load(name):return json.loads((OUT/(name+'.json')).read_text())

def main():
    package=load('final2/package')
    assert package['build']=='101' and 'D0CD2CF6-964B-328D-B85A-72935E68A3C3' in package['uuid']
    initial=load('final/fixture-initial')
    names=['compact','name-roundtrip','automation','settings','connections','parent','reopened']
    captures={name:load('final2/'+name) for name in names}
    for name,value in captures.items():
        c.guard(value,package,36)
        assert c.music(value['manifest'])==c.music(initial),name
    for name in ['automation','settings','connections']:
        view=captures[name]['manifest']['hierarchyView']
        assert view['workspace']['page']==name
        assert view['selection']['music']['nodeID']=='instrument:7E0D9016-E91D-4325-B807-033F233E32EA'
    assert captures['compact']['state']['selectedNoteIDs']==captures['name-roundtrip']['state']['selectedNoteIDs']
    assert 'section' in captures['parent']['manifest']['hierarchyView']['selection']
    assert captures['parent']['manifest']==captures['reopened']['manifest']
    fixture=Path(package['fixture'])
    assert json.loads((fixture/'manifest.json').read_text())==captures['reopened']['manifest']
    origin=load('final/fixture-origin')
    assert hashlib.sha256((Path(origin['path'])/'manifest.json').read_bytes()).hexdigest()==origin['sha256']
    for asset in initial['assets']:
        path=Path(asset['path']);assert not path.is_absolute() and '..' not in path.parts
        assert hashlib.sha256((fixture/path).read_bytes()).hexdigest()==asset['checksum']
    for name in ['name-wide','name-roundtrip']:
        ax=(OUT/'final2'/(name+'.ax.txt')).read_text()
        assert 'Value: 긴 이름 입력 중 줌 전환 검증' in ax
        focused=ax.split('The focused UI element is')[-1]
        assert '서클 이름' in focused and '긴 이름 입력 중 줌 전환 검증' in focused
        assert '상위 서클로 축소' in ax and 'Return·Tab으로 적용' in ax
    started=load('final2/reopen-job');completed=load('final2/reopen-completed')
    assert completed['job']['id']==started['jobID'] and completed['job']['state']=='completed'
    assert completed['job']['path']==package['fixture'] and completed['revision']==36
    print(json.dumps({'status':'passed','snapshots':len(names),'draftAX':2,'assets':2,'physicalAudioAttempts':0,'musicRevision':36}))

if __name__=='__main__':main()
