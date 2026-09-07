"""Targeted real-app contract QA. Restricted to disposable 0.10 QA documents."""
import argparse
import json
from pathlib import Path
import uuid
from native_smoke import SOCKET, ROOT
from server import rpc


def call(method, arguments=None, write=False):
    packet={'id':str(uuid.uuid4()),'method':method,'arguments':arguments or {}}
    if write:
        state=call('snapshot')
        assert state['path'].startswith(str(ROOT / 'qa/generated/0.10-'))
        packet.update(projectID=state['projectID'],expectedRevision=state['revision'])
    reply=rpc(SOCKET,packet)
    assert reply['ok'],reply
    return reply['result']


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('report',type=Path)
    options=parser.parse_args()
    assert not options.report.exists()
    state=call('snapshot')
    assert state['path'].startswith(str(ROOT / 'qa/generated/0.10-'))
    call('focus',{'minimized':True})
    ai=state['activeArrangementID'];uses=state['arrangements'][0]['uses'];ui=uses[3]['id']
    scope={'arrangementID':ai,'useID':ui}
    def inspect():return call('inspect',scope)
    before=inspect()
    node=next(n for n in before['graph']['nodes'] if n.get('bounce'))
    content=node['content']['audio'];lane=next(l for l in before['lanes'] if l['id']==content['laneID'])
    clip=next(c for c in lane['audio'] if c['id']==content['clipID'])
    call('apply',{'operations':[{'kind':'set_clip',**scope,'laneID':lane['id'],'clipID':clip['id'],'duration':clip['duration']*0.75}]},True)
    trimmed=inspect()
    changed=next(c for l in trimmed['lanes'] for c in l['audio'] if c['id']==clip['id'])
    assert abs(changed['duration']-clip['duration']*0.75)<1e-9
    call('undo',write=True)
    assert inspect()['lanes']==before['lanes']
    def section_orbit(s):return next(c['orbit'] for c in s['circles'] if 'section' in c['address'])
    call('apply',{'operations':[{'kind':'reorder_section',**scope,'to':uses[1]['id']}]},True)
    reordered=inspect()
    assert section_orbit(reordered)['anchor']<section_orbit(before)['anchor']
    call('undo',write=True)
    assert section_orbit(inspect())==section_orbit(before)
    source=next(n for n in before['graph']['nodes'] if 'midi' in n['content'])
    call('apply',{'operations':[{'kind':'set_node',**scope,'nodeID':source['id'],'startBeat':8}]},True)
    shifted=inspect()
    circle=next(c for c in shifted['circles'] if c['address'].get('music',{}).get('nodeID')==source['id'])
    assert abs(circle['orbit']['anchor']-8*60/shifted['context']['tempo'])<1e-9
    call('undo',write=True)
    assert inspect()['graph']==before['graph']
    final=call('snapshot')
    assert any(w['minimized'] for w in final['runtime']['windows'])
    call('save',write=True)
    report={'checks':['actual clip trim and exact Undo','section reorder changes actual orbit time and Undo restores it','MIDI start moves to actual seconds and Undo restores graph','all edits ran minimized'],
            'runtime':final['runtime'],'revisionBefore':state['revision'],'revisionAfter':final['revision'],
            'clipBefore':clip,'clipTrimmed':changed,'sectionBefore':section_orbit(before),'sectionMoved':section_orbit(reordered),'sourceShifted':circle}
    options.report.write_text(json.dumps(report,ensure_ascii=False,indent=2))
    print(json.dumps({'checks':report['checks'],'revision':final['revision']},ensure_ascii=False))


if __name__=='__main__':main()
