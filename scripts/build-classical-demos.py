#!/usr/bin/env python3
"""Reproduce circlr's classical demos from hash-pinned Mutopia MIDI (no dependencies).
Run normally to regenerate; --check checks committed output without writing it.
No audio recordings are downloaded. MIDI and LilyPond are preserved unmodified.
"""
import argparse, collections, hashlib, json, math, pathlib, struct, urllib.request, uuid
ROOT=pathlib.Path(__file__).resolve().parents[1]
OUT=ROOT/'Resources/Demos/classical'
SPECS=[
 dict(slug='bach-invention-08',lysha='ddc634821a618e9a5e9ffcefbd96005bd02bd1f12573e2fefc4e6e6653d83ebe',title='Invention 8 · 대화하는 궤도',composer='J. S. Bach',work='BWV 779',catalog=61,maintainer='Allen Garvin',stem='BachJS/BWV779/bach-invention-08/bach-invention-08',sha='07238719180171f76283756405ee43a0319226e869283bf29affb9e4c360e6f8',meter=[3,4],root=5,minor=False,tempo=90,cuts=[24,48,72],voices=[4,2],names=['빛의 플럭','유리 건반']),
 dict(slug='bach-invention-07',lysha='87b3a05f14adba1d7113d00b06f7634043e00fb2f660c7b1e698d49c73476248',title='Invention 7 · 밤의 대위',composer='J. S. Bach',work='BWV 778',catalog=73,maintainer='Allen Garvin',stem='BachJS/BWV778/bach-invention-07/bach-invention-07',sha='ee5e02d6a43cd9a45f6c10e3c6b3905190ed42521b1de7487fee8a98c3735eb6',meter=[4,4],root=4,minor=True,tempo=90,cuts=[24,48,72],voices=[7,6],names=['드로바 선율','벨벳 응답']),
 dict(slug='fur-elise',lysha='828a7bd1b42e441fe1b0eb0389ba46f1502dab28bbe488389e635fb446ba7a67',title='Für Elise · 돌아오는 빛',composer='L. V. Beethoven',work='WoO 59',catalog=931,maintainer='Stelios Samelis',stem='BeethovenLv/WoO59/fur_Elise_WoO59/fur_Elise_WoO59',sha='1c12c21c7bbf4cf163896732672648a69d497636059837abd153c71abe50215a',meter=[3,8],root=9,minor=True,tempo=72,cuts=[36,66,96,126],voices=[6,2],names=['벨벳 선율','유리 반주'])]
def uid(s):return str(uuid.uuid5(uuid.NAMESPACE_URL,'https://circlr.app/classical/'+s)).upper()
def encoded(v):return (json.dumps(v,ensure_ascii=False,indent=2,sort_keys=True)+'\n').encode()
def parse_midi(d):
 assert d[:4]==b'MThd' and struct.unpack('>HH',d[8:12])==(1,3)
 ppq=int.from_bytes(d[12:14],'big');p=14;result=[];tempos=[];controls=[]
 def vl(b,i):
  v=0
  while True:
   x=b[i];i+=1;v=(v<<7)|(x&127)
   if x<128:return v,i
 while p<len(d):
  assert d[p:p+4]==b'MTrk';n=int.from_bytes(d[p+4:p+8],'big');b=d[p+8:p+8+n];p+=8+n;i=t=0;r=None;active=collections.defaultdict(list);notes=[]
  while i<len(b):
   dt,i=vl(b,i);t+=dt;s=b[i]
   if s>=128:i+=1;r=s
   else:s=r
   if s==255:
    k=b[i];i+=1;n,i=vl(b,i);v=b[i:i+n];i+=n
    if k==81:tempos.append((t,int.from_bytes(v,'big')))
   elif s in (240,247):n,i=vl(b,i);i+=n
   else:
    n=1 if s>>4 in (12,13) else 2;v=b[i:i+n];i+=n;key=(s&15,v[0])
    if s>>4==9 and v[1]>0:active[key].append((t,v[1]))
    elif s>>4==8 or (s>>4==9 and v[1]==0):
     assert active[key],('unmatched note off',key,t)
     start,vel=active[key].pop(0);notes.append(dict(beat=start/ppq,length=(t-start)/ppq,pitch=v[0],velocity=vel))
    elif s>>4 in (11,14):controls.append((t,s,list(v)))
  assert not any(active.values()),'unclosed notes'
  if notes:result.append(sorted(notes,key=lambda x:(x['beat'],x['pitch'],x['length'])))
 assert len(result)==2 and len(set(tempos))==1 and tempos[0][0]==0
 # Sources contain no bend/pedal. Elise CC7 is constant 100 on both voices;
 # track gain below includes that source channel-volume factor.
 assert all(s>>4==11 and (v[0] in (0,32) or v == [7,100]) for t,s,v in controls),controls
 return result,60000000/tempos[0][1]
def layout(positions=None):return dict(grid=True,snap=True,spacing=24,zoom=1,pan=dict(x=100,y=150),groups=[],positions=positions or {})
def context():return {k:dict(source='inherit') for k in ('tempo','meter','scale','rhythm','beatGrid')}
def patch(voice):
 p=dict(engineVersion=3,voice=voice,character=.6,motion=.4,resonance=.12,stereoWidth=.65,filterEnvelope=0,cutoff=7500,attack=.003,decay=1.2,sustain=.16,release=.18,detune=4)
 if voice==4:p.update(cutoff=2400,attack=.002,decay=.23,sustain=.12,release=.1,detune=5,filterEnvelope=1.7)
 if voice==6:p.update(cutoff=10000,decay=2.8,sustain=.08,release=.25,detune=0,motion=.55)
 if voice==7:p.update(cutoff=6500,attack=.007,decay=.25,sustain=.75,release=.07,detune=0)
 return p
def project(spec,parts):
 slug=spec['slug'];ID=lambda x:uid(slug+'/'+x);aid=ID('arrangement');song=ID('song');beats=spec['meter'][0]*4/spec['meter'][1]
 end=max(n['beat']+n['length'] for part in parts for n in part);end=math.ceil(end/beats)*beats
 # Choose nearby bar boundaries only when neither voice sustains across them.
 # This preserves attacks and durations without artificial re-attacks or truncation.
 safe=[i*beats for i in range(1,int(end/beats)) if not any(n['beat']<i*beats<n['beat']+n['length'] for part in parts for n in part)]
 cuts=[]
 for target in spec['cuts']:
  eligible=[b for b in safe if b>(cuts[-1] if cuts else 0)+beats*2 and b<end-beats*2]
  if eligible:cuts.append(min(eligible,key=lambda b:abs(b-target)))
 bounds=[0]+cuts+[end];tracks=[dict(id=ID('track/'+str(j)),name=name,gain=(.52 if j==0 else .43)*(100/127 if slug=='fur-elise' else 1),muted=False,instrument=dict(kind='synthesizer',drums=False,program=0,synth=patch(spec['voices'][j]))) for j,name in enumerate(spec['names'])]
 sections=[];uses=[];colors=[];master=ID('master');signal=dict(layout=layout(),nodes=[dict(id=master,kind='master',name='출력',effect=dict(kind='gain',amount=.72,secondary=.25))],edges=[])
 for j,t in enumerate(tracks):
  src=ID('source/'+str(j));signal['nodes'].append(dict(id=src,kind='source',name=t['name'],trackID=t['id'],effect=dict(kind='gain',amount=1,secondary=.25)));signal['edges'].append(dict(id=ID('signal/'+str(j)),from_=src,to=master,gain=1,sidechain=False));signal['edges'][-1]['from']=signal['edges'][-1].pop('from_')
 names=['주제의 출발','응답과 전개','색채의 전환','주제의 귀환','마지막 잔상'];palette=[(115,185,230),(104,202,175),(183,152,229),(233,171,119),(220,143,167)]
 for k,(a,b) in enumerate(zip(bounds,bounds[1:])):
  sid=ID('section/'+str(k));use=ID('use/'+str(k));name=names[k];lanes=[];nodes=[];edges=[];positions={}
  for j,t in enumerate(tracks):
   lid=ID(f'lane/{k}/{j}');nn=[]
   for q,n in enumerate(parts[j]):
    if a<=n['beat']<b:nn.append(dict(n,id=ID(f'note/{j}/{q}'),beat=n['beat']-a))
   lanes.append(dict(id=lid,trackID=t['id'],notes=nn,audio=[]))
   chain=[]
   for kind,key,ref in [('midi','laneID',lid),('instrument','trackID',t['id']),('output','trackID',t['id'])]:
    nid=f'{kind}:{ref}';chain.append(nid);nodes.append(dict(id=nid,name=t['name']+({'midi':' MIDI','output':' 출력'}.get(kind,'')),content={kind:{key:ref}},gain=1,muted=False,repeatCount=1,startBeat=0,settings=context()));positions[nid]=dict(x=(len(chain)-1)*320,y=j*400)
   for q in range(2):edges.append(dict(id=ID(f'edge/{k}/{j}/{q}'),**{'from':chain[q]},to=chain[q+1],signal='midi' if q==0 else 'audio',gain=1,sidechain=False))
   for nid in chain[1:]:colors.extend([dict(music=dict(arrangementID=aid,useID=use,nodeID=nid)),dict(zip(['red','green','blue'],palette[j]))])
  sections.append(dict(id=sid,name=name,bars=round((b-a)/beats),settings=context(),tempoChanges=[],meterChanges=[],lanes=lanes,graph=dict(nodes=nodes,edges=edges,layout=layout(positions))))
  uses.append(dict(id=use,sectionID=sid,name=name,repeatCount=1,gain=1,isEnd=k==len(bounds)-2,settings=context(),effects=[],addedLanes=[],excludedLaneIDs=[],laneOverrides={}))
  colors.extend([dict(section=dict(arrangementID=aid,useID=use)),dict(zip(['red','green','blue'],palette[k]))])
 edges=[dict(id=ID('arr-edge/'+str(k)),**{'from':uses[k]['id']},to=uses[k+1]['id'],transition=dict(anchor='sourceBars',length=0,mode='within',effect=dict(kind='gain',amount=1,secondary=.25))) for k in range(len(uses)-1)]
 arr=dict(id=aid,name='원전의 전자 편곡',uses=uses,edges=edges,startID=uses[0]['id'],chosenEdges={},layout=layout({u['id']:dict(x=k*1800,y=0) for k,u in enumerate(uses)}))
 p=dict(schemaVersion=2,id=ID('project'),name=spec['title'],musicRevision=0,activeArrangementID=aid,arrangements=[arr],sections=sections,tracks=tracks,signal=signal,assets=[],takes=[],patterns=[],circleColors=colors,**{'global':dict(tempo=spec['tempo'],meter=dict(zip(['numerator','denominator'],spec['meter'])),scale=dict(root=spec['root'],name='minor' if spec['minor'] else 'major',intervals=[0,2,3,5,7,8,10] if spec['minor'] else [0,2,4,5,7,9,11]),beatGrid=dict(subdivisions=4,swing=0,accents=[]),rhythm={})})
 p['album']=dict(id=ID('album'),children=[song],compositions=[dict(id=song,name=spec['title'],kind='song',children=[],arrangementIDs=[aid],selectedArrangementID=aid,repeatCount=1,layout=layout(),settings=context())],layout=layout({song:dict(x=0,y=0)}))
 # Absolute reconstruction must preserve every note and voice exactly.
 for j in range(2):
  rebuilt=[dict((key,(n[key]+a if key=='beat' else n[key])) for key in ('beat','length','pitch','velocity')) for a,section in zip(bounds,sections) for n in section['lanes'][j]['notes']]
  assert rebuilt==parts[j],('note loss or timing change',slug,j)
 return p,dict(noteCounts=[len(x) for x in parts],sectionQuarterBeatBoundaries=bounds,sourceLastNoteBeat=max(n['beat']+n['length'] for part in parts for n in part),projectEndBeat=end,notesPreservedExactly=True,crossBoundaryNotes=0,externalAssets=0)
def main():
 check=argparse.ArgumentParser();check.add_argument('--check',action='store_true');args=check.parse_args()
 for s in SPECS:
  folder=OUT/s['slug'];data={}
  for ext in ('mid','ly'):
   path=folder/('source.'+ext)
   payload=path.read_bytes() if path.exists() else urllib.request.urlopen('https://www.mutopiaproject.org/ftp/'+s['stem']+'.'+ext).read()
   data[path]=payload
  assert hashlib.sha256(data[folder/'source.mid']).hexdigest()==s['sha']
  assert hashlib.sha256(data[folder/'source.ly']).hexdigest()==s['lysha']
  assert b'Public Domain' in data[folder/'source.ly']
  parts,tempo=parse_midi(data[folder/'source.mid']);assert abs(tempo-s['tempo'])<.001
  p,audit=project(s,parts);data[folder/(s['slug']+'.circlr')/'manifest.json']=encoded(p)
  audit.update(title=s['title'],composer=s['composer'],work=s['work'],maintainer=s['maintainer'],sourcePage=f"https://www.mutopiaproject.org/cgibin/piece-info.cgi?id={s['catalog']}",license='Public Domain',licenseURL='https://www.mutopiaproject.org/legal.html',sourceFiles={path.name:dict(url='https://www.mutopiaproject.org/ftp/'+s['stem']+path.suffix,sha256=hashlib.sha256(content).hexdigest()) for path,content in data.items() if path.suffix in ('.ly','.mid')})
  data[folder/'provenance.json']=encoded(audit)
  for path,payload in data.items():
   if args.check:assert path.read_bytes()==payload,('stale generated file',path)
   else:path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(payload)
  print(s['slug'],audit['noteCounts'],audit['sectionQuarterBeatBoundaries'],'PASS')
if __name__=='__main__':main()
