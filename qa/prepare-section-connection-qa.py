#!/usr/bin/env python3
"""Package build 64 with authored section branches and a separate owner."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import uuid

spec=importlib.util.spec_from_file_location('packager',Path(__file__).with_name('prepare-automation-workspace-qa.py'))
packager=importlib.util.module_from_spec(spec);spec.loader.exec_module(packager)
packager.NAME='section-connection';packager.BUILD='64'
packager.OUT=packager.ROOT/'qa/generated/section-connection';packager.APP=packager.OUT/'써클러 통합 검증.app'
packager.FIXTURE=packager.SOURCE.with_name('section-connection.circlr')


def identifier(name):return str(uuid.uuid5(uuid.NAMESPACE_URL,'circlr-integration-qa/section-connection/'+name)).upper()


if __name__=='__main__':
    packager.main()
    if '--candidate' not in sys.argv:
        path=packager.FIXTURE/'manifest.json';p=json.loads(path.read_text());a=p['arrangements'][0]
        a['name']='공연 편곡';a['uses'][0]['name']='인트로 · 북유럽의 밤';a['uses'][1]['name']='도시의 밤'
        for index in range(3,33):
            use=copy.deepcopy(a['uses'][1]);use['id']=identifier('use-'+str(index))
            use['name']='도시의 밤' if index==3 else '섹션 '+str(index)
            if index==32:use['name']='도시의 여운 · 북유럽 신스와 시티팝을 길게 잇는 마지막 섹션 · Northern city reprise'
            a['uses'].append(use);a['layout']['positions'][use['id']]={'x':((index-1)%8)*700,'y':((index-1)//8)*650}
        a['uses'][0]['isEnd']=False
        for index in [2,3]:
            a['edges'].append(dict(id=identifier('edge-'+str(index)),**{'from':a['uses'][0]['id'],'to':a['uses'][index-1]['id']},
                                  transition=dict(mode='within',anchor='sourceBars',length=.125,
                                                  effect=dict(kind='lowpass',amount=.4,secondary=.25))))
        a['chosenEdges'][a['uses'][0]['id']]=a['edges'][0]['id']
        p['album']['compositions'][0]['name']='f0r h3r · 공연 구성'
        other=copy.deepcopy(a);other['id']=identifier('other-arrangement');other['name']='별도 편곡'
        other['uses']=[copy.deepcopy(a['uses'][1])];other['uses'][0]['id']=identifier('other-use')
        other['edges']=[];other['chosenEdges']={};other['startID']=other['uses'][0]['id']
        other['layout']['positions']={other['uses'][0]['id']:{'x':0,'y':0}};other['layout']['groups']=[]
        owner=copy.deepcopy(p['album']['compositions'][0]);owner.update(id=identifier('other-owner'),name='다른 곡',arrangementIDs=[other['id']],selectedArrangementID=other['id'])
        p['arrangements'].append(other);p['album']['compositions'].append(owner);p['album']['children'].append(owner['id'])
        p['album']['layout']['positions'][owner['id']]={'x':900,'y':0}
        path.write_text(json.dumps(p,ensure_ascii=False,indent=2)+'\n');(packager.OUT/'fixture-initial.json').write_bytes(path.read_bytes())
    sources=['Resources/Info.plist','Sources/CirclrCore/ConnectionTargetSearch.swift','Sources/CirclrCore/SectionFlowSelection.swift',
             'Sources/CirclrApp/PortConnectionsEditor.swift','Sources/CirclrApp/PortTargetList.swift','Sources/CirclrApp/InlineCircleEditor.swift','Sources/CirclrApp/AlbumWorkspace.swift','Sources/CirclrApp/TransitionWorkspace.swift']
    (packager.OUT/'source-hashes.json').write_text(json.dumps({name:hashlib.sha256((packager.ROOT/name).read_bytes()).hexdigest() for name in sources},indent=2)+'\n')
