#!/usr/bin/env python3
"""Validate build 60 native edits, preservation and the exact tested package."""
import base64
import copy
import hashlib
import json
from pathlib import Path
import plistlib
import runpy
import subprocess

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'qa/generated/sound-selection'
CASES={'baseline':15,'bass-applied':16,'synth-undone':17,'bass-redone':18,'au-applied':20,
       'au-state':21,'au-reselected':21,'stale-rejected':22,'before-effect':25,'circle-effect-applied':26,
       'effect-cancelled':27,'global-effect-applied':28,'missing-cancelled':30,'bank-applied':32,
       'restored':33,'reopened':33,'final-inactive':34,'final-bank':35,'final-returned-synth':36,
       'final-returned-au':37,'final-synth-again':38,'final-restored':39,'final-reopened':39}


def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def document(value):
    value=copy.deepcopy(value);value.pop('musicRevision');value.pop('hierarchyView');return value
def ax(name):return (OUT/(name+'.ax.txt')).read_text()


if __name__=='__main__':
    captures={name:json.loads((OUT/(name+'.json')).read_text()) for name in CASES}
    baseline=document(captures['baseline']['manifest'])
    assert len(baseline['tracks'])==3 and len(baseline['assets'])==2 and len(baseline['arrangements'][0]['uses'])==2
    assert baseline['tracks'][2]['instrument']['synth']['cutoff']==731
    assert baseline['tracks'][2]['instrument']['synth']['voice']==6
    initial=json.loads((OUT/'fixture-initial.json').read_text())
    assert baseline['tracks']==initial['tracks'] and baseline['signal']==initial['signal']
    plugin=captures['au-applied']['manifest']['tracks'][2]['instrument']['plugin']
    assert plugin['name']=='DLSMusicDevice' and plugin['type']==1635085685 and 'state' not in plugin
    saved=captures['au-state']['manifest']['tracks'][2]['instrument']['plugin']
    assert {k:v for k,v in saved.items() if k!='state'}==plugin
    assert plistlib.loads(base64.b64decode(saved['state']))=={'qa_marker':'same AU preserves state','gain':0.27}
    effect_id=next(n['id'] for n in baseline['arrangements'][0]['uses'][0]['graphEdits']['addedNodes'] if n['name']=='서클 공간')
    for name,revision in CASES.items():
        capture=captures[name];state=capture['state'];project=capture['manifest']
        assert state['projectID']=='603A2D17-CDC7-54F5-AF4A-05B1F254372D'
        assert state['revision']==project['musicRevision']==revision,name
        assert not state['dirty'] and capture['beforeSave']['dirty']==(name not in ['au-reselected','effect-cancelled','reopened','final-reopened']),name
        assert state['output']['attempts']==state['audition']['attempts']==0
        assert not state['recording']['busy'] and not state['recording']['midi'] and not state['playback']['playing']
        assert state['runtime']['bundleID']=='com.circlr.integrationqa' and state['library']['folders']==1
        assert state['view']['consoleOpen'] and project['circleLayout']=='freeform'
        expected=copy.deepcopy(baseline);instrument=expected['tracks'][2]['instrument']
        if name in ['bass-applied','bass-redone']:
            patch=project['tracks'][2]['instrument']['synth']
            assert patch['voice']==1 and patch['cutoff']==650 and patch['release']==0.08
            instrument['synth']=patch
        if name in ['au-applied','au-state','au-reselected','stale-rejected']:
            instrument.update(kind='audioUnit',plugin=saved if name!='au-applied' else plugin)
        if name=='stale-rejected':expected['name']='음색 선택 중 변경 검증'
        if name=='circle-effect-applied':
            nodes=expected['arrangements'][0]['uses'][0]['graphEdits']['addedNodes']
            actual=next(n for n in project['arrangements'][0]['uses'][0]['graphEdits']['addedNodes'] if n['id']==effect_id)['content']['effect']['_0']
            assert actual['plugin']['name']=='AUMatrixReverb' and actual['plugin']['type']==1635083896
            next(n for n in nodes if n['id']==effect_id)['content']['effect']['_0'].update(kind='audioUnit',plugin=actual['plugin'])
        if name=='global-effect-applied':
            actual=next(n for n in project['signal']['nodes'] if n['name']=='전역 공간')['effect']
            assert actual['plugin']['name']=='AUDelay' and actual['plugin']['type']==1635083896
            next(n for n in expected['signal']['nodes'] if n['name']=='전역 공간')['effect'].update(kind='audioUnit',plugin=actual['plugin'])
        if name=='missing-cancelled':
            instrument.update(kind='audioUnit',plugin=dict(name='설치되지 않은 악기 검증',type=1635085685,subtype=65535,manufacturer=65535))
        if name in ['final-inactive','final-bank','final-returned-synth','final-returned-au','final-synth-again']:
            instrument['plugin']=saved
        if name in ['bank-applied','final-bank']:instrument['kind']='soundBank'
        if name=='final-returned-au':instrument['kind']='audioUnit'
        assert document(project)==expected,name  # Also checks source, other uses, lanes, notes, assets and routing.
    assert captures['au-state']['manifest']==captures['au-reselected']['manifest']
    assert captures['restored']['manifest']==captures['reopened']['manifest']
    assert '20개 결과' in ax('picker-open') and 'container 앨범 서클 캔버스' not in ax('picker-open')
    assert '1개 결과' in ax('synth-search') and 'button (selected) 펄스 베이스' in ax('synth-search')
    assert '0개 결과' in ax('no-results') and '일치하는 음색이 없습니다' in ax('no-results')
    assert 'button (selected) 벨벳 EP' in ax('current-restored')
    assert '3개 결과' in ax('au-instruments') and 'AU 악기 · Apple' in ax('au-instruments')
    assert 'button (selected) DLSMusicDevice' in ax('au-selected')
    assert '대상이나 음악이 바뀌었거나' in ax('stale-rejected') and '(selected, disabled) 오로라 패드' in ax('stale-rejected')
    assert '26개 결과' in ax('global-open') and 'AU 악기' not in ax('global-open')
    assert '2개 결과' in ax('circle-effects') and 'AUMatrixReverb' in ax('circle-effects')
    assert '2개 결과' in ax('global-results') and 'AUDelay' in ax('global-results')
    assert 'button (selected) 전역 Audio Unit 이펙트 찾기' in ax('effect-command')
    assert '설치 목록에 없음' in ax('missing-plugin') and 'button (disabled) 현재 음색 찾기' in ax('missing-plugin')
    assert any('Description: 필터 Hz' in line and line.endswith('Value: 731') for line in ax('reopened').splitlines())
    for name in ['picker-open','current-restored','instrument-command','global-results','reopened-picker']:
        assert 'The focused UI element is 6 search text field' in ax(name),name
    assert captures['final-restored']['manifest']==captures['final-reopened']['manifest']
    for name in ['final-returned-synth','final-reopened']:
        assert any('Description: 필터 Hz' in line and line.endswith('Value: 731') for line in ax(name).splitlines())
    fixture=Path(captures['final-reopened']['state']['path']);source=fixture.with_name('studio.circlr')
    assert json.loads((fixture/'manifest.json').read_text())==captures['final-reopened']['manifest']
    assert digest(source/'manifest.json')=='12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d'
    for asset in baseline['assets']:
        for folder in [source,fixture]:assert digest(folder/asset['path'])==asset['checksum']
    app=OUT/'final/써클러 통합 검증.app';info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
    assert (info['CFBundleVersion'],info['CFBundleShortVersionString'],info['CFBundleIdentifier'])==('60','0.20.0','com.circlr.integrationqa')
    sections=runpy.run_path(str(ROOT/'qa/check-library-evidence.py'))['sections']
    compiled=sections(ROOT/'.build/integration-release/release/circlr')
    assert len(compiled)==37 and compiled==sections(app/'Contents/MacOS/circlr')
    subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
    sources=json.loads((OUT/'final/source-hashes.json').read_text());assert len(sources)==15
    previous=json.loads((OUT/'source-hashes.json').read_text())
    assert [name for name in sources if sources[name]!=previous[name]]==['Sources/CirclrCore/SoundSelection.swift']
    for name,expected in sources.items():assert digest(ROOT/name)==expected
    kit=app/'Contents/Resources/Codex';files=json.loads((kit/'manifest.json').read_text())['files'];assert len(files)==25
    for name,expected in files.items():assert digest(kit/name)==expected
    assert 'Executed 437 tests, with 0 failures' in (ROOT/'.build/sound-selection-final-tests.log').read_text()
    assert 'Ran 26 tests' in (ROOT/'.build/sound-selection-python.log').read_text()
    preserve=json.loads((OUT/'preservation.json').read_text())
    assert preserve['ownedQAProcesses']==[] and preserve['userApp']==['0.19.0','21']
    assert set(preserve['heads'].values())=={'d88ea5d8d5d87cf49c5ef06154397c36ba1019d7','1d304eb244f60a21c3598b89d05192d3512d719d'}
    for path,head in preserve['heads'].items():assert subprocess.check_output(['git','-C',path,'rev-parse','HEAD'],text=True).strip()==head
    assert not [line for line in subprocess.check_output(['ps','-axo','pid=,command='],text=True).splitlines()
                if len(line.split(None,1))==2 and line.split(None,1)[1].startswith(str(ROOT/'qa/generated')+'/') and '/Contents/MacOS/circlr' in line]
    screenshots={p.name:digest(p) for p in sorted(OUT.glob('*.jpg'))}
    assert len(screenshots)==len(list(OUT.glob('*.ax.txt')))==20
    result=dict(status='passed',nativeSnapshots=len(CASES),axCaptures=20,screenshots=screenshots,sourceFiles=15,
                kitFiles=25,executableSections=37,physicalAudioAttempts=0)
    (OUT/'verification.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({k:v for k,v in result.items() if k!='screenshots'},ensure_ascii=False))
