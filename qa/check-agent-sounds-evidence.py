#!/usr/bin/env python3
"""Check native build 62 stdio discovery, edit isolation, saved restoration and package."""
import copy
import hashlib
import json
from pathlib import Path
import plistlib
import runpy
import subprocess

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'qa/generated/agent-sounds'


def load(name):return json.loads((OUT/(name+'.json')).read_text())
def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def music(value):
    value=copy.deepcopy(value);value.pop('musicRevision');value.pop('hierarchyView');return value


if __name__=='__main__':
    expected_revisions={'baseline':14,'applied':15,'undone':16,'redone':17,'focused-saved':17,'reopened':17}
    captures={name:load(name) for name in expected_revisions}
    baseline=music(captures['baseline']['manifest']);assert baseline==music(load('fixture-initial'))
    assert len(baseline['tracks'])==3 and len(baseline['assets'])==2 and len(baseline['arrangements'][0]['uses'])==2
    assert baseline['tracks'][2]['instrument']['synth']['cutoff']==731
    for name,revision in expected_revisions.items():
        capture=captures[name];state=capture['state']
        assert state['revision']==capture['manifest']['musicRevision']==revision
        assert state['runtime']['build']=='62' and state['runtime']['bundleID']=='com.circlr.integrationqa'
        assert state['runtime']['capabilities']['soundCatalog']==1 and not state['dirty']
        assert state['output']['attempts']==state['audition']['attempts']==0
        assert not state['recording']['busy'] and not state['recording']['midi'] and not state['playback']['playing']
        assert state['library']['folders']==1 and state['view']['consoleOpen']
        expected=copy.deepcopy(baseline)
        if name not in {'baseline','undone'}:expected['tracks'][2]['instrument'].update(kind='soundBank',program=4,bankLSB=16,drums=False)
        assert music(capture['manifest'])==expected,name
    assert captures['focused-saved']['manifest']==captures['reopened']['manifest']
    first=load('initial-reads');base_pages=first['pages'];catalog_id=base_pages[0]['catalogID']
    for name in ['initial-reads','minimized-reads','reopened-reads']:
        suite=load(name);assert suite['before']==suite['after'] and suite['pages']==base_pages
        assert len(suite['pages'])==7 and len(suite['queries'])==10
        items=[item for page in suite['pages'] for item in page['items']]
        assert len(items)==len({item['id'] for item in items})==254
        assert sum(item['category']=='soundBank' for item in items)==235
        assert sum(item['category']=='synth' for item in items)==10
        assert sum(item['category']=='instrument' for item in items)==9
        for index,page in enumerate(suite['pages']):
            assert page['offset']==index*37 and page['limit']==37 and page['total']==254 and page['catalogID']==catalog_id
            assert page.get('nextOffset')==((index+1)*37 if index<6 else None)
        assert [x['result']['total'] for x in suite['queries']]==[4,21,9,1,0,23,3,1,0,254]
        assert not suite['queries'][-1]['result']['items']
        program=suite['queries'][0]['result']['items'];assert [item['bankLSB'] for item in program]==[0,8,16,24]
        assert all(item['program']==4 and not item['drums'] for item in program)
        kit=suite['queries'][3]['result']['items'][0];assert (kit['name'],kit['program'],kit['bankLSB'],kit['drums'])==('TR-808',25,0,True)
        for item in items+suite['queries'][5]['result']['items']:
            assert 'state' not in item.get('plugin',{}) and 'path' not in item
        assert suite['denied']['isError'] and all(x['isError'] for x in suite['invalid'])
        assert 'stale_catalog' in suite['invalid'][1]['structuredContent']['error']
        for key in ['revision','layoutRevision','dirty','tracks','assets','selection','view','runtime','output','audition','recording']:
            assert suite['afterErrors'][key]==suite['before'][key],(name,key)
    assert load('minimized-reads')['before']['runtime']['windows']==[{'minimized':True,'visible':False}]
    uncached=load('uncached-reads');assert uncached['before']==uncached['after']
    assert [p['result']['query'] for p in uncached['packets']]==['#5','#26']
    assert uncached['packets'][0]['requestID']==uncached['packets'][1]['requestID']
    for name in ['applied-editor','reopened-editor']:
        assert '음색·악기 찾기 · E.Piano 1v · #5 · 변형 16' in (OUT/(name+'.ax.txt')).read_text()
    ax=(OUT/'program-five.ax.txt').read_text();assert '4개 결과' in ax and '3 · 통합 키보드 · 이 트랙의 모든 섹션' in ax
    assert all(item['name'] in ax for item in first['queries'][0]['result']['items'])
    assert '235개 결과' in (OUT/'current-catalog.ax.txt').read_text()
    fixture=Path(captures['reopened']['state']['path']);source=fixture.with_name('studio.circlr')
    assert json.loads((fixture/'manifest.json').read_text())==captures['reopened']['manifest']
    assert digest(source/'manifest.json')=='12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d'
    for asset in baseline['assets']:
        for folder in [source,fixture]:assert digest(folder/asset['path'])==asset['checksum']
    app=OUT/'써클러 통합 검증.app';info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
    assert (info['CFBundleVersion'],info['CFBundleShortVersionString'],info['CFBundleIdentifier'])==('62','0.20.0','com.circlr.integrationqa')
    sections=runpy.run_path(str(ROOT/'qa/check-library-evidence.py'))['sections'];compiled=sections(ROOT/'.build/integration-release/release/circlr')
    assert len(compiled)==37 and compiled==sections(app/'Contents/MacOS/circlr')
    subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
    sources=load('source-hashes');assert len(sources)==10
    for name,expected in sources.items():assert digest(ROOT/name)==expected,name
    kit=app/'Contents/Resources/Codex';files=json.loads((kit/'manifest.json').read_text())['files'];assert len(files)==25
    for name,expected in files.items():assert digest(kit/name)==expected,name
    assert (kit/'skills/circlr-studio/scripts/mcp_server.py').read_bytes()==(ROOT/'mcp/server.py').read_bytes()
    assert 'Executed 451 tests, with 0 failures' in (ROOT/'.build/agent-sounds-tests.log').read_text()
    python_log=(ROOT/'.build/agent-sounds-python.log').read_text();assert 'Ran 28 tests' in python_log and '\nOK\n' in python_log
    preserve=load('preservation');assert preserve['userApp']==['0.19.0','21'] and preserve['ownedQAProcesses']==[]
    assert set(preserve['heads'].values())=={'d88ea5d8d5d87cf49c5ef06154397c36ba1019d7','1d304eb244f60a21c3598b89d05192d3512d719d'}
    for path,head in preserve['heads'].items():assert subprocess.check_output(['git','-C',path,'rev-parse','HEAD'],text=True).strip()==head
    assert not [line for line in subprocess.check_output(['ps','-axo','pid=,command='],text=True).splitlines() if len(line.split(None,1))==2 and line.split(None,1)[1].startswith(str(ROOT/'qa/generated')+'/') and '/Contents/MacOS/circlr' in line]
    screenshots={p.name:digest(p) for p in sorted(OUT.glob('*.jpg'))};assert len(screenshots)==len(list(OUT.glob('*.ax.txt')))==4
    result=dict(status='passed',savedStates=6,stdioSuites=3,pagesPerSuite=7,instruments=254,queriesPerSuite=10,screenshots=screenshots,sourceFiles=10,kitFiles=25,physicalAudioAttempts=0)
    (OUT/'verification.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({k:v for k,v in result.items() if k!='screenshots'},ensure_ascii=False))
