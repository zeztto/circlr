#!/usr/bin/env python3
"""Verify compact connection navigation without treating it as cable mutation QA."""
import hashlib
import importlib.util
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'qa/generated/connection-access'
spec=importlib.util.spec_from_file_location('checks',Path(__file__).with_name('check-midi-compact-evidence.py'))
c=importlib.util.module_from_spec(spec);spec.loader.exec_module(c)
def load(name):return json.loads((OUT/(name+'.json')).read_text())
def workspace(value):return value['manifest']['hierarchyView']['workspace']['connection']
def main():
    packages={name:load(name+'/package') for name in ['baseline','final','final2']}
    assert packages['baseline']['build']=='101'
    assert packages['final']['build']==packages['final2']['build']=='102'
    assert '36B23420-6ADF-3A38-8347-FEAC5E6F4C38' in packages['final2']['uuid']
    names=['compact','keyboard-list','reconnect','reconnect-list','reconnect-return','cancelled','wide','resized','reopened']
    first={name:load('final/'+name) for name in ['compact','query','list','query-return']}
    final={name:load('final2/'+name) for name in names}
    initial=load('baseline/fixture-initial')
    groups={'baseline':{'compact':load('baseline/compact')},'final':first,'final2':final}
    for phase,values in groups.items():
        for name,value in values.items():
            c.guard(value,packages[phase],36)
            assert c.music(value['manifest'])==c.music(initial),(phase,name)
    assert workspace(first['query'])['query']=='출력'
    assert workspace(first['query'])==workspace(first['list'])==workspace(first['query-return'])
    assert workspace(final['compact'])['query']=='출력'
    assert workspace(final['compact'])==workspace(final['keyboard-list'])
    recon=workspace(final['reconnect'])
    assert recon==workspace(final['reconnect-list'])==workspace(final['reconnect-return'])
    assert recon['query']=='' and recon['ownPortID']=='out.audio.main'
    assert recon['firstOctant']==2 and recon['secondOctant']==6
    assert recon['target']==recon['replacementDestination']
    assert recon['replacing']['from']==recon['replacementSource']['node']
    assert recon['replacing']['to']==recon['replacementDestination']['node']
    assert recon['replacementDestination']['node']['music']['nodeID']=='mix:7E0D9016-E91D-4325-B807-033F233E32EA'
    for name in ['cancelled','wide','resized','reopened']:
        assert workspace(final[name])==workspace(groups['baseline']['compact'])
    assert final['resized']['manifest']==final['reopened']['manifest']
    fixture=Path(packages['final2']['fixture'])
    assert json.loads((fixture/'manifest.json').read_text())==final['reopened']['manifest']
    for a in initial['assets']:
        path=Path(a['path']);assert not path.is_absolute() and '..' not in path.parts
        assert hashlib.sha256((fixture/path).read_bytes()).hexdigest()==a['checksum']
    assert hashlib.sha256((fixture.with_name('studio.circlr')/'manifest.json').read_bytes()).hexdigest()==packages['final2']['sourceSHA256']
    checks={'keyboard-list':'연결 표시 범위','reconnect':'대상 이름','reconnect-list':'연결 표시 범위','reconnect-return':'대상 이름','cancelled':'대상 이름'}
    for name,focus in checks.items():
        text=(OUT/'final2'/(name+'.ax.txt')).read_text()
        assert focus in text.split('The focused UI element is')[-1],name
    assert 'button 기존 연결' not in (OUT/'final2/wide.ax.txt').read_text()
    job=load('final2/reopen-job');done=load('final2/reopen-completed')
    assert done['job']['id']==job['jobID'] and done['job']['state']=='completed'
    assert done['revision']==36 and done['job']['path']==str(fixture)
    print(json.dumps({'status':'passed','baselineSnapshots':1,'firstCandidateSnapshots':4,'finalSnapshots':9,'focusAX':5,'assets':2,'physicalAudioAttempts':0}))
if __name__=='__main__':main()
