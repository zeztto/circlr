#!/usr/bin/env python3
"""Check actual bank addresses, edit isolation and the final build 61 package."""
import copy
import hashlib
import json
from pathlib import Path
import plistlib
import re
import runpy
import subprocess

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'qa/generated/sound-bank-search'
CASES={'baseline':14,'variation-eight':15,'reselected':15,'variation-sixteen':16,'variation-undone':17,
       'variation-redone':18,'drums-applied':19,'last-program-applied':20,'invalid-input-unchanged':20,
       'stale-rejected':21,'synth-restored':23,'saved-variation':24,'reopened':24,'final-opened':24,
       'final-stale':25,'final-restored':26}


def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def document(value):
    value=copy.deepcopy(value);value.pop('musicRevision');value.pop('hierarchyView');return value
def ax(name):return (OUT/(name+'.ax.txt')).read_text()


if __name__=='__main__':
    captures={name:json.loads((OUT/(name+'.json')).read_text()) for name in CASES}
    baseline=document(captures['baseline']['manifest'])
    assert len(baseline['tracks'])==3 and len(baseline['assets'])==2 and len(baseline['arrangements'][0]['uses'])==2
    assert baseline['tracks'][2]['instrument']['synth']['cutoff']==731
    assert document(json.loads((OUT/'fixture-initial.json').read_text()))==baseline
    unchanged={'baseline','reselected','invalid-input-unchanged','reopened','final-opened'}
    variation8={'variation-eight','reselected','variation-undone'}
    variation16={'variation-sixteen','variation-redone','saved-variation','reopened','final-opened','final-stale','final-restored'}
    for name,revision in CASES.items():
        capture=captures[name];state=capture['state'];project=capture['manifest']
        assert state['projectID']=='3BC5B93C-8522-53C8-A09C-713E4F1A21E1'
        assert state['revision']==project['musicRevision']==revision,name
        assert not state['dirty'] and capture['beforeSave']['dirty']==(name not in unchanged),name
        assert state['output']['attempts']==state['audition']['attempts']==0
        assert not state['recording']['busy'] and not state['recording']['midi'] and not state['playback']['playing']
        assert state['runtime']['bundleID']=='com.circlr.integrationqa' and state['library']['folders']==1
        assert state['view']['consoleOpen'] and project['circleLayout']=='freeform'
        expected=copy.deepcopy(baseline);instrument=expected['tracks'][2]['instrument']
        if name in variation8|variation16:
            instrument.update(kind='soundBank',program=4,drums=False,bankLSB=8 if name in variation8 else 16)
        if name=='drums-applied':instrument.update(kind='soundBank',program=25,drums=True)
        if name in ['last-program-applied','invalid-input-unchanged','stale-rejected']:instrument.update(kind='soundBank',program=127,drums=False)
        if name=='synth-restored':instrument['program']=127
        if name=='stale-rejected':expected['name']='Sound Bank 검색 중 변경'
        if name=='final-stale':expected['name']='Sound Bank 최종 안내 검증'
        assert document(project)==expected,name  # All other tracks, uses, source, notes, routing, assets and preferences.
    assert captures['variation-eight']['manifest']==captures['reselected']['manifest']
    assert captures['saved-variation']['manifest']==captures['reopened']['manifest']==captures['final-opened']['manifest']
    bank=json.loads((OUT/'bank-metadata.json').read_text());assert len(bank)==235
    bank_source=json.loads((OUT/'bank-source.json').read_text());assert digest(Path(bank_source['path']))==bank_source['sha256']
    assert sum(row['MSB']==121 and row['LSB']==0 for row in bank)==128
    assert sum(row['MSB']==121 and row['LSB']!=0 for row in bank)==98
    assert sum(row['MSB']==120 for row in bank)==9
    for program,lsb,msb,title in [(4,8,121,'Detuned EP 1'),(4,16,121,'E.Piano 1v'),(25,0,120,'TR-808'),(127,0,121,'Gun Shot')]:
        assert any((r['program'],r['LSB'],r['MSB'],r['name'].strip())==(program,lsb,msb,title) for r in bank)
    for name,count in [('bank-open',235),('family-search',21),('program-five',4),('drum-kits',9),
                       ('drum-number',1),('drum-no-results',0),('last-program',4),('exact-first-program',4),
                       ('current-restored',254),('named-variation',1),('final-layout',235)]:
        assert str(count)+'개 결과' in ax(name),name
    assert 'container 앨범 서클 캔버스' not in ax('bank-open')
    # The current-sound header intentionally retains #128 while the user searches #1.
    result_rows=[line for line in ax('exact-first-program').splitlines() if ' button ' in line and ' · Sound Bank · ' in line]
    assert len(result_rows)==4 and all(re.search(r' · #1 · ',line) for line in result_rows)
    assert 'button (selected) TR-808' in ax('drum-number') and 'button (selected) Gun Shot' in ax('current-restored')
    assert 'button (selected) Detuned EP 1' in ax('current-variation')
    assert 'button (selected) E.Piano 1v' in ax('reopened-current') and '변형 16' in ax('reopened')
    for name in ['stale-rejected','final-stale-layout']:
        assert '(selected, disabled) E.Piano 1' in ax(name) and '대상이나 음악이 바뀌었거나' in ax(name)
    for name in ['final-layout','final-stale-layout']:
        assert '3 · 통합 키보드 · 이 트랙의 모든 섹션' in ax(name)
    assert any('Description: 필터 Hz' in line and line.endswith('Value: 731') for line in ax('synth-restored').splitlines())
    for name in ['bank-open','program-five','current-variation','drum-kits','current-restored','final-layout']:
        assert 'The focused UI element is 6 search text field' in ax(name),name
    invalid=json.loads((OUT/'invalid-input-result.json').read_text())
    assert invalid['beforeRevision']==invalid['afterRevision']==20 and '0–127' in invalid['error']
    fixture=Path(captures['final-restored']['state']['path']);source=fixture.with_name('studio.circlr')
    assert json.loads((fixture/'manifest.json').read_text())==captures['final-restored']['manifest']
    assert digest(source/'manifest.json')=='12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d'
    for asset in baseline['assets']:
        for folder in [source,fixture]:assert digest(folder/asset['path'])==asset['checksum']
    app=OUT/'final/써클러 통합 검증.app';info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
    assert (info['CFBundleVersion'],info['CFBundleShortVersionString'],info['CFBundleIdentifier'])==('61','0.20.0','com.circlr.integrationqa')
    sections=runpy.run_path(str(ROOT/'qa/check-library-evidence.py'))['sections']
    compiled=sections(ROOT/'.build/integration-release/release/circlr')
    assert len(compiled)==37 and compiled==sections(app/'Contents/MacOS/circlr')
    subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
    sources=json.loads((OUT/'final/source-hashes.json').read_text());assert len(sources)==11
    previous=json.loads((OUT/'source-hashes.json').read_text())
    assert [name for name in sources if sources[name]!=previous[name]]==['Sources/CirclrApp/SoundPickerView.swift']
    for name,expected in sources.items():assert digest(ROOT/name)==expected
    kit=app/'Contents/Resources/Codex';files=json.loads((kit/'manifest.json').read_text())['files'];assert len(files)==25
    for name,expected in files.items():assert digest(kit/name)==expected
    assert 'Executed 445 tests, with 0 failures' in (ROOT/'.build/bank-search-tests.log').read_text()
    assert 'Ran 26 tests' in (ROOT/'.build/bank-search-python.log').read_text()
    preserve=json.loads((OUT/'preservation.json').read_text())
    assert preserve['ownedQAProcesses']==[] and preserve['userApp']==['0.19.0','21']
    assert set(preserve['heads'].values())=={'d88ea5d8d5d87cf49c5ef06154397c36ba1019d7','1d304eb244f60a21c3598b89d05192d3512d719d'}
    for path,head in preserve['heads'].items():assert subprocess.check_output(['git','-C',path,'rev-parse','HEAD'],text=True).strip()==head
    assert not [line for line in subprocess.check_output(['ps','-axo','pid=,command='],text=True).splitlines()
                if len(line.split(None,1))==2 and line.split(None,1)[1].startswith(str(ROOT/'qa/generated')+'/') and '/Contents/MacOS/circlr' in line]
    screenshots={p.name:digest(p) for p in sorted(OUT.glob('*.jpg'))}
    assert len(screenshots)==len(list(OUT.glob('*.ax.txt')))==18
    result=dict(status='passed',nativeSnapshots=len(CASES),axCaptures=18,screenshots=screenshots,sourceFiles=11,
                bankPresets=235,kitFiles=25,executableSections=37,physicalAudioAttempts=0)
    (OUT/'verification.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({k:v for k,v in result.items() if k!='screenshots'},ensure_ascii=False))
