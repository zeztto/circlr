#!/usr/bin/env python3
"""Write an exclusive authored shared-audio seed or package a prebuilt build116 candidate."""
import argparse
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import plistlib
import shutil
import subprocess
import uuid

ROOT = Path(__file__).resolve().parents[1]
NAME = 'shared-audio-workspace'
OUT = ROOT / 'qa/generated' / NAME
SOURCE = Path.home() / 'Library/Application Support/circlr-integration-qa/fixtures/studio.circlr'
FIXTURE = SOURCE.with_name(NAME + '.circlr')


def ident(suffix=''):
    return str(uuid.uuid5(uuid.NAMESPACE_URL, 'circlr-integration-qa/' + NAME + suffix)).upper()


def module(name, file):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(file))
    result = importlib.util.module_from_spec(spec); spec.loader.exec_module(result)
    return result


def exclusive(path, value):
    with path.open('x') as handle:
        json.dump(value, handle, ensure_ascii=False, indent=2)
        handle.write('\n')


def seed():
    assert not OUT.exists() and not FIXTURE.exists(), 'Preserve all previous evidence'
    raw = (SOURCE / 'manifest.json').read_bytes()
    project = json.loads(raw)
    assert len(project['assets']) == 2 and project['patterns'] == [] and project['global']['rhythm'] == {}
    for asset in project['assets']:
        path = Path(asset['path'])
        assert path.parts and not path.is_absolute() and '..' not in path.parts
        assert hashlib.sha256((SOURCE / path).read_bytes()).hexdigest() == asset['checksum']
    arrangement = project['arrangements'][0]
    assert len(arrangement['uses']) == 1
    use = arrangement['uses'][0]
    rhythm = next(n for n in use['graphEdits']['addedNodes'] if 'rhythmAudio' in n['content'])
    track = rhythm['content']['rhythmAudio']['trackID']
    assert any(t['id'] == track for t in project['tracks'])
    section = next(s for s in project['sections'] if s['id'] == use['sectionID'])
    prototype = copy.deepcopy(section['lanes'][0]['audio'][0])
    clips = []
    for index, (beat, start) in enumerate([(0, 0), (8, 4)]):
        clip = copy.deepcopy(prototype)
        clip.update(id=ident('/clip-' + str(index)), beat=beat, sourceStart=start, duration=2, gain=[0.8,0.5][index])
        assert start + clip['duration'] <= next(a['duration'] for a in project['assets'] if a['id'] == clip['assetID'])
        clips.append(clip)
    pattern = dict(id=ident('/pattern'), name='함께 쓰는 오디오 리듬 · 두 클립', trackID=track,
                   length=16, meter=dict(numerator=4, denominator=4), notes=[], audio=clips)
    other_track = next(t['id'] for t in project['tracks'] if t['id'] != track)
    other_clip = copy.deepcopy(prototype)
    other_clip.update(id=ident('/other-clip'), assetID=project['assets'][1]['id'], duration=1, gain=0.75)
    other_pattern = dict(id=ident('/other-pattern'), name='보존 비교용 다른 트랙 패턴', trackID=other_track,
                         length=4, meter=dict(numerator=4, denominator=4), notes=[], audio=[other_clip])
    project['patterns'] = [pattern, other_pattern]
    project['global']['rhythm'] = dict(patternID=pattern['id'])
    assert section['settings']['rhythm']['source'] == use['settings']['rhythm']['source'] == rhythm['settings']['rhythm']['source'] == 'inherit'
    second = copy.deepcopy(use)
    use['name'] = '공유 오디오 A'
    second.update(id=ident('/use-b'), name='공유 오디오 B')
    arrangement['uses'].append(second)
    arrangement['layout']['positions'][second['id']] = dict(x=700,y=0)
    project.update(id=ident(), name='공유 오디오 작업 공간 검증')
    view = project['hierarchyView']
    view['selection'] = dict(music=dict(arrangementID=arrangement['id'],useID=use['id'],nodeID=rhythm['id']))
    view['settingsOpen'] = False
    view.pop('workspace',None); view.pop('editor',None)
    baseline = OUT / 'baseline'
    baseline.mkdir(parents=True); FIXTURE.mkdir()
    for asset in project['assets']:
        destination = FIXTURE / asset['path']; destination.parent.mkdir(parents=True,exist_ok=True)
        with destination.open('xb') as handle: handle.write((SOURCE / asset['path']).read_bytes())
    exclusive(FIXTURE / 'manifest.json',project)
    exclusive(baseline / 'fixture-initial.json',project)
    exclusive(baseline / 'scenario.json',dict(projectID=ident(),fixture=str(FIXTURE),source=str(SOURCE),
        sourceSHA256=hashlib.sha256(raw).hexdigest(),initialRevision=project['musicRevision'],candidateBuild='116',
        arrangementID=arrangement['id'],useA=use['id'],useB=second['id'],sectionID=section['id'],
        rhythmAudioNodeID=rhythm['id'],trackID=track,patternID=pattern['id'],clipIDs=[c['id'] for c in clips],
        clips=clips,otherPatternID=other_pattern['id'],otherTrackID=other_track,
        otherPattern=other_pattern,otherPatternActive=False,assets=2,
        context=dict(tempo=project['global']['tempo'],meter=project['global']['meter'],patternLength=16),
        scope='Authored studio assets; A/B inherit one pattern through actual rhythmAudio graph node; unrelated pattern/track retained for strict preservation checks',
        physicalAudioAttempts=0))
    assert (SOURCE / 'manifest.json').read_bytes() == raw
    print(json.dumps(dict(fixture=str(FIXTURE),projectID=ident(),patternID=pattern['id'],rhythmAudioNodeID=rhythm['id'],revision=project['musicRevision']),ensure_ascii=False))


def package(candidate, binary_dir, info_path):
    directory = OUT / candidate
    assert not directory.exists(), 'Preserve previous candidate'
    before = (FIXTURE / 'manifest.json').read_bytes(); assert json.loads(before)['id'] == ident()
    names = ['circlr','circlr-output-worker','circlr-au-effect-worker','circlr-au-instrument-worker','circlr-output-device-catalog']
    binary_dir = binary_dir.resolve()
    original_hashes = {name:hashlib.sha256((binary_dir / name).read_bytes()).hexdigest() for name in names}
    info = plistlib.loads(info_path.read_bytes())
    assert info['CFBundleVersion'] in ['115','116','117'] and info['CFBundleShortVersionString'] == '0.20.0'
    source_uuid = subprocess.check_output(['dwarfdump','--uuid',str(binary_dir / 'circlr')],text=True).split()[1]
    app = directory / '써클러 통합 검증.app'
    macos = app / 'Contents/MacOS'; macos.mkdir(parents=True)
    for name in names:
        shutil.copy2(binary_dir / name,macos / name)
        assert hashlib.sha256((macos / name).read_bytes()).hexdigest() == original_hashes[name]
    info.update(CFBundleIdentifier='com.circlr.integrationqa',CFBundleDisplayName='써클러 통합 검증',CFBundleName='써클러 통합 검증')
    info.pop('CFBundleDocumentTypes',None)
    (app / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
    resources = app / 'Contents/Resources'; resources.mkdir()
    for name in ['AppIcon.icns','Assets.car']: shutil.copy2(ROOT / 'Resources' / name,resources / name)
    shutil.copytree(ROOT / 'Resources/Codex',resources / 'Codex',ignore=shutil.ignore_patterns('__pycache__','*.pyc'))
    manifest = json.loads((resources / 'Codex/manifest.json').read_text())
    assert manifest['version'] == info['CFBundleShortVersionString']
    for name, digest in manifest['files'].items():
        assert hashlib.sha256((resources / 'Codex' / name).read_bytes()).hexdigest() == digest
    for name in names[1:]: subprocess.run(['codesign','--force','--sign','-',str(macos / name)],check=True)
    subprocess.run(['codesign','--force','--deep','--sign','-',str(app)],check=True)
    subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
    packaged_uuid = subprocess.check_output(['dwarfdump','--uuid',str(macos / 'circlr')],text=True).strip()
    assert packaged_uuid.split()[1] == source_uuid
    exclusive(directory / 'package.json',dict(app=str(app),fixture=str(FIXTURE),projectID=ident(),
        build=info['CFBundleVersion'],sourceSHA256=hashlib.sha256((SOURCE / 'manifest.json').read_bytes()).hexdigest(),
        uuid=packaged_uuid,binaryDirectory=str(binary_dir),sourceBinarySHA256=original_hashes,
        sourceBinaryUUID=source_uuid,infoSource=str(info_path.resolve())))
    module('shared_audio_deny','prepare-midi-generation-qa.py').deny_output(directory)
    # Preserve the provisional metadata consumed by the shared deny helper.
    # Only this new candidate is writable; prior candidate packages stay intact.
    preliminary = directory / 'package.json'
    complete = json.loads(preliminary.read_text())
    complete['packagedMainSHA256'] = hashlib.sha256((macos / 'circlr').read_bytes()).hexdigest()
    complete['packagedMainUUID'] = subprocess.check_output(['dwarfdump','--uuid',str(macos / 'circlr')],text=True).split()[1]
    assert complete['packagedMainUUID'] == source_uuid
    preliminary.rename(directory / 'package-before-injection.json')
    exclusive(directory / 'package.json',complete)

    assert (FIXTURE / 'manifest.json').read_bytes() == before
    assert all(hashlib.sha256((binary_dir / name).read_bytes()).hexdigest() == digest for name,digest in original_hashes.items())
    print(directory / 'package.json')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--candidate'); parser.add_argument('--binary-dir',type=Path)
    parser.add_argument('--info-plist',type=Path,default=ROOT / 'Resources/Info.plist')
    args = parser.parse_args()
    if not args.candidate:
        assert args.binary_dir is None
        seed(); return
    assert re.fullmatch('[a-z0-9-]{1,32}',args.candidate) and args.candidate != 'baseline'
    assert args.binary_dir is not None, 'Explicit verified --binary-dir is required; no cache defaults'
    package(args.candidate,args.binary_dir,args.info_plist)


if __name__ == '__main__': main()
