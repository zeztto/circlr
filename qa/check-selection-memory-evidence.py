#!/usr/bin/env python3
"""Compare native selection restoration to full music and immutable build artifacts."""
import copy
import hashlib
import json
from pathlib import Path
import plistlib
import runpy
import subprocess
import unicodedata
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'qa/generated/selection-memory'
CAPTURES={'baseline':14,'midi-selected':14,'midi-second-selected':14,'midi-returned':14,'midi-original':14,'midi-use-restored':14,'midi-reopened':14,
 'pan-selected':17,'automation-returned':17,'automation-reopened':17,'deleted-point-return':18,'audio-first':19,'audio-second':19,'audio-returned':19,
 'audio-trimmed':20,'audio-second-returned':20,'audio-trim-returned':20,'audio-undo-initial':21,'refined-audio-undo':23,'refined-audio-redo':24,
 'refined-audio-restored':25,'audio-reopened':25,'refined-midi-edit':26,'refined-midi-undo-returned':27,'refined-midi-redo':28,'final-restored':29,'final-reopened':29,'guard-midi-undo':31,'guard-audio-undo':33,'guard-reopened':33}
def load(name):return json.loads((OUT/(name+'.json')).read_text())
def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def music(p):
    p=copy.deepcopy(p)
    for key in ['hierarchyView','musicRevision']:p.pop(key,None)
    return p
def use(p):return p['arrangements'][0]['uses'][0]
def notes(p):return use(p)['addedLanes'][0]['notes']
def selection(d):return d['manifest']['hierarchyView']['workspace']['selection']
def has(name,*parts):return any(all(p in line for p in parts) for line in (OUT/(name+'.ax.txt')).read_text().splitlines())
def main():
    baseline=music(load('fixture-initial'));ids=sorted(n['id'] for n in notes(baseline));captures={n:load(n) for n in CAPTURES}
    curves=use(captures['pan-selected']['manifest'])['graphEdits']['addedNodes'][0]['automation']
    assert [c['parameter'] for c in curves]==['gain','pan']
    for c in curves:
        length=2 if c['parameter']=='gain' else 1;assert c['enabled'] and len(c['points'])==length
        for i,p in enumerate(c['points']):assert p==dict(id=p['id'],beat=i*.25,value=1 if c['parameter']=='gain' else 0,shape='linear')
    gainID=curves[0]['points'][1]['id'];panID=curves[1]['points'][0]['id'];assert gainID!=panID
    for name,rev in CAPTURES.items():
        d=captures[name];s=d['state'];p=d['manifest'];expected=copy.deepcopy(baseline)
        assert s['projectID']==p['id']=='9205108A-825F-5F0E-A12B-B6B33497DB3B'
        assert s['runtime']['build']=='71' and s['runtime']['bundleID']=='com.circlr.integrationqa'
        assert s['revision']==p['musicRevision']==rev and not s['dirty']
        assert not s['playback']['playing'] and s['output']['attempts']==s['audition']['attempts']==0
        assert not s['recording']['midi'] and not s['recording']['busy']
        if name in ['pan-selected','automation-returned','automation-reopened','deleted-point-return']:
            value=copy.deepcopy(curves)
            if name=='deleted-point-return':value[0]['points']=value[0]['points'][:1]
            use(expected)['graphEdits']['addedNodes'][0]['automation']=value
        if name in ['audio-trimmed','audio-second-returned','audio-trim-returned','refined-audio-redo']:
            lane=copy.deepcopy(expected['sections'][0]['lanes'][0]);assert lane['id']=='7F32786A-C5A8-5B33-BEA3-0D5D029F3C14'
            lane['audio'][0]['sourceStart']=2;lane['audio'][0]['duration']=30;use(expected)['laneOverrides'][lane['id']]=lane
        if name in ['refined-midi-edit','refined-midi-redo']:
            for n in notes(expected):n['pitch']+=2
        assert music(p)==expected,name # Compare all other uses, original lanes, graph bindings, assets and settings.
    for name in ['midi-selected','midi-returned','midi-use-restored','midi-reopened','refined-midi-edit','refined-midi-undo-returned','refined-midi-redo','final-restored','final-reopened','guard-midi-undo','guard-reopened']:
        d=captures[name];assert d['state']['selectedNoteIDs']==ids and selection(d)['noteIDs']==ids,name
        assert selection(d)['anchorID'] in ids
    assert captures['midi-second-selected']['state']['selectedNoteIDs']==['96B02BAF-8DC2-4E10-AD89-D4D5F66DEDA9']
    assert not captures['midi-original']['state']['selectedNoteIDs']
    assert captures['pan-selected']['state']['automationEditor']['selectedPointID']==panID
    for name in ['automation-returned','automation-reopened']:
        assert captures[name]['state']['automationEditor']['selectedPointID']==gainID
        assert selection(captures[name])['automationPoints']=={'gain':gainID,'pan':panID}
    assert captures['deleted-point-return']['state']['automationEditor']['selectedPointID'] is None
    for name in ['audio-first','audio-returned','audio-trimmed','audio-trim-returned','refined-audio-undo','refined-audio-redo','refined-audio-restored','audio-reopened','guard-audio-undo']:
        assert selection(captures[name])['audioSourcePosition']==7.25,name
    for name in ['audio-second','audio-second-returned']:assert selection(captures[name])['audioSourcePosition']==2.5
    assert selection(captures['audio-undo-initial'])['audioSourcePosition']==5.25 # Initial candidate finding, not a pass.
    for name in ['midi-returned','midi-use-restored','midi-reopened','final-reopened']:assert has(name,'MIDI 노트 선택 · 3개')
    assert has('gain-returned','선택 점 2/2') and has('deleted-point-return','선택 점 0/1')
    assert has('refined-audio-undo','오디오 분할 위치 초','Value: 7.250')
    assert has('refined-audio-redo','오디오 분할 위치 초','Value: 5.250')
    assert has('audio-reopened','오디오 분할 위치 초','Value: 7.250')
    for prefix in ['midi','automation','audio','final','guard']:
        assert load(prefix+'-open-job')['jobID']==load(prefix+'-open-completed')['job']['id']
        assert load(prefix+'-open-completed')['job']['state']=='completed'
    sources=load('final/source-hashes');assert len(sources)==8
    for name,value in sources.items():assert digest(ROOT/name)==value,name
    for candidate,old in [('', 'initial-AppStore.swift'),('refined/','refined-AppStore.swift')]:
        for name,value in load(candidate+'source-hashes').items():
            assert digest(OUT/old if name.endswith('/AppStore.swift') else ROOT/name)==value,name
    sections=runpy.run_path(str(ROOT/'qa/check-library-evidence.py'))['sections'];compiled=sections(ROOT/'.build/integration-release/release/circlr')
    assert len(compiled)==37 and compiled==sections(OUT/'final/써클러 통합 검증.app/Contents/MacOS/circlr')
    for folder in ['', 'refined','final']:
        app=OUT/folder/'써클러 통합 검증.app';p=plistlib.loads((app/'Contents/Info.plist').read_bytes())
        assert (p['CFBundleVersion'],p['CFBundleShortVersionString'],p['CFBundleIdentifier'])==('71','0.20.0','com.circlr.integrationqa')
        subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
        kit=app/'Contents/Resources/Codex';files=json.loads((kit/'manifest.json').read_text())['files'];assert len(files)==25
        for name,value in files.items():assert digest(kit/name)==value
    fixture=Path(captures['guard-reopened']['state']['path']);original=fixture.with_name('studio.circlr')
    assert digest(original/'manifest.json')=='12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d'
    assert music(json.loads((fixture/'manifest.json').read_text()))==baseline
    for asset in baseline['assets']:
        for folder in [original,fixture]:assert digest(folder/asset['path'])==asset['checksum']
    assert 'Executed 496 tests, with 0 failures' in (ROOT/'.build/selection-memory-tests-fixed.log').read_text()
    assert 'Ran 29 tests' in (ROOT/'.build/selection-memory-python-tests.log').read_text()
    assert 'Build complete!' in (ROOT/'.build/selection-memory-final-release.log').read_text()
    screens=list(OUT.glob('*.jpg'));assert len(screens)==34
    for shot in screens:assert shot.stat().st_size>10000 and '통합 편집 검증' in (OUT/(shot.stem+'.ax.txt')).read_text()
    ps=unicodedata.normalize('NFC',subprocess.check_output(['ps','-axo','pid,command'],text=True))
    assert not any('/qa/generated/selection-memory/' in l and l.endswith('/Contents/MacOS/circlr') for l in ps.splitlines())
    result=dict(status='passed',snapshots=len(captures),screens=len(screens),sourceFiles=len(sources),executableSections=len(compiled),kitFiles=len(files),physicalAudioAttempts=0)
    (OUT/'verification.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
if __name__=='__main__':main()
