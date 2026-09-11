#!/usr/bin/env python3
"""Verify native selection/edit evidence, complete music preservation and signed builds."""
import copy
import hashlib
import json
from pathlib import Path
import plistlib
import runpy
import subprocess
import unicodedata

ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'qa/generated/accessibility-geometry'
CAPTURES={'baseline-state':14,'row-selected':14,'step-input':15,'initial-undone':16,'refined-row':16,
          'refined-input':17,'piano-selected':18,'automation-point':20,'orbit-selected':22,'port-selected':22,
          'cable-selected':22,'refined-cell-input':23,'final-restored':24,'reopened':24}
def load(name):return json.loads((OUT/(name+'.json')).read_text())
def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def music(p):
    p=copy.deepcopy(p)
    for k in ['hierarchyView','musicRevision']:p.pop(k,None)
    return p
def lane(p):return p['arrangements'][0]['uses'][0]['addedLanes'][0]
def contains(name,*parts):
    return any(all(part in line for part in parts) for line in (OUT/(name+'.ax.txt')).read_text().splitlines())

def main():
    baseline=music(load('fixture-initial'));originalIDs={n['id'] for n in lane(baseline)['notes']}
    orbital={'orbit-selected','port-selected','cable-selected','refined-cell-input','final-restored','reopened'}
    captures={name:load(name) for name in CAPTURES}
    for name,revision in CAPTURES.items():
        s=captures[name]['state'];p=captures[name]['manifest'];expected=copy.deepcopy(baseline)
        assert s['projectID']==p['id']=='E95D8338-1A25-5D4B-A44C-5DEDDDB6B8F4'
        assert s['runtime']['build']==('69' if name=='baseline-state' else '70') and s['runtime']['bundleID']=='com.circlr.integrationqa'
        assert s['revision']==p['musicRevision']==revision and not s['dirty'],name
        assert s['output']['attempts']==s['audition']['attempts']==0 and not s['playback']['playing']
        assert not s['recording']['midi'] and not s['recording']['busy'] and (s['job'] is None or s['job']['state']=='completed')
        if name in orbital:expected['circleLayout']='orbit'
        if name in ['step-input','refined-input','refined-cell-input']:
            added=[n for n in lane(p)['notes'] if n['id'] not in originalIDs];assert len(added)==1
            note=added[0];pitch={'step-input':69,'refined-input':66,'refined-cell-input':73}[name]
            assert note==dict(id=note['id'],beat=.5,length=.225,pitch=pitch,velocity=96),name
            lane(expected)['notes'].append(note)
            assert s['selectedNoteIDs']==[note['id']]
        if name=='automation-point':
            node=p['arrangements'][0]['uses'][0]['graphEdits']['addedNodes'][0]
            curve=node['automation'][0];points=curve['points'];assert len(points)==2 and points[0]['id']!=points[1]['id']
            assert curve==dict(enabled=True,parameter='gain',points=[dict(id=pt['id'],beat=i*.25,value=1,shape='linear') for i,pt in enumerate(points)])
            expected['arrangements'][0]['uses'][0]['graphEdits']['addedNodes'][0]['automation']=[curve]
        assert music(p)==expected,name # Other uses, original notes, audio, edges, instruments, assets and layouts all match.
    assert captures['piano-selected']['state']['selectedNoteIDs']==['96B02BAF-8DC2-4E10-AD89-D4D5F66DEDA9']
    assert captures['orbit-selected']['state']['selectedNoteIDs']==['532E9152-5CC2-4864-BD08-1A749B5780B5']
    assert 'elementHasNoFrame' in (OUT/'baseline-row-error.txt').read_text()
    for name,pitch in [('refined-scrolled-row','66 · F♯4'),('refined-top-row','69 · A4')]:
        assert contains(name,'스텝 편집기','Value: '+pitch+' · 3스텝'),name
    assert contains('drum-filter','드럼 행 검색','Value: 73')
    assert contains('piano-selected','MIDI 음높이','Value: 69') and contains('piano-resized','MIDI 음높이','Value: 66')
    assert contains('orbit-selected','MIDI 음높이','Value: 73')
    assert contains('automation-point','1번 점','Value: 선택됨')
    assert contains('port-selected','(selected)','출력별 신호 검증 · IN 재생 경로')
    assert contains('cable-selected','(selected)','케이블 · 통합 키보드 MIDI')
    assert contains('circle-opened','text field','서클 이름','Value: 통합 키보드 MIDI')
    assert contains('reopened','스텝 편집기','Value: 73 · C♯5 · 1스텝')
    assert load('open-completed')['job']['state']=='completed'
    assert load('open-completed')['job']['id']==load('open-job')['jobID']
    screens=list(OUT.glob('*.jpg'));assert len(screens)==21
    for shot in screens:assert shot.stat().st_size>10000 and '통합 편집 검증' in (OUT/(shot.stem+'.ax.txt')).read_text()
    hashes=load('refined/source-hashes');assert len(hashes)==8
    for name,value in hashes.items():assert digest(ROOT/name)==value,name
    for name,value in load('final/source-hashes').items():
        assert digest(OUT/'initial-StepEditor.swift' if name.endswith('/StepEditor.swift') else ROOT/name)==value,name
    sections=runpy.run_path(str(ROOT/'qa/check-library-evidence.py'))['sections']
    final=OUT/'refined/써클러 통합 검증.app';compiled=sections(ROOT/'.build/integration-release/release/circlr')
    assert len(compiled)==37 and compiled==sections(final/'Contents/MacOS/circlr')
    for folder,build in [('baseline','69'),('final','70'),('refined','70')]:
        app=OUT/folder/'써클러 통합 검증.app';info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
        assert (info['CFBundleVersion'],info['CFBundleShortVersionString'],info['CFBundleIdentifier'])==(build,'0.20.0','com.circlr.integrationqa')
        subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
        kit=app/'Contents/Resources/Codex';files=json.loads((kit/'manifest.json').read_text())['files'];assert len(files)==25
        for name,value in files.items():assert digest(kit/name)==value
    assert sections(OUT/'baseline/써클러 통합 검증.app/Contents/MacOS/circlr')==sections(ROOT/'qa/generated/midi-inspector/refined/써클러 통합 검증.app/Contents/MacOS/circlr')
    fixture=Path(captures['reopened']['state']['path']);original=fixture.with_name('studio.circlr')
    assert music(json.loads((fixture/'manifest.json').read_text()))==music(captures['reopened']['manifest'])
    assert digest(original/'manifest.json')=='12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d'
    for asset in baseline['assets']:
        for folder in [fixture,original]:assert digest(folder/asset['path'])==asset['checksum']
    assert 'Executed 491 tests, with 0 failures' in (ROOT/'.build/accessibility-geometry-tests.log').read_text()
    assert 'Ran 29 tests' in (ROOT/'.build/accessibility-geometry-python-tests.log').read_text()
    assert '14 AppKit checks passed' in (ROOT/'.build/accessibility-geometry-checks.log').read_text()
    assert 'Build complete!' in (ROOT/'.build/accessibility-geometry-refined-release.log').read_text()
    ps=unicodedata.normalize('NFC',subprocess.check_output(['ps','-axo','pid,command'],text=True))
    assert not any('/qa/generated/accessibility-geometry/' in line and line.endswith('/Contents/MacOS/circlr') for line in ps.splitlines())
    result=dict(status='passed',snapshots=len(captures),screens=len(screens),appKitChecks=14,sourceFiles=len(hashes),executableSections=len(compiled),kitFiles=len(files),physicalAudioAttempts=0)
    (OUT/'verification.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
if __name__=='__main__':main()
