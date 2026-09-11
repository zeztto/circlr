#!/usr/bin/env python3
"""Check native MIDI inspector edits against the complete owned song and signed candidates."""
import copy
import hashlib
import json
from pathlib import Path
import plistlib
import runpy
import subprocess
import unicodedata

ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'qa/generated/midi-inspector'
CAPTURES={'baseline':14,'transpose-initial':15,'initial-undone':16,'refined-baseline':16,
          'relative-applied':20,'invalid-inputs-unchanged':20,'relative-undone':24,'single-velocity':25,
          'mcp-applied':27,'duplicate-applied':28,'delete-applied':30,'all-undone':32,'orbit-velocity':33,'final-restored':34}
def load(name):return json.loads((OUT/(name+'.json')).read_text())
def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def music(p):
    p=copy.deepcopy(p)
    for key in ['hierarchyView','musicRevision']:p.pop(key,None)
    return p
def notes(p):return p['arrangements'][0]['uses'][0]['addedLanes'][0]['notes']
def ax(name):return (OUT/(name+'.ax.txt')).read_text()
def contains(name,*parts):return any(all(part in line for part in parts) for line in ax(name).splitlines())

def main():
    baseline=music(load('fixture-initial'));ids={n['id'] for n in notes(baseline)}
    captures={name:load(name) for name in CAPTURES}
    for name,revision in CAPTURES.items():
        d=captures[name];s=d['state'];p=d['manifest'];expected=copy.deepcopy(baseline);n=notes(expected)
        assert s['projectID']==p['id']=='2FB6C728-FC54-5318-B685-B297E9DF0CD1',name
        assert s['runtime']['build']=='69' and s['runtime']['bundleID']=='com.circlr.integrationqa'
        assert s['revision']==p['musicRevision']==revision and not s['dirty'],name
        assert s['job']['state']=='completed' and not s['playback']['playing']
        assert s['output']['attempts']==s['audition']['attempts']==0
        assert not s['recording']['midi'] and not s['recording']['busy'] and s['library']['folders']==1
        if name=='transpose-initial':
            for note in n:note['pitch']+=2
        if name in ['relative-applied','invalid-inputs-unchanged']:
            for note in n:note['pitch']+=2;note['beat']+=1;note['length']+=.25;note['velocity']+=5
        if name=='single-velocity':n[1]['velocity']=84
        if name in ['mcp-applied','duplicate-applied','delete-applied']:
            for note in n:note['length']+=.125;note['velocity']-=5
        if name=='duplicate-applied':
            actual=notes(p);extra=actual[3:];assert len(extra)==3
            assert len({note['id'] for note in actual})==6 and not ids.intersection(note['id'] for note in extra)
            copied=copy.deepcopy(n)
            for original,added in zip(copied,extra):original['id']=added['id'];original['beat']+=2.75
            n.extend(copied)
        if name=='delete-applied':n.clear()
        if name in ['orbit-velocity','final-restored']:expected['circleLayout']='orbit'
        if name=='orbit-velocity':
            for note in n:note['velocity']-=10
        assert music(p)==expected,name # Every other use, original, clip, effect and binding must match.
    for name in ['multi-refined','orbit-multi']:
        for label in ['음정 이동','시작 이동','길이 변경','세기 변경']:assert contains(name,'text field','MIDI 선택 '+label)
        assert contains(name,'button Description: 선택 MIDI 노트 복제') and contains(name,'button Description: 선택 MIDI 노트 삭제')
    for label in ['음높이','시작 박','길이 박','세기']:assert contains('single-piano','text field','Description: MIDI '+label+',')
    assert contains('single-velocity','MIDI 세기,','Value: 84')
    assert contains('length-rejected','text field','모든 노트의 길이를 1/32박 이상')
    assert contains('velocity-rejected','text field','세기 차이를 유지하려면 모든 노트를 1–127')
    assert contains('draft-stale-rejected','text field','편집 대상이 변경되었습니다','Value: 4')
    assert 'stale_revision' in (OUT/'mcp-stale-rejected.txt').read_text()
    request=load('mcp-relative-result')['request'];assert [op['edit'] for op in request]==['length_delta','velocity_delta']
    assert request[0]['beatOffset']==.125 and request[1]['velocityOffset']==-5
    for name in ['tab-to-start','tab-to-length','tab-to-velocity']:assert 'Selected text: ```\n0\n```' in ax(name)
    assert captures['relative-applied']['state']['selectedNoteIDs']==sorted(ids)
    assert not captures['delete-applied']['state']['selectedNoteIDs']
    screens=list(OUT.glob('*.jpg'));assert len(screens)==25
    for shot in screens:assert shot.stat().st_size>10000 and '통합 편집 검증' in ax(shot.stem),shot.name
    sources=load('refined/source-hashes');assert len(sources)==8
    for name,value in sources.items():assert digest(ROOT/name)==value,name
    for name,value in load('source-hashes').items():
        assert digest(OUT/'initial-MIDINoteInspector.swift' if name=='Sources/CirclrApp/MIDINoteInspector.swift' else ROOT/name)==value,name
    sections=runpy.run_path(str(ROOT/'qa/check-library-evidence.py'))['sections']
    app=OUT/'refined/써클러 통합 검증.app';compiled=sections(ROOT/'.build/integration-release/release/circlr')
    assert len(compiled)==37 and compiled==sections(app/'Contents/MacOS/circlr')
    for candidate in [OUT/'써클러 통합 검증.app',app]:
        info=plistlib.loads((candidate/'Contents/Info.plist').read_bytes())
        assert (info['CFBundleVersion'],info['CFBundleShortVersionString'],info['CFBundleIdentifier'])==('69','0.20.0','com.circlr.integrationqa')
        subprocess.run(['codesign','--verify','--deep','--strict',str(candidate)],check=True)
        kit=candidate/'Contents/Resources/Codex';files=json.loads((kit/'manifest.json').read_text())['files'];assert len(files)==25
        for name,value in files.items():assert digest(kit/name)==value
    fixture=Path(captures['final-restored']['state']['path']);original=fixture.with_name('studio.circlr')
    assert json.loads((fixture/'manifest.json').read_text())==captures['final-restored']['manifest']
    assert digest(original/'manifest.json')=='12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d'
    for asset in baseline['assets']:
        for folder in [fixture,original]:assert digest(folder/asset['path'])==asset['checksum']
    assert 'Executed 491 tests, with 0 failures' in (ROOT/'.build/midi-inspector-tests.log').read_text()
    assert 'Ran 29 tests' in (ROOT/'.build/midi-inspector-python-tests.log').read_text()
    assert 'Build complete!' in (ROOT/'.build/midi-inspector-refined-release.log').read_text()
    ps=unicodedata.normalize('NFC',subprocess.check_output(['ps','-axo','pid,command'],text=True))
    assert not any('/qa/generated/midi-inspector/' in line and line.endswith('/Contents/MacOS/circlr') for line in ps.splitlines())
    result=dict(status='passed',snapshots=len(captures),screens=len(screens),sourceFiles=len(sources),executableSections=len(compiled),kitFiles=len(files),physicalAudioAttempts=0)
    (OUT/'verification.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))

if __name__=='__main__':main()
