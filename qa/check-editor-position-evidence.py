#!/usr/bin/env python3
"""Validate editor view persistence, exact music preservation and both signed QA candidates."""
import copy
import hashlib
import json
from pathlib import Path
import plistlib
import runpy
import subprocess
import unicodedata

ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'qa/generated/editor-position'
CAPTURES={'baseline':14,'step-saved':14,'drum-saved':14,'piano-saved':14,'piano-warm-saved':14,
          'audio-settings-saved':14,'automation-undone':18,'automation-fitted-saved':22,'automation-reopened':22,
          'orbit-saved':22,'orbit-cold-saved':22,'shorter-saved':23,'length-restored':22,'drum-warm-saved':22,
          'refined-opened':22,'low-pitch-saved':22,'refined-piano-saved':22,'refined-piano-reopened':22,'final-restored':22}
def load(name):return json.loads((OUT/(name+'.json')).read_text())
def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def music(p):
    p=copy.deepcopy(p)
    for key in ['hierarchyView','musicRevision','circleLayout']:p.pop(key,None)
    return p
def ax(name):return (OUT/(name+'.ax.txt')).read_text()
def contains(name,*parts):return any(all(part in line for part in parts) for line in ax(name).splitlines())
def editor(name):return load(name)['manifest']['hierarchyView']['workspace']['editor']
def scroll(name,index=0):
    return float([line for line in ax(name).splitlines() if 'scroll bar (settable, float)' in line][index].split()[-1])

def main():
    base=music(load('fixture-initial'));captures={name:load(name) for name in CAPTURES}
    for name,revision in CAPTURES.items():
        d=captures[name];p=d['manifest'];s=d['state'];expected=copy.deepcopy(base)
        assert s['projectID']==p['id']=='926DF9B0-369A-57F8-A08F-DD2221CD5999',name
        assert s['runtime']['build']=='68' and s['runtime']['bundleID']=='com.circlr.integrationqa'
        assert s['revision']==p['musicRevision']==revision and not s['dirty'],name
        assert s['job']['state']=='completed' and not s['playback']['playing']
        assert s['output']['attempts']==s['audition']['attempts']==0
        assert not s['recording']['midi'] and not s['recording']['busy'] and s['library']['folders']==1
        if name=='shorter-saved':expected['arrangements'][0]['uses'][0]['barsOverride']=1
        assert music(p)==expected,name
    assert editor('step-saved')['steps']['page']==2 and editor('step-saved')['topPitch']==86
    assert editor('step-saved')['scrolls']['steps']['y']>100
    for name in ['step-position','step-return','first-circle-return']:
        assert contains(name,'스텝 페이지,','Value: 3') and contains(name,'가장 높은 음','C♯6')
        assert abs(scroll(name)-.7)<.002
    for name in ['drum-saved','drum-warm-saved']:
        s=editor(name)['steps'];assert s['page']==1 and s['subdivisions']==8 and s['drumMode'] and s['extraPitches']==[97]
    assert editor('drum-saved')['steps']['rowQuery']=='97' and editor('drum-warm-saved')['steps']['rowQuery']=='73'
    assert contains('drum-reopened','드럼 행 검색,','Value: 97') and contains('drum-warm-edited','드럼 행 검색,','Value: 73')
    for index in [0,1]:
        for name in ['piano-return','piano-reopened','piano-warm-edited']:assert abs(scroll(name,index)-scroll('piano-position',index))<.002
    assert editor('piano-warm-saved')['topPitch']==98
    assert editor('piano-warm-saved')['scrolls']['piano']==editor('piano-saved')['scrolls']['piano']
    for name in ['audio-position','audio-scope-return','audio-reopened']:assert contains(name,'container Description: 오디오 파형','원본 표시 16.000부터 24.000초')
    assert contains('audio-original-fresh','container Description: 오디오 파형','원본 표시 0.000부터 32.000초')
    assert contains('audio-original-position','container Description: 오디오 파형','원본 표시 8.000부터 24.000초')
    for name in ['settings-page-return','settings-reopened']:assert abs(scroll(name)-scroll('settings-scroll-set'))<.004
    for name in ['automation-fitted','automation-fitted-return','automation-fitted-undone','automation-reopened']:
        assert contains(name,'container Description: 오토메이션 곡선','표시 위치 1–129박')
    assert contains('automation-pan-separate','container Description: 오토메이션 곡선','표시 위치 1–65박')
    assert captures['automation-fitted-saved']['state']['automationEditor']['displayBeats']==128
    for name in ['orbit-position','orbit-return','orbit-cold-open']:assert contains(name,'container Description: MIDI 궤도','5–6마디 · E♭4–D6')
    assert editor('orbit-cold-saved')['orbit']==dict(barsPerPage=2,page=3,pitchRows=24,topPitch=86)
    assert editor('shorter-saved')['orbit']['page']==editor('shorter-saved')['steps']['page']==0
    assert contains('shorter-step','스텝 페이지,','Value: 1') and contains('shorter-orbit','1–1마디 / 1')
    assert editor('low-pitch-saved')['topPitch']==27
    assert captures['refined-piano-saved']['manifest']==captures['refined-piano-reopened']['manifest']
    for index in [0,1]:assert abs(scroll('refined-piano-position',index)-scroll('refined-piano-reopened',index))<.002
    assert captures['final-restored']['manifest']==captures['orbit-cold-saved']['manifest']
    excluded={'refined-opened','low-pitch-opened'}
    screens=[shot for shot in OUT.glob('*.jpg') if shot.stem not in excluded];assert len(screens)==43
    for name in excluded:assert 'menu button 새 앨범' in ax(name)
    for shot in screens:assert shot.stat().st_size>10000 and '통합 편집 검증' in ax(shot.stem),shot.name
    sources=load('refined/source-hashes');assert len(sources)==17
    for name,value in sources.items():assert digest(ROOT/name)==value,name
    initial=load('source-hashes')
    for name,value in initial.items():assert digest(OUT/'initial-EditorWorkspace.swift' if name=='Sources/CirclrApp/EditorWorkspace.swift' else ROOT/name)==value,name
    sections=runpy.run_path(str(ROOT/'qa/check-library-evidence.py'))['sections']
    app=OUT/'refined/써클러 통합 검증.app';compiled=sections(ROOT/'.build/integration-release/release/circlr')
    assert len(compiled)==37 and compiled==sections(app/'Contents/MacOS/circlr')
    for candidate in [OUT/'써클러 통합 검증.app',app]:
        info=plistlib.loads((candidate/'Contents/Info.plist').read_bytes())
        assert (info['CFBundleVersion'],info['CFBundleShortVersionString'],info['CFBundleIdentifier'])==('68','0.20.0','com.circlr.integrationqa')
        subprocess.run(['codesign','--verify','--deep','--strict',str(candidate)],check=True)
        kit=candidate/'Contents/Resources/Codex';files=json.loads((kit/'manifest.json').read_text())['files'];assert len(files)==25
        for name,value in files.items():assert digest(kit/name)==value
    fixture=Path(captures['final-restored']['state']['path']);original=fixture.with_name('studio.circlr')
    assert json.loads((fixture/'manifest.json').read_text())==captures['final-restored']['manifest']
    assert digest(original/'manifest.json')=='12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d'
    for asset in base['assets']:
        for folder in [fixture,original]:assert digest(folder/asset['path'])==asset['checksum']
    assert 'Executed 485 tests, with 0 failures' in (ROOT/'.build/editor-position-tests.log').read_text()
    assert 'Ran 28 tests' in (ROOT/'.build/editor-position-python-tests.log').read_text()
    assert 'Build complete!' in (ROOT/'.build/editor-position-refined-release.log').read_text()
    ps=unicodedata.normalize('NFC',subprocess.check_output(['ps','-axo','pid,command'],text=True))
    assert not any('/qa/generated/editor-position/' in line and line.endswith('/Contents/MacOS/circlr') for line in ps.splitlines())
    result=dict(status='passed',snapshots=len(captures),screens=len(screens),sourceFiles=len(sources),executableSections=len(compiled),kitFiles=len(files),physicalAudioAttempts=0)
    (OUT/'verification.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))

if __name__=='__main__':main()
