#!/usr/bin/env python3
"""Read saved build88 host evidence only; never launch an app or output device."""
import hashlib,json,math
from pathlib import Path
import wave
P=Path(__file__).resolve().parent/'generated/output-preparation-build88/host'
def load(n):return json.loads((P/n).read_text())
all_json={f.name:json.loads(f.read_text()) for f in P.glob('*.json')}
obs=load('play-observation.json');samples=obs['snapshots'];assert len(samples)==100
assert [s['elapsed'] for s in samples]==sorted(s['elapsed'] for s in samples)
assert all(not s['state']['output']['transport']['didStart'] for s in samples)
first=samples[-1]['state']; second=load('after-space.json');third=load('cancelled.json')
expected=[(s,ph) for s in ['cafWrite','helperHello','fileValidation','engineCreation'] for ph in ['entered','completed']]+[('mixerAcquisition','entered')]
for state,attempt,request in [(first,1,'timedOut'),(second,2,'timedOut'),(third,3,'cancelled')]:
 o=state['output'];assert o['attempts']==attempt and o['request']==request and o['phase']=='idle'
 assert not o['transport']['didStart'] and o['transport']['seconds']==0
 assert state['revision']==0 and state['dirty'] is False
 es=o['trace']['events'];assert [(e['stage'],e['phase']) for e in es]==expected
 assert o['trace']['sessionID']==o['attemptID']
 values=[e['elapsedSeconds'] for e in es];assert all(math.isfinite(v) and v>=0 for v in values) and values==sorted(values)
assert len({s['output']['attemptID'] for s in [first,second,third]})==3
report=load('pcm-verified.json');raw=(P/'silence.wav').read_bytes()
with wave.open(str(P/'silence.wav'),'rb') as w:
 assert (w.getnframes(),w.getframerate(),w.getnchannels(),w.getsampwidth())==(96000,48000,2,3)
 pcm=w.readframes(96000);assert not any(pcm)
 assert hashlib.sha256(pcm).hexdigest()==report['sha256']
assert report['allZero']
job=load('export-completed.json')['job'];assert job['state']=='completed' and job['renderedSeconds']==2 and job['tail']['effectiveSeconds']==0
assert '믹서 준비 중 · 6초' in (P/'play.ax.txt').read_text() and 'Space로 취소' in (P/'play.ax.txt').read_text()
assert '이전 출력 정리가 끝났습니다' in (P/'cancelled.ax.txt').read_text()
first_timeout=next(s['elapsed'] for s in samples if s['state']['output']['request']=='timedOut')
print(json.dumps(dict(status='passed',scope='saved host evidence and silent PCM only',snapshots=100,firstTimeoutObservedSeconds=first_timeout,hostTimeouts=2,hostCancellations=1,hostStarted=False,pcmFrames=96000,lastStage='mixerAcquisition entered'),ensure_ascii=False))
