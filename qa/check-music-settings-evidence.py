#!/usr/bin/env python3
"""Verify native build65 edits against complete documents and the exact signed app."""
import copy
import hashlib
import json
from pathlib import Path
import plistlib
import runpy
import subprocess
import unicodedata

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'qa/generated/music-settings'
CASES={'baseline':14,'tempo-album':15,'tempo-local':16,'source-noop':16,'final-opened':16,
       'keyboard-candidate-restored':16,'refined-opened':16,'keyboard-album':17,'keyboard-local':18,
       'tempo-committed':19,'section-duration':21,'rhythm-local':22,'rhythm-undone':23,'settings-return':24,
       'section-undone':28,'section-restored':29,'midi-timing':32,'album-tempo':33,'music-restored':37,
       'composition-repeat':38,'final-saved':39,'saved-settings':39,'reopened-after-view':39}
SCREENS=['refined-keyboard-album','refined-tempo-album','refined-tempo-local','tempo-committed-tab',
         'section-duration','rhythm-local','rhythm-redone','connections-open','connections-tab','settings-return',
         'section-console-closed','midi-settings','midi-timing','album-settings','album-tempo',
         'composition-settings','composition-repeat','saved-music-settings','reopened-music','reopened-settings','advanced-scrollbar']

def load(name):return json.loads((OUT/(name+'.json')).read_text())
def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def music(p):
    p=copy.deepcopy(p);p.pop('musicRevision');p.pop('hierarchyView');return p

def main():
    captures={name:load(name) for name in CASES};baseline=music(captures['baseline']['manifest'])
    assert baseline==music(load('fixture-initial'))
    local132={'tempo-local','source-noop','final-opened','keyboard-candidate-restored','refined-opened','keyboard-local','section-undone'}
    local136={'tempo-committed','section-duration','rhythm-local','rhythm-undone','settings-return'}
    midi='midi:055F3787-2B9D-4DD1-9752-56106F8D94F5'
    for name,revision in CASES.items():
        data=captures[name];s=data['state'];p=data['manifest'];expected=copy.deepcopy(baseline)
        assert s['projectID']=='3950E095-CDF9-5AE9-AD06-8009326A4C93'
        assert s['revision']==p['musicRevision']==revision,name
        assert s['runtime']['build']=='65' and s['runtime']['bundleID']=='com.circlr.integrationqa'
        assert not s['dirty'] and s['output']['attempts']==s['audition']['attempts']==0
        assert not s['recording']['midi'] and not s['recording']['busy'] and not s['playback']['playing']
        assert s['library']['folders']==1
        use=expected['arrangements'][0]['uses'][0]
        if name in local132:use['settings']['tempo']['source']='local'
        if name in {'tempo-album','keyboard-album'}:use['settings']['tempo']['source']='global'
        if name in local136:use['settings']['tempo']={'source':'local','value':136}
        if name in {'section-duration','rhythm-local','rhythm-undone','settings-return'}:
            use['barsOverride']=12;use['repeatCount']=2
        if name in {'rhythm-local','settings-return'}:use['settings']['rhythm']['source']='local'
        if name in {'midi-timing','album-tempo'}:
            node=next(n for n in use['graphEdits']['addedNodes'] if n['id']==midi)
            node.update(startBeat=8.5,lengthBeats=24,repeatCount=2)
        if name=='album-tempo':expected['global']['tempo']=126
        if name=='composition-repeat':expected['album']['compositions'][0]['repeatCount']=3
        assert music(p)==expected,name # Includes every other note, original, port, effect, track, pattern and asset.
    assert captures['tempo-local']['manifest']==captures['source-noop']['manifest']
    assert not captures['source-noop']['beforeSave']['dirty']
    assert captures['keyboard-album']['state']['selection']==captures['keyboard-local']['state']['selection']==captures['tempo-committed']['state']['selection']
    for name in ['final-saved','saved-settings','reopened-after-view']:
        assert captures[name]['state']['selection']['music']['nodeID']==midi
    assert captures['reopened-after-view']['state']['job']['state']=='completed'
    for name in SCREENS:
        text=(OUT/(name+'.ax.txt')).read_text();assert '통합 편집 검증' in text,name
        assert (OUT/(name+'.jpg')).stat().st_size>10000
    ax=lambda name:(OUT/(name+'.ax.txt')).read_text()
    assert 'The focused UI element is 42 button 앨범' in ax('refined-keyboard-album')
    assert 'The focused UI element is 46 button 기본값, Description: 박자 출처' in ax('tempo-committed-tab')
    assert 'The focused UI element is 40 table 대상 포트 검색 결과' in ax('connections-tab')
    for name,value in [('refined-tempo-album','120'),('refined-tempo-local','132'),('tempo-committed-tab','136')]:
        assert any('템포 BPM,' in line and 'Value: '+value in line for line in ax(name).splitlines()),name
    assert '보관된 개별 값: 132 BPM' in ax('refined-tempo-album')
    assert '직접 만든 4박 킥' in ax('rhythm-local') and '직접 만든 4박 킥' in ax('rhythm-redone')
    assert 'Description: 부모 안 시작 박,' in ax('midi-timing') and 'Value: 9.5' in ax('midi-timing')
    assert 'button (selected) Description: 작업 전환 · 설정' in ax('reopened-music')
    assert '강세 묶음' in ax('advanced-scrollbar')
    app=OUT/'refined/써클러 통합 검증.app';info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
    assert (info['CFBundleVersion'],info['CFBundleShortVersionString'],info['CFBundleIdentifier'])==('65','0.20.0','com.circlr.integrationqa')
    sections=runpy.run_path(str(ROOT/'qa/check-library-evidence.py'))['sections']
    compiled=sections(ROOT/'.build/integration-release/release/circlr');assert len(compiled)==37 and compiled==sections(app/'Contents/MacOS/circlr')
    subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
    for name,value in load('refined/source-hashes').items():assert digest(ROOT/name)==value,name
    kit=app/'Contents/Resources/Codex';files=json.loads((kit/'manifest.json').read_text())['files'];assert len(files)==25
    for name,value in files.items():assert digest(kit/name)==value
    fixture=Path(captures['reopened-after-view']['state']['path']);original=fixture.with_name('studio.circlr')
    assert json.loads((fixture/'manifest.json').read_text())==captures['reopened-after-view']['manifest']
    assert digest(original/'manifest.json')=='12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d'
    for asset in baseline['assets']:
        for folder in [original,fixture]:assert digest(folder/asset['path'])==asset['checksum']
    assert 'Executed 463 tests, with 0 failures' in (ROOT/'.build/music-settings-tests.log').read_text()
    assert 'Ran 28 tests' in (ROOT/'.build/music-settings-python.log').read_text()
    assert 'Build complete!' in (ROOT/'.build/music-settings-refined-release.log').read_text()
    ps=unicodedata.normalize('NFC',subprocess.check_output(['ps','-axo','pid,command'],text=True))
    assert not any('/qa/generated/music-settings/' in line and line.endswith('/Contents/MacOS/circlr') for line in ps.splitlines())
    result=dict(status='passed',nativeSnapshots=len(CASES),finalScreens=len(SCREENS),sourceFiles=4,executableSections=len(compiled),kitFiles=len(files),physicalAudioAttempts=0)
    (OUT/'verification.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))

if __name__=='__main__':main()
