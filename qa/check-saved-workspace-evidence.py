#!/usr/bin/env python3
"""Check build67 restoration against saved documents, AX and the signed final candidate."""
import copy
import hashlib
import json
from pathlib import Path
import plistlib
import runpy
import subprocess
import unicodedata

ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'qa/generated/saved-workspace'
EARLY={'baseline':14,'connection-saved':14,'reopened-query-edit':14}
FINAL={'refined-query-saved':14,'refined-warm-edited':14,'reconnect-applied':15,'reconnect-undone':16,
       'transition-saved':16,'transition-reopened':16,'automation-pan-saved':16,'original-settings-saved':16,
       'original-connections-saved':16,'original-connections-reopened':16,'audio-original-settings-saved':16,
       'audio-original-settings-reopened':16,'midi-step-saved':16,'midi-step-reopened':16,
       'missing-node-reopened':16,'missing-reconnect-reopened':17,'missing-transition-reopened':17,'final-restored':16}
SCREENS=['refined-cold-open','refined-query-edit','refined-warm-open','refined-reconnect-applied',
         'transition-saved','transition-reopened','automation-pan-saved','automation-pan-reopened',
         'original-settings-saved','original-settings-reopened','original-connections-saved','original-connections-reopened',
         'audio-original-settings-saved','audio-original-settings-reopened','midi-step-saved','midi-step-reopened',
         'missing-node-reopened','missing-reconnect-reopened','missing-transition-reopened','final-restored']
def load(name):return json.loads((OUT/(name+'.json')).read_text())
def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def music(p):
    p=copy.deepcopy(p);p.pop('hierarchyView');p.pop('musicRevision');return p
def ax(name):return (OUT/(name+'.ax.txt')).read_text()
def contains(name,*parts):return any(all(p in line for p in parts) for line in ax(name).splitlines())

def main():
    captures={name:load(name) for name in EARLY|FINAL};baseline=music(captures['baseline']['manifest'])
    assert baseline==music(load('fixture-initial'))
    for name,revision in (EARLY|FINAL).items():
        data=captures[name];s=data['state'];p=data['manifest'];expected=copy.deepcopy(baseline)
        assert s['projectID']=='F8DAEB31-C399-5654-A31A-8B8D2364AB69' and s['revision']==p['musicRevision']==revision,name
        assert s['runtime']['build']=='67' and s['runtime']['bundleID']=='com.circlr.integrationqa'
        assert s['job']['state']=='completed' and not s['dirty']
        assert s['output']['attempts']==s['audition']['attempts']==0
        assert not s['playback']['playing'] and not s['recording']['midi'] and not s['recording']['busy']
        assert s['library']['folders']==1
        if revision>=16:expected['portLayout']['revision']=6
        a=expected['arrangements'][0]
        if name=='reconnect-applied':
            edge=a['edges'].pop(0);edge['to']=a['uses'][3]['id'];a['edges'].append(edge)
            expected['portLayout']['revision']=5
            expected['portLayout']['connections']=[{'id':{'edgeID':edge['id'],
                'from':{'section':{'arrangementID':a['id'],'useID':edge['from']}},
                'to':{'section':{'arrangementID':a['id'],'useID':edge['to']}}},'placement':{'from':3,'to':7}}]
        if name=='missing-reconnect-reopened':a['edges'].pop(0);a['chosenEdges']={}
        if name=='missing-transition-reopened':a['edges'].pop(1)
        assert music(p)==expected,name # Exact comparison includes every original, note, effect, binding and asset.
    workspace=lambda name:captures[name]['manifest']['hierarchyView']['workspace']
    # Preserve the first candidate's reproducible failure, separate from final acceptance.
    assert contains('reopened-query-edit','검색,','Value: #5')
    assert workspace('reopened-query-edit')['connection']['query']=='#4'
    for name,query in [('refined-query-saved','#5'),('refined-warm-edited','#4')]:
        c=workspace(name)['connection'];assert c['query']==query and c['replacing'] and c['target']
        assert c['firstOctant']==3 and c['secondOctant']==7
    for name,query in [('refined-cold-open','#4'),('refined-warm-open','#5')]:
        assert contains(name,'검색,','Value: '+query) and contains(name,'cell (selected) '+query)
        assert contains(name,'button 재연결 적용')
    for first,second in [('transition-saved','transition-reopened'),('original-connections-saved','original-connections-reopened'),
                         ('audio-original-settings-saved','audio-original-settings-reopened'),('midi-step-saved','midi-step-reopened'),
                         ('midi-step-reopened','final-restored')]:
        assert captures[first]['manifest']==captures[second]['manifest'],(first,second)
    assert workspace('transition-reopened')['page']=='transition' and workspace('transition-reopened')['transitionID']==baseline['arrangements'][0]['edges'][1]['id']
    assert contains('transition-reopened','작업 전환 · 전환','Value: 선택됨') and '뒤 섹션 · #3' in ax('transition-reopened')
    assert workspace('automation-pan-saved')['page']=='automation' and workspace('automation-pan-saved')['automationParameter']=='pan'
    assert captures['automation-pan-saved']['state']['automationEditor']['visible']
    assert contains('automation-pan-reopened','작업 전환 · 오토메이션','Value: 선택됨') and contains('automation-pan-reopened','Description: 팬','Value: 1')
    for name in ['original-settings-saved','original-connections-saved','original-connections-reopened','audio-original-settings-saved','audio-original-settings-reopened']:
        assert workspace(name)['original'] is True
    assert contains('original-settings-reopened','공유 원본 편집','Value: 1')
    assert '연결 3개 공유 원본' in ax('original-connections-reopened')
    assert contains('audio-original-settings-reopened','공유 원본 편집','Value: 1')
    assert '이번 사용에만 있는 서클은' not in ax('audio-original-settings-reopened')
    assert captures['midi-step-reopened']['manifest']['hierarchyView']['midiStepMode'] is True
    assert workspace('midi-step-reopened')['page']=='content' and workspace('midi-step-reopened')['original'] is False
    assert contains('midi-step-reopened','radio button Description: 스텝','Value: 1')
    scope={'section':{'arrangementID':baseline['arrangements'][0]['id'],'useID':baseline['arrangements'][0]['uses'][0]['id']}}
    assert captures['missing-node-reopened']['state']['selection']==scope
    assert workspace('missing-node-reopened')['page']=='content'
    c=workspace('missing-reconnect-reopened')['connection'];assert c['query']=='#4' and 'replacing' not in c and 'target' not in c
    assert 'button (disabled) 연결' in ax('missing-reconnect-reopened') and '재연결 적용' not in ax('missing-reconnect-reopened')
    assert workspace('missing-transition-reopened')['page']=='settings' and 'transitionID' not in workspace('missing-transition-reopened')
    assert '작업 전환 · 전환' not in ax('missing-transition-reopened')
    for name in SCREENS:
        assert '통합 편집 검증' in ax(name) and (OUT/(name+'.jpg')).stat().st_size>10000,name
    app=OUT/'refined/써클러 통합 검증.app';info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
    assert (info['CFBundleVersion'],info['CFBundleShortVersionString'],info['CFBundleIdentifier'])==('67','0.20.0','com.circlr.integrationqa')
    sections=runpy.run_path(str(ROOT/'qa/check-library-evidence.py'))['sections'];compiled=sections(ROOT/'.build/integration-release/release/circlr')
    assert len(compiled)==37 and compiled==sections(app/'Contents/MacOS/circlr')
    subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
    sources=load('refined/source-hashes');assert len(sources)==10
    for name,value in sources.items():assert digest(ROOT/name)==value,name
    kit=app/'Contents/Resources/Codex';files=json.loads((kit/'manifest.json').read_text())['files'];assert len(files)==25
    for name,value in files.items():assert digest(kit/name)==value
    fixture=Path(captures['final-restored']['state']['path']);original=fixture.with_name('studio.circlr')
    assert json.loads((fixture/'manifest.json').read_text())==captures['final-restored']['manifest']
    assert digest(original/'manifest.json')=='12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d'
    for asset in baseline['assets']:
        for folder in [fixture,original]:assert digest(folder/asset['path'])==asset['checksum']
    assert 'Executed 477 tests, with 0 failures' in (ROOT/'.build/saved-workspace-clean-tests.log').read_text()
    assert 'Ran 28 tests' in (ROOT/'.build/saved-workspace-python.log').read_text()
    assert 'Build complete!' in (ROOT/'.build/saved-workspace-refined-release.log').read_text()
    ps=unicodedata.normalize('NFC',subprocess.check_output(['ps','-axo','pid,command'],text=True))
    assert not any('/qa/generated/saved-workspace/' in line and line.endswith('/Contents/MacOS/circlr') for line in ps.splitlines())
    result=dict(status='passed',finalSnapshots=len(FINAL),finalScreens=len(SCREENS),earlierCaptures=len(EARLY),sourceFiles=len(sources),executableSections=len(compiled),kitFiles=len(files),physicalAudioAttempts=0)
    (OUT/'verification.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))

if __name__=='__main__':main()
