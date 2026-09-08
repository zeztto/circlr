#!/usr/bin/env python3
"""Verify only the captured offline and native cancellation scope, not audible playback."""
import hashlib
import json
from pathlib import Path
import plistlib
import runpy
import subprocess

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'qa/generated/output-lifecycle'

def capture(name):
    result=json.loads((OUT/(name+'.json')).read_text());state=result['state']
    assert state['projectID']=='872A0FCD-8E1B-50AD-91D9-0E91051382CA'
    assert state['runtime']['bundleID']=='com.circlr.integrationqa'
    assert not state['recording']['busy'] and not state['recording']['midi']
    return result

def main():
    before=capture('before')['manifest']
    for name,revision in [('undo',16),('first-final',16),('final-save',18),('reopened',18)]:
        data=capture(name)
        assert data['state']['revision']==revision and not data['state']['dirty']
        for key in ['global','tracks','sections','arrangements','assets','patterns','portLayout']:
            assert data['manifest'][key]==before[key],(name,key)
    assert capture('edited')['state']['revision']==15
    assert capture('final-space-start')['state']['revision']==17
    first=capture('timed-out')['state']['output']
    assert first['phase']=='connecting' and first['request']=='timedOut'
    assert capture('first-final')['state']['output']['attemptID']==first['attemptID']
    start=capture('final-space-start')['state']['output']
    for name in ['paired-space-stop','final-save','reopened']:
        state=capture(name)['state'];output=state['output']
        assert output['attemptID']==start['attemptID'] and output['attempts']==1
        assert output['request']=='cancelled' and output['transport']['phase']=='idle'
        assert not state['playback']['playing'] and not output['transport']['didStart']
    assert capture('paired-space-stop')['state']['playback']['canvasKeyboardFocus']
    assert capture('reopened')['state']['job']['state']=='completed'
    for name in ['final-return-ax','final-escape-ax']:
        text=(OUT/(name+'.txt')).read_text()
        assert 'Value: 0.65' in text
        assert 'The focused UI element is 25 container 앨범 서클 캔버스' in text
    assert 'button Description: 재생 준비 취소' in (OUT/'paired-space-start-ax.txt').read_text()
    assert 'button Description: 재생, Help: 재생 / 정지' in (OUT/'paired-space-stop-ax.txt').read_text()
    assert 'Value: qa , Placeholder: help' in (OUT/'final-console-space-ax.txt').read_text()
    stack=(OUT/'native-wait-stack.txt').read_text()
    assert 'circlr.playback-output' in stack and 'AVAudioEngineImpl::GetIOUnit' in stack
    source=Path.home()/'Library/Application Support/circlr-integration-qa/fixtures/studio.circlr'
    assert hashlib.sha256((source/'manifest.json').read_bytes()).hexdigest()=='12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d'
    fixture=source.with_name('output-lifecycle.circlr')
    for asset in before['assets']:
        assert hashlib.sha256((fixture/asset['path']).read_bytes()).hexdigest()==asset['checksum']
        assert hashlib.sha256((source/asset['path']).read_bytes()).hexdigest()==asset['checksum']
    app=OUT/'focus/써클러 통합 검증.app'
    assert plistlib.loads((app/'Contents/Info.plist').read_bytes())['CFBundleVersion']=='32'
    sections=runpy.run_path(str(ROOT/'qa/check-library-evidence.py'))['sections']
    compiled=sections(ROOT/'.build/integration-release/release/circlr')
    assert compiled==sections(app/'Contents/MacOS/circlr')
    subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
    hashes=json.loads((OUT/'focus/source-hashes.json').read_text())
    for name,digest in hashes.items():assert hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==digest
    kit=app/'Contents/Resources/Codex';files=json.loads((kit/'manifest.json').read_text())['files']
    for name,digest in files.items():assert hashlib.sha256((kit/name).read_bytes()).hexdigest()==digest
    assert 'Executed 293 tests, with 0 failures' in (OUT/'swift-tests.log').read_text()
    assert 'Ran 26 tests' in (OUT/'python-tests.log').read_text()
    result=dict(result='passed',scope='Offline lifecycle and native cancellation/editing only',revision=18,
        fileBackedSections=len(compiled),kitFiles=len(files),sourceFiles=len(hashes),
        actualPlayback='Not verified: HAL output acquisition remained pending.',
        uuid=subprocess.check_output(['dwarfdump','--uuid',str(app/'Contents/MacOS/circlr')],text=True).strip())
    (OUT/'verification.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(result,ensure_ascii=False))

if __name__=='__main__':main()
