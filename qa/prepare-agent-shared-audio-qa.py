#!/usr/bin/env python3
"""Prepare a declared shared-audio fixture edit and an isolated prebuilt build125 QA app."""
import argparse
import copy
import importlib.util
import json
from pathlib import Path
import plistlib
import re
import shutil
import uuid

spec=importlib.util.spec_from_file_location('shared_audio_helpers',Path(__file__).with_name('prepare-synth-workspace-qa.py'))
p=importlib.util.module_from_spec(spec);spec.loader.exec_module(p)
ROOT=p.ROOT; OUT=ROOT/'qa/generated/agent-shared-audio'
SOURCE=ROOT/'qa/generated/audio-automation-flow/final124/saved.json'
FIXTURE=Path.home()/'Library/Application Support/circlr-integration-qa/fixtures/agent-shared-audio.circlr'
PROJECT_ID=str(uuid.uuid5(uuid.NAMESPACE_URL,'circlr-integration-qa/agent-shared-audio')).upper()
digest,exclusive,run=p.digest,p.exclusive,p.run


def seed():
    assert not OUT.exists() and not FIXTURE.exists()
    record=json.loads(SOURCE.read_text()); original=record['manifest']; project=copy.deepcopy(original)
    assert project['musicRevision']==28
    source_fixture=Path(record['state']['path'])
    pattern=project['patterns'][0]; assert not pattern['audio']
    track=pattern['trackID']; node_id='rhythm-audio:'+track
    arrangement=project['arrangements'][0]; assert len(arrangement['uses'])==2
    for use in arrangement['uses']:
        node=next(n for n in use['graphEdits']['addedNodes'] if n['id']==node_id)
        assert node['content']=={'rhythmAudio':{'trackID':track}}
        section=next(s for s in project['sections'] if s['id']==use['sectionID'])
        assert node['settings']['rhythm']['source']==use['settings']['rhythm']['source']==section['settings']['rhythm']['source']=='inherit'
    assert project['global']['rhythm']['patternID']==pattern['id']
    asset=next(a for a in project['assets'] if a['id']=='69276595-4C4D-50C1-B3B6-820A8AA9196B')
    clip=dict(id=str(uuid.uuid5(uuid.NAMESPACE_URL,'circlr-integration-qa/agent-shared-audio/clip')).upper(),
        assetID=asset['id'],beat=0,sourceStart=0,duration=1,gain=1,sourceBPM=120,followsTempo=False,fadeIn=0,fadeOut=0)
    pattern['audio'].append(clip)
    project.update(id=PROJECT_ID,name='에이전트 공유 오디오 검증')
    project['hierarchyView']['selection']=dict(music=dict(arrangementID=arrangement['id'],useID=arrangement['uses'][0]['id'],nodeID=node_id))
    project['hierarchyView']['settingsOpen']=False
    baseline=OUT/'baseline';baseline.mkdir(parents=True);FIXTURE.mkdir()
    for a in project['assets']:
        path=Path(a['path']);assert not path.is_absolute() and '..' not in path.parts
        assert digest(source_fixture/path)==a['checksum']
        dest=FIXTURE/path;dest.parent.mkdir(parents=True,exist_ok=True)
        with dest.open('xb') as f:f.write((source_fixture/path).read_bytes())
    exclusive(FIXTURE/'manifest.json',project);exclusive(baseline/'fixture-initial.json',project)
    exclusive(baseline/'scenario.json',dict(projectID=PROJECT_ID,fixture=str(FIXTURE),source=str(SOURCE),sourceSHA256=digest(SOURCE),
        initialRevision=28,arrangementID=arrangement['id'],useIDs=[u['id'] for u in arrangement['uses']],
        nodeID=node_id,trackID=track,patternID=pattern['id'],clipID=clip['id'],outputNodeID='output:'+track,
        assets=project['assets'],scope='Fixture preparation adds exactly one authored 1-second shared audio clip; no production music edits; existing two rhythmAudio consumers retained',physicalAudioAttempts=0))
    print(json.dumps(dict(fixture=str(FIXTURE),projectID=PROJECT_ID,patternID=pattern['id'],clipID=clip['id'],nodeID=node_id)))


def package(candidate,binary,info_path):
    directory=OUT/candidate;assert not directory.exists()
    scenario=json.loads((OUT/'baseline/scenario.json').read_text());assert digest(SOURCE)==scenario['sourceSHA256']
    metadata=json.loads((ROOT/'qa/generated/audio-automation-flow/final124/package.json').read_text())
    source_app=Path(metadata['app']);assert set(metadata['helpers'])==set(p.HELPERS)
    for name,checksum in metadata['helpers'].items():assert digest(source_app/'Contents/MacOS'/name)==checksum
    run(['codesign','--verify','--deep','--strict',str(source_app)])
    info=plistlib.loads(info_path.read_bytes());assert info['CFBundleVersion']=='125'
    source_hash=digest(binary);source_uuid=run(['dwarfdump','--uuid',str(binary)]).split()[1]
    app=directory/'써클러 통합 검증.app';directory.mkdir();shutil.copytree(source_app,app)
    mac=app/'Contents/MacOS';shutil.copy2(binary,mac/'circlr')
    codex=app/'Contents/Resources/Codex'
    # Only the newly created candidate's cloned resources are replaced.
    shutil.rmtree(codex)
    shutil.copytree(ROOT/'Resources/Codex',codex,ignore=shutil.ignore_patterns('__pycache__','*.pyc'))
    manifest=json.loads((codex/'manifest.json').read_text())
    assert manifest['version']==info['CFBundleShortVersionString']
    actual={str(f.relative_to(codex)) for f in codex.rglob('*') if f.is_file()}
    assert actual==set(manifest['files'])|{'manifest.json'}
    for name,checksum in manifest['files'].items():assert digest(codex/name)==checksum
    mcp_name='skills/circlr-studio/scripts/mcp_server.py'
    assert digest(codex/mcp_name)==digest(ROOT/'mcp/server.py')
    codex_hash=digest(codex/'manifest.json');mcp_hash=digest(ROOT/'mcp/server.py')
    info.update(CFBundleIdentifier='com.circlr.integrationqa',CFBundleDisplayName='써클러 통합 검증',CFBundleName='써클러 통합 검증');info.pop('CFBundleDocumentTypes',None)
    (app/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
    run(['codesign','--force','--deep','--sign','-',str(app)]);run(['codesign','--verify','--deep','--strict',str(app)])
    assert run(['dwarfdump','--uuid',str(mac/'circlr')]).split()[1]==source_uuid and digest(binary)==source_hash
    for name,checksum in metadata['helpers'].items():assert digest(mac/name)==checksum
    exclusive(directory/'package.json',dict(app=str(app),build='125',projectID=PROJECT_ID,fixture=str(FIXTURE),
        sourceBinary=str(binary.resolve()),sourceSHA256=digest(SOURCE),sourceBinarySHA256=source_hash,sourceUUID=source_uuid,
        mainSHA256=digest(mac/'circlr'),helpers=metadata['helpers'],helperSourcePackage=str(source_app),signatureVerified=True,
        codexManifestSHA256=codex_hash,codexFiles=manifest['files'],mcpSourceSHA256=mcp_hash))
    print(directory/'package.json')


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--candidate');parser.add_argument('--binary',type=Path);parser.add_argument('--info-plist',type=Path);a=parser.parse_args()
    if a.candidate:
        assert re.fullmatch('[a-z0-9-]{1,32}',a.candidate) and a.candidate!='baseline' and a.binary and a.info_plist
        package(a.candidate,a.binary,a.info_plist)
    else:
        assert a.binary is None and a.info_plist is None;seed()
