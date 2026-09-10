#!/usr/bin/env python3
"""Snapshot/save exact build128 editor-space QA; selection/view metadata only may differ."""
import argparse
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'qa/generated/editor-space'
FIXTURE=Path.home()/'Library/Application Support/circlr-integration-qa/fixtures/editor-space.circlr'
PROJECT_ID='84081CB3-F73E-4707-90E4-D9496B6083BE'
A='95B906AF-5A06-43F0-BF79-8EDB26A8973F';B='94300CA6-82FC-4C5E-816B-04CEEBD5745F'
HELPERS={'circlr-output-worker','circlr-au-effect-worker','circlr-au-instrument-worker','circlr-output-device-catalog','circlr-audition-worker'}
spec=importlib.util.spec_from_file_location('editor_space_transport',Path(__file__).with_name('verify-integration-native.py'))
q=importlib.util.module_from_spec(spec);spec.loader.exec_module(q)
q.FIXTURE=FIXTURE;q.PROJECT_ID=PROJECT_ID
sha=lambda path:hashlib.sha256(path.read_bytes()).hexdigest()


def state(expected_revision):
    s=q.state();assert s['runtime']['build']=='128' and s['revision']==expected_revision
    assert s['output']['attempts']==s['audition']['attempts']==0
    assert s['output']['phase']==s['audition']['phase']=='idle' and s['audition']['heldNotes']==0
    assert not s['playback']['playing'] and not any(s['recording'][k] for k in ['busy','audio','midi'])
    return s


def capture(name,candidate,expected_revision=62):
    assert re.fullmatch('[a-z0-9-]{1,64}',name) and re.fullmatch('[a-z0-9-]{1,32}',candidate)
    directory=OUT/candidate;target=directory/(name+'.json');assert not target.exists()
    package=json.loads((directory/'package.json').read_text());app=directory/'써클러 통합 검증.app'
    assert package['app']==str(app) and str(package['build'])=='128'
    mac=app/'Contents/MacOS';assert sha(mac/'circlr')==package['mainSHA256']
    assert subprocess.check_output(['dwarfdump','--uuid',str(mac/'circlr')],text=True).split()[1]==package['sourceUUID']
    assert set(package['helpers'])==HELPERS
    for helper,checksum in package['helpers'].items():assert sha(mac/helper)==checksum
    subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True,capture_output=True,timeout=60)
    codex=app/'Contents/Resources/Codex';manifest=json.loads((codex/'manifest.json').read_text())
    assert manifest['version']=='0.20.0'
    if 'codexManifestSHA256' in package:assert sha(codex/'manifest.json')==package['codexManifestSHA256']
    assert {str(f.relative_to(codex)) for f in codex.rglob('*') if f.is_file()}==set(manifest['files'])|{'manifest.json'}
    for filename,checksum in manifest['files'].items():assert sha(codex/filename)==checksum
    assert sha(codex/'skills/circlr-studio/scripts/mcp_server.py')==sha(ROOT/'mcp/server.py')
    assert expected_revision >= 62
    before=state(expected_revision);q.call('save',dict(projectID=PROJECT_ID,expectedRevision=before['revision']));after=state(expected_revision)
    assert after['revision']==before['revision'] and not after['dirty']
    current=json.loads((FIXTURE/'manifest.json').read_text());baseline=json.loads((OUT/'baseline.json').read_text())
    assert current['id']==PROJECT_ID and current['musicRevision']==expected_revision
    assert current['assets']==baseline['assets']
    for asset in current['assets']:
        path=Path(asset['path']);assert not path.is_absolute() and '..' not in path.parts
        assert sha(FIXTURE/path)==asset['checksum']
    def normalized(value):
        value=copy.deepcopy(value)
        for key in ['hierarchyView','layoutRevision','modifiedAt','musicRevision']:value.pop(key,None)
        return value
    assert normalized(current)==normalized(baseline), 'Unexpected musical change outside selection/view/revision metadata'
    with target.open('x') as handle:
        json.dump(dict(state=after,manifest=current,expectedRevision=expected_revision,
            validationScope='Explicit expectedRevision and exact baseline except hierarchyView, layoutRevision, modifiedAt, musicRevision; editing changes require separate evidence comparison'),handle,ensure_ascii=False,indent=2)
        handle.write('\n')
    print(target)


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('name');parser.add_argument('--candidate',default='final128')
    parser.add_argument('--expected-revision',type=int,default=62)
    args=parser.parse_args();capture(args.name,args.candidate,args.expected_revision)
