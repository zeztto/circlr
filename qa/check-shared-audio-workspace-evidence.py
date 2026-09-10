#!/usr/bin/env python3
"""Read-only build116 evidence checker. Missing scenario evidence is a failure.

Music comparison excludes only musicRevision and hierarchyView (saved UI state).
No other fields, graph IDs, array order, or shared-pattern contents are normalized.
"""
import copy
import hashlib
import json
import struct
import uuid
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'qa/generated/shared-audio-workspace'
FINAL=OUT/'final2'  # Earlier final candidate is retained failed evidence, never accepted.
HELPERS={'circlr-output-worker','circlr-au-effect-worker','circlr-au-instrument-worker','circlr-output-device-catalog'}


def load(path):
    return json.loads(path.read_text())


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def by_id(values,identifier):
    matches=[value for value in values if value['id']==identifier]
    assert len(matches)==1,identifier
    return matches[0]


def music(project):
    result=copy.deepcopy(project)
    result.pop('musicRevision',None)
    result.pop('hierarchyView',None)
    return result


def verify_package(directory,scenario,build):
    package=load(directory/'package.json');injection=load(directory/'qa-injection.json')
    assert package['build']==build and package['projectID']==scenario['projectID']
    assert package['fixture']==scenario['fixture']
    main=Path(package['app'])/'Contents/MacOS/circlr'
    data=main.read_bytes();assert struct.unpack_from('<I',data)[0]==0xfeedfacf
    offset=32;identifiers=[]
    for _ in range(struct.unpack_from('<I',data,16)[0]):
        command,size=struct.unpack_from('<II',data,offset)
        assert size>=8 and offset+size<=len(data)
        if command==0x1b:
            assert size==24
            identifiers.append(str(uuid.UUID(bytes=data[offset+8:offset+24])).upper())
        offset+=size
    assert identifiers==[package['sourceBinaryUUID']]
    if directory.name=='final3':
        assert package['packagedMainUUID']==identifiers[0]
        assert digest(main)==package['packagedMainSHA256']
    assert injection['qaOnlyMock'] and injection['denyOutput'] and injection['outputWorkerExit']==78
    assert set(injection['packagedHelperSHA256'])==HELPERS
    for name,sha in injection['packagedHelperSHA256'].items():
        assert digest(Path(package['app'])/'Contents/MacOS'/name)==sha
    assert digest(directory/'production-helpers/circlr-output-worker')==injection['productionHelperSHA256']['circlr-output-worker']
    return package


def verify_capture(path,scenario,seed,build,revision):
    capture=load(path);state=capture['state'];project=capture['manifest']
    assert state['projectID']==project['id']==scenario['projectID']
    assert state['path']==scenario['fixture'] and not state['dirty']
    assert state['runtime']['build']==build and state['runtime']['bundleID']=='com.circlr.integrationqa'
    assert state['revision']==project['musicRevision']==revision
    assert state['output']['attempts']==state['audition']['attempts']==0
    assert not state['playback']['playing']
    assert not any(state['recording'][key] for key in ('busy','audio','midi'))
    assert project['assets']==seed['assets'] and len(project['assets'])==2
    for asset in project['assets']:
        relative=Path(asset['path'])
        assert not relative.is_absolute() and '..' not in relative.parts
        assert digest(Path(scenario['fixture'])/relative)==asset['checksum']
    return capture


def verify_pattern_only(project,baseline,pattern_id,expected_audio):
    expected=music(baseline)
    by_id(expected['patterns'],pattern_id)['audio']=copy.deepcopy(expected_audio)
    assert music(project)==expected


def verify_selected_clip(capture,scenario,use_id,clip_id):
    workspace=capture['manifest']['hierarchyView']['workspace']
    assert capture['state']['selection']['music']==dict(arrangementID=scenario['arrangementID'],useID=use_id,nodeID=scenario['rhythmAudioNodeID'])
    assert workspace['selection']['audioClipID']==clip_id


def verify_persistence(restored,reopened,scenario):
    assert restored['manifest']==reopened['manifest']==load(Path(scenario['fixture'])/'manifest.json')
    job=reopened['state']['job']
    assert job['kind']=='open' and job['state']=='completed' and job['progress']==1
    assert job['path']==scenario['fixture']


def main():
    scenario=load(OUT/'baseline/scenario.json');seed=load(OUT/'baseline/fixture-initial.json')
    assert seed['id']==scenario['projectID']
    assert digest(Path(scenario['source'])/'manifest.json')==scenario['sourceSHA256']
    assert by_id(seed['patterns'],scenario['patternID'])['audio']==scenario['clips']
    assert by_id(seed['patterns'],scenario['otherPatternID'])==scenario['otherPattern']
    verify_package(FINAL,scenario,'116')
    revisions={'before':18,'selected-second':18,'trimmed':19,'use-b':19,'trim-undo':20,'fade':21,'gain':22,
        'effects-undo':24,'split':25,'split-undo':26,'duplicated':27,'duplicate-deleted':28,'one-left':29,'last-delete':30,'delete-undo':32}
    captures={name:verify_capture(FINAL/(name+'.json'),scenario,seed,'116',revision) for name,revision in revisions.items()}
    original=copy.deepcopy(scenario['clips']);assert len(original)==2
    expected={name:copy.deepcopy(original) for name in revisions}
    for name in ('trimmed','use-b'):expected[name][1].update(sourceStart=4.25,duration=1.75)
    expected['fade'][1]['fadeIn']=0.05
    expected['gain'][1].update(fadeIn=.05,gain=10**(-12/20))
    split_observed=by_id(captures['split']['manifest']['patterns'],scenario['patternID'])['audio']
    right_ids=[c['id'] for c in split_observed if c['id'] not in scenario['clipIDs']]
    assert len(right_ids)==1
    window=dict(sourceStart=4,duration=2,cycleBeat=8,automaticEdges=False,envelopes=[])
    expected['split'][1].update(duration=1,renderWindow=window)
    right=copy.deepcopy(original[1]);right.update(id=right_ids[0],sourceStart=5,duration=1,beat=10,renderWindow=window)
    expected['split'].append(right)
    duplicate_observed=by_id(captures['duplicated']['manifest']['patterns'],scenario['patternID'])['audio']
    new_ids=[c['id'] for c in duplicate_observed if c['id'] not in scenario['clipIDs']]
    assert len(new_ids)==1 and new_ids[0]!=right_ids[0]
    duplicate=copy.deepcopy(original[0]);duplicate.update(id=new_ids[0],beat=4)
    expected['duplicated'].append(duplicate)
    expected['one-left']=[original[1]];expected['last-delete']=[]
    for name,capture in captures.items():
        verify_pattern_only(capture['manifest'],seed,scenario['patternID'],expected[name])
    for name in ('selected-second','trimmed'):
        verify_selected_clip(captures[name],scenario,scenario['useA'],scenario['clipIDs'][1])
    for name in ('use-b','fade','gain'):
        verify_selected_clip(captures[name],scenario,scenario['useB'],scenario['clipIDs'][1])
    verify_selected_clip(captures['split'],scenario,scenario['useB'],right_ids[0])
    verify_selected_clip(captures['duplicated'],scenario,scenario['useB'],new_ids[0])
    last=captures['last-delete']
    assert last['state']['selection']=={'section':dict(arrangementID=scenario['arrangementID'],useID=scenario['useB'])}
    selected=last['manifest']['hierarchyView']['workspace']['selection']
    assert 'audioClipID' not in selected and 'audioAssetID' not in selected
    ordinary=verify_capture(FINAL/'ordinary-gain.json',scenario,seed,'116',33)
    undone=verify_capture(FINAL/'ordinary-undo.json',scenario,seed,'116',34)
    assert music(undone['manifest'])==music(seed)
    address=ordinary['state']['selection']['music']
    assert address['arrangementID']==scenario['arrangementID'] and address['useID']==scenario['useA']
    assert address['nodeID']!=scenario['rhythmAudioNodeID']
    section=by_id(seed['sections'],scenario['sectionID'])
    node=by_id(section['graph']['nodes'],address['nodeID'])
    audio=node['content']['audio']
    lane=copy.deepcopy(by_id(section['lanes'],audio['laneID']))
    by_id(lane['audio'],audio['clipID'])['gain']=10**(-3/20)
    expected_ordinary=music(seed)
    target=by_id(by_id(expected_ordinary['arrangements'],scenario['arrangementID'])['uses'],scenario['useA'])
    target.setdefault('laneOverrides',{})[lane['id']]=lane
    assert music(ordinary['manifest'])==expected_ordinary
    final3=OUT/'final3'
    verify_package(final3,scenario,'116')
    targeted={name:verify_capture(final3/(name+'.json'),scenario,seed,'116',revision)
        for name,revision in {'before':34,'draft-switched':34,'trimmed':35,'trim-undo':36,'reopened':36}.items()}
    for name,capture in targeted.items():
        clips=copy.deepcopy(original)
        if name=='trimmed':clips[1].update(sourceStart=4.25,duration=1.75)
        verify_pattern_only(capture['manifest'],seed,scenario['patternID'],clips)
    verify_selected_clip(targeted['before'],scenario,scenario['useA'],scenario['clipIDs'][0])
    for name in ('draft-switched','trimmed','trim-undo','reopened'):
        verify_selected_clip(targeted[name],scenario,scenario['useA'],scenario['clipIDs'][1])
    verify_persistence(targeted['trim-undo'],targeted['reopened'],scenario)
    switched=(final3/'draft-switched.ax.txt').read_text()
    reopened=(final3/'reopened.ax.txt').read_text()
    for text in (switched,reopened):
        assert '선택 4.000부터 6.000초' in text
        assert 'sheet Description: alert' not in text
    invalid=(final3/'invalid-draft.ax.txt').read_text()
    assert 'Value: 99' in invalid
    assert 'Value: 99' not in switched
    print('PASS: mixed candidates: final2 shared/ordinary mutation suite; final3 draft identity, trim/Undo, selected-clip persistence and signed main identity; no physical audio exercised')


if __name__=='__main__':
    main()
