#!/usr/bin/env python3
"""Check captured edit scope, native gestures, restoration and package provenance."""
import copy
import hashlib
import json
import math
from pathlib import Path
import plistlib
import runpy
import subprocess

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'qa/generated/output-editing'
NODE='F040BB79-274C-5168-9E71-0B62AA6BDD50'
TRACK='3F85A31A-4CB4-5F71-9426-C593B94AC1D5'
KEYS=['global','tracks','sections','arrangements','assets','patterns','portLayout']

def capture(name,revision):
    data=json.loads((OUT/(name+'.json')).read_text());s=data['state']
    assert s['projectID']=='DBB508A6-2452-5CAD-8037-9E0804AA4EB1'
    assert s['runtime']['bundleID']=='com.circlr.integrationqa' and s['revision']==revision
    assert not s['dirty'] and not s['recording']['busy'] and not s['recording']['midi']
    return data['manifest']

def track(project):return next(t for t in project['tracks'] if t['id']==TRACK)
def original(project):return next(n for n in project['sections'][0]['graph']['nodes'] if n['id']==NODE)
def override(project,index=0):return project['arrangements'][0]['uses'][index]['graphEdits']['nodeOverrides'].get(NODE)
def ax(name):return (OUT/(name+'-ax.txt')).read_text()
def near(a,b):assert math.isclose(a,b,rel_tol=1e-12,abs_tol=1e-12),(a,b)

def main():
    before=capture('before',14)
    assert len(before['arrangements'][0]['uses'])==2
    circle=capture('circle-minus6',15)
    near(override(circle)['gain'],10**(-6/20))
    assert override(circle,1) is None and circle['tracks']==before['tracks'] and circle['sections']==before['sections']
    both=capture('track-minus6',16)
    near(track(both)['gain'],10**(-6/20))
    assert both['arrangements']==circle['arrangements'] and both['sections']==circle['sections']
    second=capture('second-use',16)
    for key in KEYS:assert second[key]==both[key],key
    muted=capture('circle-muted',17)
    assert override(muted)['muted'] and not track(muted)['muted'] and override(muted,1) is None
    shared=capture('original-minus3',19)
    expected=copy.deepcopy(both);original(expected)['gain']=10**(-3/20)
    for key in KEYS:assert shared[key]==expected[key],key
    for key in KEYS:assert capture('original-undo',20)[key]==both[key],key
    assert track(capture('track-muted',21))['muted']
    assert override(capture('silence',23))['gain']==0
    assert override(capture('unicode-silence',28))['gain']==0
    for name,revision in [('compact-restored',36),('final-restored',52),('reopened',52)]:
        restored=capture(name,revision)
        for key in KEYS:assert restored[key]==before[key],(name,key)
    dragged=capture('gesture-drag',37)
    assert 0<override(dragged)['gain']<1 and dragged['tracks']==before['tracks']
    near(override(capture('gesture-key',39))['gain'],10**(0.5/20))
    final_circle=capture('final-circle-minus6',45)
    near(override(final_circle)['gain'],10**(-6/20))
    assert final_circle['tracks']==before['tracks']
    final_shared=capture('final-original',46)
    assert final_shared['arrangements']==final_circle['arrangements']
    near(original(final_shared)['gain'],10**(-3/20))
    stale=capture('stale-rejected',48)
    near(override(stale)['gain'],10**(-6/20));assert track(stale)['gain']==0.65
    routes=capture('routes-no-mutation',48)
    for key in KEYS:assert routes[key]==stale[key],key
    near(track(capture('final-track-tab',49))['gain'],10**(-6/20))
    assert 'MCP 연결 가능 r38' in ax('gesture-undo') and 'MCP 연결 가능 r38' in ax('gesture-noop')
    assert 'Value: 0.60' in ax('gesture-fine') and 'Value: 3.60' in ax('gesture-coarse')
    assert 'MCP 연결 가능 r44' in ax('gesture-keys-restored') and 'Value: 0.00' in ax('gesture-keys-restored')
    assert 'MCP 연결 가능 r45' in ax('final-precision') and 'Value: -3.10' in ax('final-precision')
    assert '입력 범위: −∞–12.04 dB' in ax('invalid') and 'MCP 연결 가능 r22' in ax('invalid')
    assert '편집 대상이 변경되었습니다' in ax('stale-rejected') and 'MCP 연결 가능 r48' in ax('stale-rejected')
    assert 'The focused UI element is 25 container 앨범 서클 캔버스' in ax('stale-escape')
    assert 'radio button Description: 팬, Value: 1' in ax('pan-route')
    assert 'radio button Description: 볼륨, Value: 1' in ax('gain-route')
    assert '0개 점' in ax('gain-route') and '0개 점' in ax('pan-route')
    assert 'Description: 악기, Value: 내장 신스' in ax('instrument-only') and '레벨 dB' not in ax('instrument-only')
    assert '이번 사용에 추가된 서클입니다' in ax('added-output-original')
    assert 'Description: 서클 레벨 dB' in ax('added-output-local')
    source=Path.home()/'Library/Application Support/circlr-integration-qa/fixtures/studio.circlr'
    assert hashlib.sha256((source/'manifest.json').read_bytes()).hexdigest()=='12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d'
    fixture=source.with_name('output-editing.circlr')
    for asset in before['assets']:
        for folder in [source,fixture]:assert hashlib.sha256((folder/asset['path']).read_bytes()).hexdigest()==asset['checksum']
    app=OUT/'gesture/써클러 통합 검증.app'
    assert plistlib.loads((app/'Contents/Info.plist').read_bytes())['CFBundleVersion']=='33'
    sections=runpy.run_path(str(ROOT/'qa/check-library-evidence.py'))['sections']
    compiled=sections(ROOT/'.build/integration-release/release/circlr')
    assert compiled==sections(app/'Contents/MacOS/circlr')
    subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
    hashes=json.loads((OUT/'gesture/source-hashes.json').read_text())
    for name,digest in hashes.items():assert hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==digest
    kit=app/'Contents/Resources/Codex';files=json.loads((kit/'manifest.json').read_text())['files']
    for name,digest in files.items():assert hashlib.sha256((kit/name).read_bytes()).hexdigest()==digest
    assert 'Executed 303 tests, with 0 failures' in (OUT/'final-tests.log').read_text()
    assert 'Ran 26 tests' in (OUT/'python-tests.log').read_text()
    result=dict(result='passed',scope='Native level editing and offline PCM; no physical audio input/output',revision=52,
        fileBackedSections=len(compiled),kitFiles=len(files),sourceFiles=len(hashes),
        uuid=subprocess.check_output(['dwarfdump','--uuid',str(app/'Contents/MacOS/circlr')],text=True).strip())
    (OUT/'verification.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(result,ensure_ascii=False))

if __name__=='__main__':main()
