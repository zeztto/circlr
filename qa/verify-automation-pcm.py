#!/usr/bin/env python3
"""Verify stereo native GUI automation bounces; exact 0.19 fixture contract."""
import json
import math
from pathlib import Path
import wave

OUT = Path(__file__).resolve().parent / 'generated/0.19'


def pcm(name):
    with wave.open(str(OUT / (name + '.wav')), 'rb') as audio:
        assert (audio.getnchannels(), audio.getsampwidth(), audio.getframerate()) == (2, 3, 48000)
        raw = audio.readframes(audio.getnframes())
    return [int.from_bytes(raw[i:i + 3], 'little', signed=True) for i in range(0, len(raw), 3)]


def main():
    target = OUT / 'native-automation-pcm.json'
    assert not target.exists(), 'Preserve previous evidence'
    base, gain, hold, pan, bypass = map(pcm, ['gui-initial', 'gui-gain', 'gui-hold', 'gui-pan', 'gui-pan-bypass'])
    assert len({len(a) for a in (base, gain, hold, pan, bypass)}) == 1
    # Only the right split starts at 0.5 s and owns these automation curves.
    # Its node clock starts at section beat zero, 120 BPM: beat 2 is 1 second.
    assert all(a[:48000] == base[:48000] for a in (gain, hold, pan, bypass))
    errors = dict(gain=0, hold=0, pan=0)
    for i in range(48000, len(base)):
        seconds = (i // 2) / 48000
        g = min(1, .2 + .8 * seconds)
        h = .2 if seconds < 1 else 1
        p = min(1, -1 + 2 * seconds)
        expected = dict(gain=base[i] * g, hold=base[i] * h,
                        pan=gain[i] * math.sqrt(1 + (p if i % 2 else -p)))
        for name, actual in (('gain', gain), ('hold', hold), ('pan', pan)):
            errors[name] = max(errors[name], abs(actual[i] - round(expected[name])))
    assert all(v <= 2 for v in errors.values()), errors
    assert bypass == gain, 'Bypassing pan must preserve the gain-only PCM'
    pan_state = json.loads((OUT / 'gui-pan.json').read_text())
    bypass_state = json.loads((OUT / 'gui-pan-bypass.json').read_text())
    node_id = pan_state['state']['selection']['music']['nodeID']
    def lane(evidence):
        node = next(n for n in evidence['inspection']['graph']['nodes'] if n['id'] == node_id)
        return next(l for l in node['automation'] if l['parameter'] == 'pan')
    a, b = lane(pan_state), lane(bypass_state)
    assert a['enabled'] and not b['enabled'] and a['points'] == b['points']
    result = dict(maxError24BitLSB=errors, beforeSelectedAudioExact=True,
                  panBypassMatchesGainExact=True, bypassPreservesPointIDsAndValues=True,
                  channels=2, rate=48000, frames=len(base) // 2)
    target.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result))


if __name__ == '__main__':
    main()
