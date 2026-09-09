#!/usr/bin/env python3
"""Verify build66 session navigation, exact music changes and the signed native app."""
import copy
import hashlib
import json
from pathlib import Path
import plistlib
import runpy
import subprocess
import unicodedata

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'qa/generated/workspace-return'
CASES={'baseline':14,'connection-restored':14,'transition-edited':15,'transition-undone':16,
       'reconnect-pending':16,'other-section-fresh':16,'reconnect-restored':16,'hidden-deleted':17,
       'deleted-reconnect-return':17,'deletion-undone':18,'active-transition-deleted':19,
       'active-deletion-undone':20,'header-keyboard-return':20,'audio-restored':20,'midi-restored':20,
       'scope-restored':20,'explicit-audio-port':20,'before-session-reset':20,'reopened':20,
       'new-session-connections':20,'name-committed-switch':21,'final-restored':22,'commit-opened':22,
       'reconnect-applied':23,'reconnect-undone':24,'keyboard-opened':24,'keyboard-return-verified':24}
STATE_SCREENS=['pending-target','pending-directions','settings-from-connections','connection-restored',
               'transition-open','section-from-transition','transition-return','transition-to-connections',
               'reconnect-pending','other-section-fresh','reconnect-restored','hidden-reconnect',
               'deleted-reconnect-return','transition-before-delete','active-transition-deleted',
               'header-keyboard-connection','header-keyboard-return','audio-query-pending','audio-query-restored',
               'midi-pending','instrument-settings','midi-restored','original-settings','original-fresh',
               'use-scope-restored','canvas-instrument-ports','explicit-audio-port','before-session-reset',
               'new-session-connections','name-committed-switch','final-restored',
               'commit-restored-draft','reconnect-applied','reconnect-undone']
KEYBOARD_SCREENS=['body-to-header','keyboard-transition','keyboard-connection-back','body-to-edit',
                  'keyboard-section-edit','keyboard-music-header','keyboard-music-settings']

def load(name):return json.loads((OUT/(name+'.json')).read_text())
def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def music(project):
    project=copy.deepcopy(project);project.pop('musicRevision');project.pop('hierarchyView');return project
def ax(name):return (OUT/(name+'.ax.txt')).read_text()
def contains(name,*parts):
    return any(all(part in line for part in parts) for line in ax(name).splitlines())

def main():
    captures={name:load(name) for name in CASES};baseline=music(captures['baseline']['manifest'])
    assert baseline==music(load('fixture-initial'))
    for name,revision in CASES.items():
        data=captures[name];s=data['state'];p=data['manifest'];expected=copy.deepcopy(baseline)
        assert s['projectID']=='A870E933-4C6E-5665-8127-9E4B454E5DC9'
        assert s['revision']==p['musicRevision']==revision,name
        assert s['runtime']['build']=='66' and s['runtime']['bundleID']=='com.circlr.integrationqa'
        assert not s['dirty'] and s['output']['attempts']==s['audition']['attempts']==0
        assert not s['recording']['midi'] and not s['recording']['busy'] and not s['playback']['playing']
        assert s['library']['folders']==1
        a=expected['arrangements'][0]
        if name=='transition-edited':a['edges'][1]['transition']['length']=.25
        if name in {'hidden-deleted','deleted-reconnect-return'}:
            a['edges'].pop(0);a['chosenEdges']={}
        if name=='active-transition-deleted':a['edges'].pop(1)
        if name=='name-committed-switch':a['uses'][0]['name']='인트로 · 이름 확정 검증'
        if name=='reconnect-applied':
            edge=a['edges'].pop(0);edge['to']=a['uses'][3]['id'];a['edges'].append(edge)
        assert music(p)==expected,name # Every other note, original, effect, group, port and asset is included.
    for first,second in [('before-session-reset','reopened'),('final-restored','commit-opened'),('reconnect-undone','keyboard-opened')]:
        assert captures[first]['manifest']==captures[second]['manifest'],(first,second)
        assert captures[second]['state']['job']['state']=='completed'
    for name in STATE_SCREENS+KEYBOARD_SCREENS:
        assert '통합 편집 검증' in ax(name),name
        assert (OUT/(name+'.jpg')).stat().st_size>10000,name
    for name in ['pending-directions','connection-restored','transition-to-connections']:
        for label,value in [('검색,','Value: #3'),('시작 위치,','시작 오른쪽 아래'),
                            ('대상 위치,','대상 왼쪽 위'),('표시 범위,','현재 포트')]:assert contains(name,label,value),name
        assert contains(name,'cell (selected) #3 · 도시의 밤')
    for name in ['reconnect-pending','reconnect-restored','commit-restored-draft']:
        assert contains(name,'검색,','Value: #4') and contains(name,'cell (selected) #4')
        assert contains(name,'button 재연결 적용')
    assert contains('deleted-reconnect-return','검색,','Value: #4')
    assert 'cell (selected)' not in ax('deleted-reconnect-return')
    assert '재연결 적용' not in ax('deleted-reconnect-return') and 'button (disabled) 연결' in ax('deleted-reconnect-return')
    assert '작업 전환 · 전환' not in ax('active-transition-deleted')
    assert contains('active-transition-deleted','작업 전환 · 편집','Value: 선택됨')
    for name in ['audio-query-pending','audio-query-restored']:
        assert contains(name,'검색,','Value: 믹스') and contains(name,'cell (selected) 통합 키보드 믹스')
    for name in ['midi-restored','use-scope-restored']:
        assert contains(name,'IN OUT 포트,','Value: IN MIDI') and contains(name,'검색,','Value: MIDI')
        assert contains(name,'cell (selected) 통합 키보드 MIDI')
    for name in ['original-fresh','explicit-audio-port','new-session-connections','other-section-fresh']:
        assert not contains(name,'검색,','Value:') and 'cell (selected)' not in ax(name),name
    assert contains('explicit-audio-port','IN OUT 포트,','Value: OUT 오디오')
    assert '작업 전환 · 전환' not in ax('new-session-connections')
    for name,title in [('body-to-header','전환'),('body-to-edit','편집'),('keyboard-music-header','설정')]:
        assert contains(name,'The focused UI element is','button '+title,'작업 전환 · '+title)
    for name,title in [('keyboard-transition','전환'),('keyboard-section-edit','편집'),('keyboard-music-settings','설정')]:
        assert contains(name,'작업 전환 · '+title,'Value: 선택됨')
    assert contains('keyboard-connection-back','검색,','Value: #3') and contains('keyboard-connection-back','cell (selected) #3')
    app=OUT/'final/써클러 통합 검증.app';info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
    assert (info['CFBundleVersion'],info['CFBundleShortVersionString'],info['CFBundleIdentifier'])==('66','0.20.0','com.circlr.integrationqa')
    sections=runpy.run_path(str(ROOT/'qa/check-library-evidence.py'))['sections']
    compiled=sections(ROOT/'.build/integration-release/release/circlr');assert len(compiled)==37 and compiled==sections(app/'Contents/MacOS/circlr')
    assert compiled==sections(OUT/'keyboard/써클러 통합 검증.app/Contents/MacOS/circlr')
    subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
    sources=load('final/source-hashes');assert len(sources)==9
    for name,value in sources.items():assert digest(ROOT/name)==value,name
    kit=app/'Contents/Resources/Codex';files=json.loads((kit/'manifest.json').read_text())['files'];assert len(files)==25
    for name,value in files.items():assert digest(kit/name)==value
    fixture=Path(captures['keyboard-return-verified']['state']['path']);original=fixture.with_name('studio.circlr')
    assert json.loads((fixture/'manifest.json').read_text())==captures['keyboard-return-verified']['manifest']
    assert digest(original/'manifest.json')=='12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d'
    for asset in baseline['assets']:
        for folder in [original,fixture]:assert digest(folder/asset['path'])==asset['checksum']
    assert 'Executed 469 tests, with 0 failures' in (ROOT/'.build/workspace-return-tests.log').read_text()
    assert 'Ran 28 tests' in (ROOT/'.build/workspace-return-python.log').read_text()
    for name in ['keyboard','format']:
        assert 'Build complete!' in (ROOT/('.build/workspace-return-'+name+'-release.log')).read_text()
    ps=unicodedata.normalize('NFC',subprocess.check_output(['ps','-axo','pid,command'],text=True))
    assert not any('/qa/generated/workspace-return/' in line and line.endswith('/Contents/MacOS/circlr') for line in ps.splitlines())
    result=dict(status='passed',nativeSnapshots=len(CASES),stateScreens=len(STATE_SCREENS),finalKeyboardScreens=len(KEYBOARD_SCREENS),sourceFiles=len(sources),executableSections=len(compiled),kitFiles=len(files),physicalAudioAttempts=0)
    (OUT/'verification.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))

if __name__=='__main__':main()
