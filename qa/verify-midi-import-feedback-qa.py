#!/usr/bin/env python3
"""Snapshot/save exact build132 MIDI import feedback capture; musical changes require independent comparison."""
import argparse
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import unicodedata

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'qa/generated/midi-import-feedback'
FIXTURE=Path.home()/'Library/Application Support/circlr-integration-qa/fixtures/midi-import-feedback.circlr'
PROJECT_ID='850B9812-38E4-567C-ACD8-B47A6370128D'
BASELINE_NAME='baseline.json'
A='95B906AF-5A06-43F0-BF79-8EDB26A8973F';B='94300CA6-82FC-4C5E-816B-04CEEBD5745F'
HELPERS={'circlr-output-worker','circlr-au-effect-worker','circlr-au-instrument-worker','circlr-output-device-catalog','circlr-audition-worker'}
spec=importlib.util.spec_from_file_location('midi_feedback_transport',Path(__file__).with_name('verify-integration-native.py'))
q=importlib.util.module_from_spec(spec);spec.loader.exec_module(q)
q.FIXTURE=FIXTURE;q.PROJECT_ID=PROJECT_ID
sha=lambda path:hashlib.sha256(path.read_bytes()).hexdigest()


def assert_candidate_process(app):
    """Reject stale shared-socket captures when another integration QA binary is live."""
    expected=unicodedata.normalize('NFC',str(app/'Contents/MacOS/circlr'))
    rows=subprocess.check_output(['ps','-axo','pid=,comm='],text=True,timeout=10).splitlines()
    candidates=[]
    suffix='/써클러 통합 검증.app/Contents/MacOS/circlr'
    for row in rows:
        parts=row.strip().split(None,1)
        if len(parts)!=2:continue
        executable=unicodedata.normalize('NFC',parts[1])
        if executable.endswith(suffix):candidates.append((int(parts[0]),executable))
    assert len(candidates)==1 and candidates[0][1]==expected, f'Expected exactly one requested integration QA process: {candidates}'
    return candidates[0][0]


def state(expected_revision):
    s=q.state();assert s['runtime']['build']=='132' and s['revision']==expected_revision
    assert s['output']['attempts']==s['audition']['attempts']==0
    assert s['output']['phase']==s['audition']['phase']=='idle' and s['audition']['heldNotes']==0
    assert not s['playback']['playing'] and not any(s['recording'][k] for k in ['busy','audio','midi'])
    job=s.get('job')
    assert not job or job.get('state')!='running', 'Wait for active jobs before capture'
    return s


def capture(name,candidate,expected_revision):
    assert re.fullmatch('[a-z0-9-]{1,64}',name) and re.fullmatch('[a-z0-9-]{1,32}',candidate)
    directory=OUT/candidate;target=directory/(name+'.json');assert not target.exists()
    package=json.loads((directory/'package.json').read_text());app=directory/'써클러 통합 검증.app'
    assert package['app']==str(app) and str(package['build'])=='132'
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
    assert expected_revision >= 0
    candidate_pid=assert_candidate_process(app)
    before=state(expected_revision)
    assert assert_candidate_process(app)==candidate_pid
    q.call('save',dict(projectID=PROJECT_ID,expectedRevision=before['revision']))
    after=state(expected_revision)
    assert assert_candidate_process(app)==candidate_pid
    assert after['revision']==before['revision'] and not after['dirty']
    current=json.loads((FIXTURE/'manifest.json').read_text());baseline=json.loads((OUT/BASELINE_NAME).read_text())
    assert current['id']==PROJECT_ID and current['musicRevision']==expected_revision
    assert current['schemaVersion'] in [2,3,4]
    originals={a['id']:a for a in baseline['assets']};actual={a['id']:a for a in current['assets']}
    assert len(actual)==len(current['assets']) and all(actual.get(k)==v for k,v in originals.items())
    for asset in current['assets']:
        path=Path(asset['path']);assert not path.is_absolute() and '..' not in path.parts
        assert sha(FIXTURE/path)==asset['checksum']
    with target.open('x') as handle:
        json.dump(dict(state=after,manifest=current,expectedRevision=expected_revision,candidatePID=candidate_pid,
            validationScope='Identity/runtime/no-I/O/source asset integrity only; schema migration and musical changes require independent raw manifest comparison'),handle,ensure_ascii=False,indent=2)
        handle.write('\n')
    print(target)


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('name');parser.add_argument('--candidate',default='final132')
    parser.add_argument('--expected-revision',type=int,required=True)
    parser.add_argument('--unsupported',action='store_true',help='Explicitly use the isolated unsupported-audio copy')
    args=parser.parse_args()
    if args.unsupported:
        FIXTURE=FIXTURE.with_name('midi-import-feedback-unsupported.circlr')
        PROJECT_ID='6866C359-00CE-5BB2-91F0-F34CE840A10A'
        BASELINE_NAME='unsupported-baseline.json'
        q.FIXTURE=FIXTURE;q.PROJECT_ID=PROJECT_ID
    capture(args.name,args.candidate,args.expected_revision)
