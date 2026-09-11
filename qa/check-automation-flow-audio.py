#!/usr/bin/env python3
"""Compare authored native reference and automated bounce samples (24-bit WAV)."""
import argparse,json,math,wave
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];out=ROOT/'qa/generated/automation-flow'
def samples(name):
 with wave.open(str(out/name),'rb') as w:
  assert (w.getnchannels(),w.getsampwidth(),w.getframerate())==(2,3,48000)
  raw=w.readframes(w.getnframes())
 return raw
reference=samples('reference.wav');automated=samples('automated.wav');assert len(reference)==len(automated)==34*48000*6
windows=[];max_error=0.;tested=0
for start,end in [(0.5,3.5),(8.5,11.5),(16.5,19.5),(24.5,27.5)]:
 rsum=asum=0.
 for frame in range(int(start*48000),int(end*48000)):
  gain=10**(-6/20)+(1-10**(-6/20))*frame/(32*48000)
  for channel in range(2):
   i=frame*6+channel*3
   r=int.from_bytes(reference[i:i+3],'little',signed=True)/(2**23)
   a=int.from_bytes(automated[i:i+3],'little',signed=True)/(2**23)
   rsum+=r*r;asum+=a*a;max_error=max(max_error,abs(a-r*gain));tested+=1
 assert rsum>0
 windows.append({'seconds':[start,end],'rmsRatio':math.sqrt(asum/rsum)})
assert all(a['rmsRatio']<b['rmsRatio'] for a,b in zip(windows,windows[1:]))
assert max_error<2e-6,max_error
report={'frames':34*48000,'testedSamples':tested,'maximumAbsoluteError':max_error,'windows':windows}
parser=argparse.ArgumentParser();parser.add_argument('--output',type=Path);args=parser.parse_args()
if args.output:
 with args.output.open('x') as f:f.write(json.dumps(report,indent=2)+'\n')
print(json.dumps(report))
