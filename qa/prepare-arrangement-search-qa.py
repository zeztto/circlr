#!/usr/bin/env python3
"""Create build 63 and an authored-only album with 65 owned alternatives plus another song."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import uuid

spec=importlib.util.spec_from_file_location('packager',Path(__file__).with_name('prepare-automation-workspace-qa.py'))
packager=importlib.util.module_from_spec(spec);spec.loader.exec_module(packager)
packager.NAME='arrangement-search';packager.BUILD='63'
packager.OUT=packager.ROOT/'qa/generated/arrangement-search';packager.APP=packager.OUT/'써클러 통합 검증.app'
packager.FIXTURE=packager.SOURCE.with_name('arrangement-search.circlr')


def identifier(name):return str(uuid.uuid5(uuid.NAMESPACE_URL,'circlr-integration-qa/arrangement-search/'+name)).upper()


def alternative(base,index,name):
    result=copy.deepcopy(base);result['id']=identifier('arrangement-'+str(index));result['name']=name
    uses={u['id']:identifier(str(index)+'/use/'+u['id']) for u in result['uses']}
    edges={e['id']:identifier(str(index)+'/edge/'+e['id']) for e in result['edges']}
    for use in result['uses']:use['id']=uses[use['id']]
    for edge in result['edges']:
        edge.update(id=edges[edge['id']],**{'from':uses[edge['from']],'to':uses[edge['to']]})
    result['chosenEdges']={uses[k]:edges[v] for k,v in result['chosenEdges'].items()}
    if result.get('startID'):result['startID']=uses[result['startID']]
    result['layout']['positions']={uses.get(k,k):v for k,v in result['layout']['positions'].items()}
    for group in result['layout']['groups']:
        group['id']=identifier(str(index)+'/group/'+group['id']);group['members']=[uses[x] for x in group['members']]
    return result


if __name__=='__main__':
    packager.main()
    if '--candidate' not in sys.argv:
        path=packager.FIXTURE/'manifest.json';p=json.loads(path.read_text());base=p['arrangements'][0]
        base['name']='메인 편곡';owner=p['album']['compositions'][0]
        owner['name']='f0r h3r · 북유럽의 차가운 밤과 도시의 불빛을 연결하는 곡'
        for index in range(2,66):
            name='도시의 밤' if index in (2,3) else '편곡 '+str(index)
            if index==65:name='도시의 밤 · 북유럽의 차가운 신스와 일본 시티팝의 잔향을 길게 이어가는 마지막 편곡 · Northern city reprise'
            value=alternative(base,index,name)
            if index==4:
                value['name']='빈 편곡';value['uses']=[];value['edges']=[];value['chosenEdges']={};value.pop('startID',None);value['layout']['positions']={};value['layout']['groups']=[]
            p['arrangements'].append(value);owner['arrangementIDs'].append(value['id'])
        owner['selectedArrangementID']=owner['arrangementIDs'][-1];p['activeArrangementID']=owner['selectedArrangementID']
        other=copy.deepcopy(owner);other.update(id=identifier('other-owner'),name='다른 곡 · 편곡 범위 검증',arrangementIDs=[],children=[])
        for index,name in [(66,'도시의 밤'),(67,'별도 곡의 대안')]:
            value=alternative(base,index,name);p['arrangements'].append(value);other['arrangementIDs'].append(value['id'])
        other['selectedArrangementID']=other['arrangementIDs'][0]
        p['album']['compositions'].append(other);p['album']['children'].append(other['id']);p['album']['layout']['positions'][other['id']]={'x':700,'y':0}
        path.write_text(json.dumps(p,ensure_ascii=False,indent=2)+'\n');(packager.OUT/'fixture-initial.json').write_bytes(path.read_bytes())
    sources=['Resources/Info.plist','Sources/CirclrCore/ArrangementSelection.swift','Sources/CirclrApp/ArrangementPickerView.swift','Sources/CirclrApp/AppStore.swift','Sources/CirclrApp/RootView.swift','Sources/CirclrApp/InlineCircleEditor.swift','Sources/CirclrApp/AlbumWorkspace.swift','Sources/CirclrApp/CirclrApp.swift','Sources/CirclrApp/CanvasCommands.swift','Sources/CirclrApp/StudioNavigationView.swift','Sources/CirclrApp/SoundPickerView.swift','Sources/CirclrApp/MediaLibraryView.swift','Sources/CirclrApp/AlbumCanvas.swift','Sources/CirclrApp/CanvasFileDrop.swift']
    (packager.OUT/'source-hashes.json').write_text(json.dumps({name:hashlib.sha256((packager.ROOT/name).read_bytes()).hexdigest() for name in sources},indent=2)+'\n')
