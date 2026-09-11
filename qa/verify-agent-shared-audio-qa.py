#!/usr/bin/env python3
"""Guarded shared-audio QA capture/apply/Undo. Never plays, auditions or records."""
import argparse
import importlib.util
import json
from pathlib import Path
import re


def module(name,file):
    spec=importlib.util.spec_from_file_location(name,Path(__file__).with_name(file));m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m

p=module('agent_shared_package','prepare-agent-shared-audio-qa.py')
q=module('agent_shared_transport','verify-integration-native.py')
q.FIXTURE=p.FIXTURE;q.PROJECT_ID=p.PROJECT_ID


def state():
    s=q.state();assert s['runtime']['build']=='125'
    assert s['output']['attempts']==s['audition']['attempts']==0
    assert s['output']['phase']==s['audition']['phase']=='idle' and s['audition']['heldNotes']==0
    assert not s['playback']['playing'] and not any(s['recording'][k] for k in ['busy','audio','midi'])
    return s


def write(name,args=None):
    assert name in ['apply','undo','save']
    if name=='apply':
        assert all(op.get('kind') in ['edit_shared_audio','set_automation'] for op in (args or {}).get('operations',[]))
    s=state();result=q.call(name,dict(args or {},projectID=s['projectID'],expectedRevision=s['revision']));state();return result


def capture(name,candidate,operations=None,undo=False):
    assert re.fullmatch('[a-z0-9-]{1,64}',name) and re.fullmatch('[a-z0-9-]{1,32}',candidate)
    directory=p.OUT/candidate;target=directory/(name+'.json');assert not target.exists()
    package=json.loads((directory/'package.json').read_text());assert package['build']=='125' and package['fixture']==str(p.FIXTURE) and package['projectID']==p.PROJECT_ID
    scenario=json.loads((p.OUT/'baseline/scenario.json').read_text());assert p.digest(p.SOURCE)==package['sourceSHA256']==scenario['sourceSHA256']
    app=Path(package['app']);assert app==directory/'써클러 통합 검증.app';mac=app/'Contents/MacOS'
    assert p.digest(mac/'circlr')==package['mainSHA256'] and p.run(['dwarfdump','--uuid',str(mac/'circlr')]).split()[1]==package['sourceUUID']
    assert set(package['helpers'])==set(p.p.HELPERS)
    for helper,checksum in package['helpers'].items():assert p.digest(mac/helper)==checksum
    p.run(['codesign','--verify','--deep','--strict',str(app)])
    codex=app/'Contents/Resources/Codex'
    assert p.digest(codex/'manifest.json')==package['codexManifestSHA256']
    manifest_files=json.loads((codex/'manifest.json').read_text())['files']
    assert manifest_files==package['codexFiles']
    assert {str(f.relative_to(codex)) for f in codex.rglob('*') if f.is_file()}==set(manifest_files)|{'manifest.json'}
    for name1,checksum in manifest_files.items():assert p.digest(codex/name1)==checksum
    assert p.digest(codex/'skills/circlr-studio/scripts/mcp_server.py')==package['mcpSourceSHA256']==p.digest(p.ROOT/'mcp/server.py')
    assert not (operations is not None and undo)
    before=state();action=None
    if operations is not None:
        assert isinstance(operations,list) and operations
        action=write('apply',dict(operations=operations))
    if undo:action=write('undo')
    saving=state();write('save');after=state();assert after['revision']==saving['revision'] and not after['dirty']
    manifest=json.loads((p.FIXTURE/'manifest.json').read_text());seed=json.loads((p.OUT/'baseline/fixture-initial.json').read_text())
    assert manifest['musicRevision']==after['revision'] and manifest['id']==p.PROJECT_ID and manifest['assets']==seed['assets']
    for asset in manifest['assets']:
        path=Path(asset['path']);assert not path.is_absolute() and '..' not in path.parts
        assert p.digest(p.FIXTURE/path)==asset['checksum']
    p.exclusive(target,dict(state=after,manifest=manifest,beforeRevision=before['revision'],action=action,
        scope='Identity/no-I/O/asset guards; exact target changes require separate snapshot comparison'))
    print(target)


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('name');parser.add_argument('--candidate',required=True);parser.add_argument('--apply-json',type=Path);parser.add_argument('--undo',action='store_true');a=parser.parse_args()
    capture(a.name,a.candidate,json.loads(a.apply_json.read_text()) if a.apply_json else None,a.undo)
