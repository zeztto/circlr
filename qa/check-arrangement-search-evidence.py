#!/usr/bin/env python3
"""Check native build 63 arrangement ownership, history, restoration and package."""
import copy
import hashlib
import json
from pathlib import Path
import plistlib
import re
import runpy
import subprocess

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'qa/generated/arrangement-search'
# revision, active arrangement ordinal, first owner's selection, second owner's selection
CASES={
    'baseline':(14,65,65,66),'reselected':(14,65,65,66),'third-applied':(15,3,3,66),
    'undone':(16,65,65,66),'noop-before-redo':(16,65,65,66),'redone':(17,3,3,66),
    'empty-applied':(18,4,4,66),'empty-undone':(19,3,3,66),'revision-stale':(20,3,3,66),
    'name-restored':(21,3,3,66),'owner-stale':(21,66,3,66),'other-applied':(22,67,3,67),
    'other-undone':(23,66,3,66),'name-committed':(24,3,3,66),'name-undone':(25,3,3,66),
    'editor-before':(25,3,3,66),'editor-noop':(25,3,3,66),'pre-final':(25,3,3,66),
    'editor-stable':(25,3,3,66),'editor-stable-noop':(25,3,3,66),
    'initial-final-saved':(25,3,3,66),'final-opened':(25,3,3,66),
    'final-applied':(26,2,2,66),'final-undone':(27,3,3,66),'final-saved':(27,3,3,66),
    'final-reopened':(27,3,3,66),
}


def load(name):return json.loads((OUT/(name+'.json')).read_text())
def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def ax(name):return (OUT/(name+'.ax.txt')).read_text()
def music(value):
    value=copy.deepcopy(value);value.pop('musicRevision');value.pop('hierarchyView');return value


if __name__=='__main__':
    captures={name:load(name) for name in CASES};baseline=music(captures['baseline']['manifest'])
    assert baseline==music(load('fixture-initial'))
    assert len(baseline['tracks'])==3 and len(baseline['assets'])==2 and len(baseline['arrangements'])==67
    owners=baseline['album']['compositions'];assert [len(c['arrangementIDs']) for c in owners]==[65,2]
    ids=[a['id'] for a in baseline['arrangements']]
    assert baseline['arrangements'][3]['uses']==[] and len(baseline['arrangements'][64]['uses'])==2
    for name,(revision,active,first,second) in CASES.items():
        capture=captures[name];state=capture['state'];project=capture['manifest']
        assert state['projectID']=='96F52E7D-A74F-57EE-B9B9-139761DC6D9A'
        assert state['revision']==project['musicRevision']==revision,name
        assert state['runtime']['build']=='63' and state['runtime']['bundleID']=='com.circlr.integrationqa'
        assert not state['dirty'] and state['output']['attempts']==state['audition']['attempts']==0
        assert not state['recording']['busy'] and not state['recording']['midi'] and not state['playback']['playing']
        assert state['library']['folders']==1 and state['view']['consoleOpen']
        expected=copy.deepcopy(baseline);expected['activeArrangementID']=ids[active-1]
        expected['album']['compositions'][0]['selectedArrangementID']=ids[first-1]
        expected['album']['compositions'][1]['selectedArrangementID']=ids[second-1]
        if name=='revision-stale':expected['name']='편곡안 검색 중 외부 변경'
        if name=='name-committed':expected['album']['compositions'][0]['name']='편곡 검색 이름 확정 검증'
        assert music(project)==expected,name  # Every arrangement, note, graph, asset and other field stays intact.
    # The initial baseline was captured during a focus animation; use settled captures for camera equality.
    assert captures['baseline']['state']['selection']==captures['reselected']['state']['selection']
    for first,second in [('undone','noop-before-redo'),
                         ('editor-stable','editor-stable-noop'),('initial-final-saved','final-opened'),
                         ('final-saved','final-reopened')]:
        assert captures[first]['manifest']==captures[second]['manifest'],(first,second)
    assert captures['editor-stable']['state']['selection']==captures['editor-stable-noop']['state']['selection']
    for name in ['reselected','noop-before-redo','editor-stable-noop','final-opened','final-reopened']:
        assert not captures[name]['beforeSave']['dirty'],name
    for name in ['third-applied','undone','redone','empty-applied','empty-undone','other-applied',
                 'other-undone','name-committed','name-undone','final-applied','final-undone']:
        assert captures[name]['beforeSave']['dirty'],name
    for name,count in [('opened-current',65),('korean-duplicates',3),('exact-first',1),('no-results',0),
                       ('current-restored',65),('other-owner',2),('editor-picker',65),('final-picker',65),('reopened-picker',65)]:
        assert str(count)+'개 결과' in ax(name),name
        assert 'container 앨범 서클 캔버스' not in ax(name),name
    rows=lambda name:[line for line in ax(name).splitlines() if re.search(r'button .*#\d+ · .*개 섹션',line)]
    assert len(rows('korean-duplicates'))==3
    assert [int(re.search(r'#(\d+)',line)[1]) for line in rows('korean-duplicates')]==[2,3,65]
    assert len(rows('exact-first'))==1 and '#1 · 메인 편곡' in rows('exact-first')[0]
    assert '(selected)' in ax('keyboard-third') and '#3 · 도시의 밤' in ax('keyboard-third')
    for name in ['current-restored','editor-picker','final-picker','reopened-picker']:
        assert '(selected) Description: #3 · 도시의 밤 · 2개 섹션 · 재생 편곡' in ax(name),name
    for name in ['revision-stale','owner-stale']:
        assert '대상이나 음악이 바뀌었거나' in ax(name)
        assert rows(name) and all('disabled' in row for row in rows(name)),name
    assert '편곡 검색 이름 확정 검증 · 앨범 재생에 사용할 편곡안' in ax('name-committed-picker')
    assert '대상이나 음악이 바뀌었거나' not in ax('name-committed-picker')
    for name,title in [('switch-navigation','text 작업 이동'),('switch-library','text 샘플 라이브러리')]:
        assert title in ax(name) and 'text 편곡안 찾기' not in ax(name)
    assert 'button (selected) 편곡안 찾기, ⌥⌘J' in ax('command-search')
    assert 'text 편곡안 찾기' in ax('command-picker') and '명령 또는 서클 이름 검색' not in ax('command-picker')
    before=ax('settings-before');after=ax('final-settings');button='button Description: 편곡안 찾기 ·'
    assert before.index(button)>before.index('Description: 템포 설정 출처')
    assert after.count(button)==1 and after.index(button)<after.index('Description: 템포 설정 출처')
    fixture=Path(captures['final-reopened']['state']['path']);source=fixture.with_name('studio.circlr')
    assert json.loads((fixture/'manifest.json').read_text())==captures['final-reopened']['manifest']
    assert digest(source/'manifest.json')=='12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d'
    for asset in baseline['assets']:
        for folder in [source,fixture]:assert digest(folder/asset['path'])==asset['checksum']
    app=OUT/'final/써클러 통합 검증.app';info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
    assert (info['CFBundleVersion'],info['CFBundleShortVersionString'],info['CFBundleIdentifier'])==('63','0.20.0','com.circlr.integrationqa')
    sections=runpy.run_path(str(ROOT/'qa/check-library-evidence.py'))['sections']
    compiled=sections(ROOT/'.build/integration-release/release/circlr')
    assert len(compiled)==37 and compiled==sections(app/'Contents/MacOS/circlr')
    subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
    sources=load('final/source-hashes');previous=load('source-hashes');assert len(sources)==14
    assert [name for name in sources if sources[name]!=previous[name]]==['Sources/CirclrApp/InlineCircleEditor.swift']
    for name,expected in sources.items():assert digest(ROOT/name)==expected,name
    kit=app/'Contents/Resources/Codex';files=json.loads((kit/'manifest.json').read_text())['files'];assert len(files)==25
    for name,expected in files.items():assert digest(kit/name)==expected,name
    assert (kit/'skills/circlr-studio/scripts/mcp_server.py').read_bytes()==(ROOT/'mcp/server.py').read_bytes()
    assert 'Executed 457 tests, with 0 failures' in (ROOT/'.build/arrangement-search-tests.log').read_text()
    python_log=(ROOT/'.build/arrangement-search-python.log').read_text();assert 'Ran 28 tests' in python_log and '\nOK\n' in python_log
    assert 'Build complete! (37.53s)' in (ROOT/'.build/arrangement-search-final-release.log').read_text()
    preserve=load('preservation');assert preserve['userApp']==['0.19.0','21'] and preserve['ownedQAProcesses']==[]
    assert set(preserve['heads'].values())=={'d88ea5d8d5d87cf49c5ef06154397c36ba1019d7','1d304eb244f60a21c3598b89d05192d3512d719d'}
    for path,head in preserve['heads'].items():assert subprocess.check_output(['git','-C',path,'rev-parse','HEAD'],text=True).strip()==head
    user_info=plistlib.loads((ROOT.parent.parent/'dist/써클러.app/Contents/Info.plist').read_bytes())
    assert [user_info['CFBundleShortVersionString'],user_info['CFBundleVersion']]==preserve['userApp']
    assert not [line for line in subprocess.check_output(['ps','-axo','pid=,command='],text=True).splitlines()
                if len(line.split(None,1))==2 and line.split(None,1)[1].startswith(str(ROOT/'qa/generated')+'/') and '/Contents/MacOS/circlr' in line]
    screenshots={p.name:digest(p) for p in sorted(OUT.glob('*.jpg'))}
    assert len(screenshots)==len(list(OUT.glob('*.ax.txt')))==24
    result=dict(status='passed',nativeSnapshots=len(CASES),axCaptures=24,screenshots=screenshots,sourceFiles=14,
                arrangements=67,owners=2,kitFiles=25,executableSections=37,physicalAudioAttempts=0)
    (OUT/'verification.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({k:v for k,v in result.items() if k!='screenshots'},ensure_ascii=False))
