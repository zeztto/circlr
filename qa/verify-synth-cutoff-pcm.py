#!/usr/bin/env python3
"""Offline C DSP regression against immutable 4ad38a0; no DAW or device execution.

Run explicitly: python3 qa/verify-synth-cutoff-pcm.py --run final
Compiles old/current C in a temporary directory and saves exclusive JSON evidence.
"""
import argparse
import cmath
import ctypes as C
import hashlib
import json
import math
from pathlib import Path
import re
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[1]
RATE=48000; OFF=96000; TOTAL=144000
FILES=['Sources/CirclrRealtime/synth.c','Sources/CirclrRealtime/include/CirclrSynth.h']
sha=lambda value:hashlib.sha256(value).hexdigest()


def command(args):
    return subprocess.check_output(args,cwd=ROOT,stderr=subprocess.STDOUT)


def library(directory,sources):
    directory.mkdir()
    for path,data in sources.items():(directory/Path(path).name).write_bytes(data)
    command(['clang','-std=c11','-O2','-dynamiclib','-I',str(directory),str(directory/'synth.c'),'-o',str(directory/'synth.dylib')])
    lib=C.CDLL(str(directory/'synth.dylib'))
    for name,count in [('circlr_synth_create',7),('circlr_synth_create_v2',10),('circlr_synth_create_v3',12)]:
        fn=getattr(lib,name);fn.argtypes=[C.c_int]+[C.c_double]*(count-1);fn.restype=C.c_void_p
    lib.circlr_synth_note.argtypes=[C.c_void_p,C.c_int,C.c_int,C.c_int]
    lib.circlr_synth_destroy.argtypes=[C.c_void_p]
    lib.circlr_synth_render.argtypes=[C.c_void_p,C.POINTER(C.c_float),C.POINTER(C.c_float),C.c_uint32]
    if hasattr(lib,'circlr_synth_render_cutoff'):
        lib.circlr_synth_render_cutoff.argtypes=[C.c_void_p,C.POINTER(C.c_float),C.POINTER(C.c_float),C.POINTER(C.c_double),C.c_uint32]
    return lib


def render(lib,engine,block,curve=None,new_api=False):
    args=[0,400,.005,.15,.75,.15,0]
    if engine>=2:args += [.1,.3,0]
    if engine==3:args += [.5,0]
    name='circlr_synth_create'+('' if engine==1 else '_v'+str(engine))
    synth=getattr(lib,name)(*args);assert synth
    left=(C.c_float*TOTAL)();right=(C.c_float*TOTAL)()
    try:
        lib.circlr_synth_note(synth,60,100,1)
        offset=0
        while offset<TOTAL:
            if offset==OFF:lib.circlr_synth_note(synth,60,0,0)
            boundary=OFF if offset<OFF else TOTAL
            frames=min(block,boundary-offset)
            l=C.cast(C.byref(left,offset*C.sizeof(C.c_float)),C.POINTER(C.c_float))
            r=C.cast(C.byref(right,offset*C.sizeof(C.c_float)),C.POINTER(C.c_float))
            if new_api:
                values=(C.c_double*frames)(*[curve(i/RATE) for i in range(offset,offset+frames)]) if curve else None
                lib.circlr_synth_render_cutoff(synth,l,r,values,frames)
            else:lib.circlr_synth_render(synth,l,r,frames)
            offset+=frames
    finally:lib.circlr_synth_destroy(synth)
    assert all(math.isfinite(x) for x in left) and all(math.isfinite(x) for x in right)
    return bytes(left)+bytes(right),list(left),list(right)


def high_band_fraction(samples,start):
    n=8192;segment=samples[int(start*RATE):int(start*RATE)+n];assert len(segment)==n
    values=[complex(x*(.5-.5*math.cos(2*math.pi*i/(n-1)))) for i,x in enumerate(segment)]
    j=0
    for i in range(1,n):
        bit=n>>1
        while j&bit:j^=bit;bit>>=1
        j^=bit
        if i<j:values[i],values[j]=values[j],values[i]
    size=2
    while size<=n:
        half=size//2;root=cmath.exp(-2j*math.pi/size)
        for begin in range(0,n,size):
            phase=1
            for k in range(half):
                a=values[begin+k];b=values[begin+k+half]*phase
                values[begin+k]=a+b;values[begin+k+half]=a-b;phase*=root
        size*=2
    powers=[abs(z)**2 for z in values[1:n//2]];total=sum(powers);assert total>0
    high=sum(power for index,power in enumerate(powers,1) if index*RATE/n>=2000)
    return high/total


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--run',required=True);args=parser.parse_args()
    assert re.fullmatch('[a-z0-9-]{1,40}',args.run)
    out=ROOT/'qa/generated/synth-cutoff'/args.run;assert not out.exists();out.mkdir(parents=True)
    commit=command(['git','rev-parse','4ad38a0^{commit}']).decode().strip()
    old={path:command(['git','show',commit+':'+path]) for path in FILES}
    current={path:(ROOT/path).read_bytes() for path in FILES}
    result=dict(baselineCommit=commit,sourceSHA256={k:sha(v) for k,v in current.items()},
        baselineSHA256={k:sha(v) for k,v in old.items()},sampleRate=RATE,frames=TOTAL,
        scope='CPU-only C synth DSP; no HAL, AudioUnit, Swift build, app launch, or audible-quality claim',engines={})
    sweep=lambda t:400 if t<.5 else 400+(6400-400)*min(1,(t-.5))
    with tempfile.TemporaryDirectory(prefix='circlr-cutoff-qa-') as temp:
        oldlib=library(Path(temp)/'old',old);newlib=library(Path(temp)/'current',current)
        for engine in [1,2,3]:
            legacy=render(oldlib,engine,257);fixed=render(newlib,engine,257)
            null=render(newlib,engine,257,new_api=True)
            constant=render(newlib,engine,257,lambda _:400,True)
            assert legacy[0]==fixed[0]==null[0]==constant[0], f'engine{engine}: fixed/NULL/constant legacy drift'
            dynamic=render(newlib,engine,257,sweep,True)
            for block in [64,1024]:
                assert render(newlib,engine,block,sweep,True)[0]==dynamic[0], f'engine{engine}: block {block} drift'
            low=high_band_fraction(dynamic[1],.25);high=high_band_fraction(dynamic[1],1.7)
            assert high>low*2 and high>0, f'engine{engine}: normalized high-band response missing'
            peak=max(abs(x) for x in dynamic[1]);tail=max(abs(x) for x in dynamic[1][-4800:])
            assert peak>1e-5 and tail<1e-5, f'engine{engine}: note-off tail not settled'
            result['engines'][str(engine)]=dict(legacyFloatByteExact=True,constant400ByteExact=True,
                nullByteExact=True,blockSizesByteExact=[64,257,1024],fixedPCMHash=sha(fixed[0]),
                sweepPCMHash=sha(dynamic[0]),lowHighBandFraction=low,openHighBandFraction=high,
                normalizedGrowth=high/low if low else None,peak=peak,noteOffTailPeak=tail)
    assert all((ROOT/path).read_bytes()==data for path,data in current.items()), 'Source changed during audit'
    result['status']='PASS'
    with (out/'result.json').open('x') as handle:json.dump(result,handle,indent=2);handle.write('\n')
    print(json.dumps(result))


if __name__=='__main__':main()
