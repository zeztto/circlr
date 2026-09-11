#!/usr/bin/env python3
"""Validate build114 final2 captures without operating the app or audio devices."""
import copy
import hashlib
import json
from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'qa/generated/audio-handles'
FINAL=OUT/'final2'
def load(path): return json.loads(path.read_text())
def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def item(values,identifier):
    result=[v for v in values if v['id']==identifier]
    assert len(result)==1,identifier
    return result[0]
def music(project):
    result=copy.deepcopy(project)
    result.pop('musicRevision',None);result.pop('hierarchyView',None)
    return result

def main():
    scenario=load(OUT/'baseline/scenario.json');seed=load(OUT/'baseline/fixture-initial.json')
    package=load(FINAL/'package.json');injection=load(FINAL/'qa-injection.json')
    assert package['build']=='114' and package['projectID']==scenario['projectID']
    assert injection['qaOnlyMock'] and injection['denyOutput'] and injection['outputWorkerExit']==78
    for name,sha in injection['packagedHelperSHA256'].items():
        assert digest(Path(package['app'])/'Contents/MacOS'/name)==sha
    assert digest(FINAL/'production-helpers/circlr-output-worker')==injection['productionHelperSHA256']['circlr-output-worker']
    assert digest(Path(scenario['source'])/'manifest.json')==scenario['sourceSHA256']
    revisions={'before':18,'start-dragged':19,'start-cursor':20,'end-dragged':21,'fitted':22,'all':22,
        'tiny-before':22,'tiny-cursor':22,'tiny-end-dragged':23,'tiny-end-undo':24,'tiny-start-dragged':25,'tiny-restored':26,
        'middle-expanded':27,'middle-before':28,'middle-cursor':28,'middle-end-dragged':29,'middle-undo':30,
        'middle-expanded-undo':31,'restored':32,'reopened':32}
    captures={name:load(FINAL/(name+'.json')) for name in revisions}
    # Only observed endpoint values enter the expected copy, after independent gesture checks below.
    changes={'start-dragged':'startRegion','end-dragged':'startRegion','tiny-end-dragged':'endRegion',
        'tiny-start-dragged':'endRegion','middle-expanded':'startRegion','middle-before':'startRegion',
        'middle-cursor':'startRegion','middle-end-dragged':'startRegion','middle-undo':'startRegion','middle-expanded-undo':'startRegion'}
    def target_use(project):return item(item(project['arrangements'],scenario['arrangementID'])['uses'],scenario['useID'])
    def source_lane(region):return item(item(seed['sections'],scenario['sectionID'])['lanes'],region['laneID'])
    def clip(project,region):
        lane=target_use(project).get('laneOverrides',{}).get(region['laneID'],source_lane(region))
        return item(lane['audio'],region['clipID'])
    for name,capture in captures.items():
        state,project=capture['state'],capture['manifest']
        assert state['projectID']==project['id']==scenario['projectID']
        assert state['path']==scenario['fixture'] and not state['dirty']
        assert state['runtime']['build']=='114' and state['runtime']['bundleID']=='com.circlr.integrationqa'
        assert state['revision']==project['musicRevision']==revisions[name],name
        assert state['output']['attempts']==state['audition']['attempts']==0
        assert not state['playback']['playing'] and not any(state['recording'][k] for k in ('busy','audio','midi'))
        assert project['assets']==seed['assets'] and len(project['assets'])==2
        expected=music(seed)
        if name in changes:
            region=scenario[changes[name]];observed=clip(project,region)
            lane=copy.deepcopy(source_lane(region));original=item(lane['audio'],region['clipID'])
            original['sourceStart']=observed['sourceStart'];original['duration']=observed['duration']
            assert observed==original and observed['duration']>=0.01 and observed['sourceStart']>=0
            assert observed['sourceStart']+observed['duration']<=32+1e-12
            target_use(expected).setdefault('laneOverrides',{})[region['laneID']]=lane
        assert music(project)==expected,name
    for asset in seed['assets']:
        assert digest(Path(scenario['fixture'])/asset['path'])==asset['checksum']
    tolerance=32/908  # One screenshot pixel; native geometry has subpixel coordinates.
    gestures=[('start-dragged','startRegion',False,0,.5,55,58),('end-dragged','startRegion',True,0,.5,69,73),
        ('tiny-end-dragged','endRegion',True,31.95,.05,964,963),('tiny-start-dragged','endRegion',False,31.95,.05,962,963),
        ('middle-end-dragged','startRegion',True,16,.5,524,528)]
    for name,key,end,start,duration,x0,x1 in gestures:
        observed=clip(captures[name]['manifest'],scenario[key]);stop=start+duration
        # Linear phase clamps at the visible plot boundary before accumulating travel.
        delta=(min(1,max(0,(x1-55.5)/908))-min(1,max(0,(x0-55.5)/908)))*32
        old=stop if end else start
        predicted=min(32,max(start+.01,old+delta)) if end else min(stop-.01,max(0,old+delta))
        actual=observed['sourceStart']+observed['duration'] if end else observed['sourceStart']
        assert abs(actual-predicted)<=tolerance,name
        assert (actual-old)*delta>0,name
        if end: assert observed['sourceStart']==start,name
        else: assert abs(observed['sourceStart']+observed['duration']-stop)<1e-12,name
    for name,start,duration in [('middle-expanded',0,16.5),('middle-expanded-undo',0,16.5),
        ('middle-before',16,.5),('middle-cursor',16,.5),('middle-undo',16,.5)]:
        observed=clip(captures[name]['manifest'],scenario['startRegion'])
        assert observed['sourceStart']==start and observed['duration']==duration,name
    for name,key,x,expected in [('start-cursor','startRegion',62,.227),('tiny-cursor','endRegion',963,.038),('middle-cursor','startRegion',514,.160)]:
        text=(FINAL/(name+'.ax.txt')).read_text()
        match=re.search(r'오디오 분할 위치 초[^\n]*Value: ([0-9.]+)',text);assert match,name
        offset=float(match[1]);current=clip(captures[name]['manifest'],scenario[key])
        assert 0<offset<current['duration'] and abs(offset-expected)<.0005,name
        assert abs(offset-max(0,min(current['duration'],(x-55.5)/908*32-current['sourceStart'])))<=tolerance,name
        assert '원본 표시 0.000부터 32.000초' in text
        position=captures[name]['manifest']['hierarchyView']['workspace']['selection']['audioSourcePosition']
        assert abs(position-current['sourceStart']-offset)<=.0005,name
        prior={'start-cursor':'before','tiny-cursor':'tiny-before','middle-cursor':'middle-before'}[name]
        assert position!=captures[prior]['manifest']['hierarchyView']['workspace']['selection'].get('audioSourcePosition'),name
    assert '원본 표시 0.000부터 0.550초' in (FINAL/'fitted.ax.txt').read_text()
    assert captures['fitted']['manifest']['hierarchyView']['workspace']['editor']['audio']=={'fitted':[0,0.55]}
    assert captures['all']['manifest']['hierarchyView']['workspace']['editor']['audio']=={}
    assert captures['restored']['manifest']==captures['reopened']['manifest']==load(Path(scenario['fixture'])/'manifest.json')
    job=captures['reopened']['state']['job']
    assert job['kind']=='open' and job['state']=='completed' and job['progress']==1 and job['path']==scenario['fixture']
    print('PASS: 20 final2 captures; independent trim/cursor checks, exact music preservation, Undo, full persistence, assets and no physical output')
if __name__=='__main__':main()
