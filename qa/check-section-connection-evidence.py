#!/usr/bin/env python3
"""Check native build 64 search, flow edits, complete music preservation and final app."""
import copy
import hashlib
import json
from pathlib import Path
import plistlib
import re
import runpy
import subprocess
import uuid

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'qa/generated/section-connection'
CASES={'baseline':14,'duplicate-noop':14,'unselected-noop':14,'connected':15,'connect-undone':16,
       'connect-redone':17,'connect-restored':18,'final-opened':18,'branch-selected':19,'branch-undone':20,
       'branch-redone':21,'incoming-before':21,'incoming-selected':22,'incoming-undone':23,
       'transition-edited':24,'transition-undone':25,'reconnected':26,'reconnect-undone':27,
       'disconnected':28,'disconnect-undone':29,'branch-restored':30,'port-view-before':30,
       'port-view-after':30,'refined-opened':30,'refined-endpoint':30,'refined-saved':30,'refined-reopened':30}
BRANCHED={'branch-selected','branch-redone','incoming-before','incoming-undone','transition-edited',
          'transition-undone','reconnected','reconnect-undone','disconnect-undone'}


def load(name):return json.loads((OUT/(name+'.json')).read_text())
def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def ax(name):return (OUT/(name+'.ax.txt')).read_text()
def music(value):
    value=copy.deepcopy(value);value.pop('musicRevision');value.pop('hierarchyView');return value


if __name__=='__main__':
    captures={name:load(name) for name in CASES};baseline=music(captures['baseline']['manifest'])
    assert baseline==music(load('fixture-initial'))
    assert len(baseline['tracks'])==3 and len(baseline['assets'])==2
    assert [len(a['uses']) for a in baseline['arrangements']]==[32,1]
    initial=baseline['arrangements'][0];source=initial['uses'][0]['id'];branch=initial['edges'][1]['id']
    added=captures['connected']['manifest']['arrangements'][0]['edges'][-1]['id'];uuid.UUID(added)
    for name,revision in CASES.items():
        c=captures[name];s=c['state'];p=c['manifest']
        assert s['projectID']=='D6A45651-8842-5174-A74F-AD3F10A22A9E'
        assert s['revision']==p['musicRevision']==revision,name
        assert s['runtime']['build']=='64' and s['runtime']['bundleID']=='com.circlr.integrationqa'
        assert not s['dirty'] and s['output']['attempts']==s['audition']['attempts']==0
        assert not s['recording']['midi'] and not s['recording']['busy'] and not s['playback']['playing']
        assert s['library']['folders']==1 and s['view']['consoleOpen']
        expected=copy.deepcopy(baseline);a=expected['arrangements'][0]
        if name in BRANCHED:a['chosenEdges'][source]=branch
        if name in {'connected','connect-redone'}:
            a['edges'].append(dict(id=added,**{'from':source,'to':a['uses'][31]['id']},transition=dict(mode='within',anchor='sourceBars',length=0,effect=dict(kind='gain',amount=1,secondary=.25))))
        if name=='transition-edited':a['edges'][0]['transition']['length']=.25
        if name=='reconnected':a['edges'][1]['to']=a['uses'][3]['id']
        if name=='disconnected':a['edges'].pop(1);a['chosenEdges'].pop(source)
        assert music(p)==expected,name  # Includes every other owner/use, source, note, effect, binding and placement.
    for first,second in [('baseline','duplicate-noop'),('duplicate-noop','unselected-noop'),
                         ('connect-restored','final-opened'),('port-view-before','port-view-after'),
                         ('port-view-after','refined-opened'),('refined-saved','refined-reopened')]:
        assert captures[first]['manifest']==captures[second]['manifest'],(first,second)
    assert captures['incoming-before']['state']['selection']==captures['incoming-selected']['state']['selection']
    assert captures['incoming-before']['manifest']['hierarchyView']==captures['incoming-selected']['manifest']['hierarchyView']
    assert captures['refined-reopened']['state']['selection']['section']['useID']==initial['uses'][2]['id']
    for name in ['duplicate-noop','unselected-noop','port-view-after','refined-opened','refined-reopened']:
        assert not captures[name]['beforeSave']['dirty'],name
    for name in ['connected','connect-undone','connect-redone','branch-selected','branch-undone','incoming-selected',
                 'transition-edited','reconnected','reconnect-undone','disconnected','disconnect-undone','branch-restored']:
        assert captures[name]['beforeSave']['dirty'],name
    for name,count in [('connections-open',31),('korean-search',2),('exact-third',1),('no-results',0),('unselected-result',1),('audio-targets',5),('midi-targets',1)]:
        assert re.search(r'\btext '+str(count)+r'개\b',ax(name)),name
    cells=lambda name:[line for line in ax(name).splitlines() if re.search(r'cell(?: \(selected\))? #',line)]
    assert len(cells('korean-search'))==2 and all('도시의 밤' in row for row in cells('korean-search'))
    assert len(cells('exact-third'))==1 and '#3 · 도시의 밤' in cells('exact-third')[0]
    assert 'button (disabled) 연결' in ax('no-results') and 'button (disabled) 연결' in ax('unselected-result')
    assert '다른 곡' not in '\n'.join(cells('connections-open'))
    assert 'Northern city reprise' in ax('long-target')
    assert '섹션 순서·전환 · 인트로' in ax('section-settings') and 'menu button 다음 섹션 연결' not in ax('section-settings')
    assert 'button (disabled) 재생 경로, Description: 재생 경로 · #3' in ax('branch-selected')
    assert 'button (disabled) 재생 경로, Description: 재생 경로 · #2' in ax('disconnected')
    first=load('tab-order-first');branch_tabs=load('tab-order-branch')
    assert len(first)==len(branch_tabs)==5 and '전환 편집' in first[-1] and '이 경로 재생 · #3' in branch_tabs[-1]
    for label,text in zip(['재연결','해제','OUT 위치','IN 위치'],branch_tabs):assert label in text
    assert '앞 섹션 · #1 · 인트로' in ax('refined-transition') and '뒤 섹션 · #3 · 도시의 밤' in ax('refined-transition')
    assert 'Value: 0.125' in ax('refined-transition') and '작업 전환 · 연결' in ax('transition-return')
    assert 'cell 신스 그룹 · IN 외부 스테레오 입력' in ax('audio-targets')
    assert 'cell 통합 키보드 MIDI · OUT MIDI 연주' in ax('midi-targets')
    for name in ['audio-targets','midi-targets']:assert 'button 전환 편집' not in ax(name)
    fixture=Path(captures['refined-reopened']['state']['path']);original=fixture.with_name('studio.circlr')
    assert json.loads((fixture/'manifest.json').read_text())==captures['refined-reopened']['manifest']
    assert digest(original/'manifest.json')=='12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d'
    for asset in baseline['assets']:
        for folder in [fixture,original]:assert digest(folder/asset['path'])==asset['checksum']
    app=OUT/'refined/써클러 통합 검증.app';info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
    assert (info['CFBundleVersion'],info['CFBundleShortVersionString'],info['CFBundleIdentifier'])==('64','0.20.0','com.circlr.integrationqa')
    sections=runpy.run_path(str(ROOT/'qa/check-library-evidence.py'))['sections'];compiled=sections(ROOT/'.build/integration-release/release/circlr')
    assert len(compiled)==37 and compiled==sections(app/'Contents/MacOS/circlr')
    subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
    sources=load('refined/source-hashes');initial_sources=load('source-hashes');middle=load('final/source-hashes')
    assert len(sources)==8 and len(initial_sources)==len(middle)==7
    assert [name for name in initial_sources if initial_sources[name]!=middle[name]]==['Sources/CirclrApp/PortConnectionsEditor.swift']
    assert all(sources[name]==middle[name] for name in middle)
    for name,expected in sources.items():assert digest(ROOT/name)==expected,name
    kit=app/'Contents/Resources/Codex';files=json.loads((kit/'manifest.json').read_text())['files'];assert len(files)==25
    for name,expected in files.items():assert digest(kit/name)==expected,name
    assert 'Executed 463 tests, with 0 failures' in (ROOT/'.build/section-connection-tests.log').read_text()
    log=(ROOT/'.build/section-connection-python.log').read_text();assert 'Ran 28 tests' in log and '\nOK\n' in log
    assert 'Build complete! (36.35s)' in (ROOT/'.build/section-connection-refined-release.log').read_text()
    preserve=load('preservation');assert preserve['userApp']==['0.19.0','21'] and preserve['ownedQAProcesses']==[]
    assert set(preserve['heads'].values())=={'d88ea5d8d5d87cf49c5ef06154397c36ba1019d7','1d304eb244f60a21c3598b89d05192d3512d719d'}
    for path,head in preserve['heads'].items():assert subprocess.check_output(['git','-C',path,'rev-parse','HEAD'],text=True).strip()==head
    current=plistlib.loads((ROOT.parent.parent/'dist/써클러.app/Contents/Info.plist').read_bytes())
    assert [current['CFBundleShortVersionString'],current['CFBundleVersion']]==preserve['userApp']
    assert not [s for s in subprocess.check_output(['ps','-axo','pid=,command='],text=True).splitlines() if len(s.split(None,1))==2 and s.split(None,1)[1].startswith(str(ROOT/'qa/generated')+'/') and '/Contents/MacOS/circlr' in s]
    screenshots={p.name:digest(p) for p in sorted(OUT.glob('*.jpg'))};assert len(screenshots)==len(list(OUT.glob('*.ax.txt')))==22
    result=dict(status='passed',nativeSnapshots=len(CASES),axCaptures=22,screenshots=screenshots,sourceFiles=8,sectionUses=33,kitFiles=25,executableSections=37,physicalAudioAttempts=0)
    (OUT/'verification.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({k:v for k,v in result.items() if k!='screenshots'},ensure_ascii=False))
