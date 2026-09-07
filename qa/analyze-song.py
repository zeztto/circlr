"""48 kHz stereo 24-bit WAV QA. NumPy only; no audio device or source modification.
K weighting/gates: ITU-R BS.1770-5 Annex 1 (48 kHz coefficients).
4x windowed-sinc peaks are estimates, not an EBU compliance certification.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import numpy as np

spec = importlib.util.spec_from_file_location('bounce', Path(__file__).with_name('analyze-bounce.py'))
bounce = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bounce)
RATE = 48000


def db(x):
    return float(20*np.log10(max(float(x), 1e-15)))


def k_impulse():
    x = np.zeros(16384); x[0] = 1
    for b, a in [([1.53512485958697, -2.69169618940638, 1.19839281085285], [-1.69065929318241, .73248077421585]), ([1., -2., 1.], [-1.99004745483398, .99007225036621])]:
        y = np.zeros_like(x); x1 = x2 = y1 = y2 = 0.
        for i, value in enumerate(x):
            y[i] = b[0]*value+b[1]*x1+b[2]*x2-a[0]*y1-a[1]*y2
            x2, x1, y2, y1 = x1, value, y1, y[i]
        x = y
    assert np.max(np.abs(x[-100:])) < 1e-20
    return x


def loudness(audio):
    h = k_impulse(); length = 1 << (len(audio)+len(h)-2).bit_length()
    transfer = np.fft.rfft(h, length); energy = np.zeros(len(audio))
    for channel in audio.T:
        y = np.fft.irfft(np.fft.rfft(channel, length)*transfer, length)[:len(audio)]
        energy += y*y
    cumulative = np.r_[0., np.cumsum(energy)]
    starts = np.arange(0, len(audio)-19200+1, 4800)
    blocks = (cumulative[starts+19200]-cumulative[starts])/19200
    levels = -.691+10*np.log10(np.maximum(blocks, 1e-30))
    absolute = blocks[levels > -70]
    if not len(absolute): return None
    gate = -.691+10*np.log10(np.mean(absolute))-10
    selected = blocks[(levels > -70) & (levels > gate)]
    return float(-.691+10*np.log10(np.mean(selected)))


def peak4(audio):
    maximum = np.max(np.abs(audio))
    t = np.arange(-48, 49)
    for phase in [.25, .5, .75]:
        kernel = np.sinc(t-phase)*np.kaiser(97, 8.6); kernel /= kernel.sum()
        for channel in audio.T:
            maximum = max(maximum, np.max(np.abs(np.convolve(channel, kernel, mode='same'))))
    return float(maximum)


def analyze(path):
    audio = bounce.pcm(path).reshape(-1, 2).astype(np.float64)/8388608
    mid = audio.mean(axis=1); side = (audio[:, 0]-audio[:, 1])/2
    result = {'file':path.name, 'sha256':hashlib.sha256(path.read_bytes()).hexdigest(), 'seconds':len(audio)/RATE,
              'sampleRate':RATE, 'bitDepth':24, 'channels':2, 'samplePeakDBFS':db(np.max(np.abs(audio))),
              'rmsDBFS':db(np.sqrt(np.mean(audio*audio))), 'clippedSamples':int(np.count_nonzero(np.abs(audio) >= 1)),
              'dc':audio.mean(axis=0).tolist(), 'stereoCorrelation':float(np.corrcoef(audio.T)[0, 1]),
              'sideToMidDB':db(np.sqrt(np.mean(side*side))/max(1e-15,np.sqrt(np.mean(mid*mid)))),
              'integratedLUFS':loudness(audio), 'estimatedPeak4xDBFS':db(peak4(audio)),
              'meter':'circlr QA v1; BS.1770-5 stereo K weighting, 400ms/100ms gates; 4x 97-tap Kaiser sinc peak estimate',
              'listeningReview':'not performed by model', 'certifiedMeter':False}
    return result


if __name__ == '__main__':
    p = argparse.ArgumentParser();p.add_argument('wav', type=Path);p.add_argument('--output', type=Path);a=p.parse_args()
    tone = np.sin(2*np.pi*997*np.arange(RATE*4)/RATE)*.1
    calibration = loudness(np.column_stack([tone,tone]))
    assert abs(calibration+20) < .06, calibration
    silence_gated = loudness(np.r_[np.column_stack([tone,tone]),np.zeros((RATE*4,2))])
    assert abs(silence_gated-calibration) < .2
    result = analyze(a.wav);result['997HzCalibrationLUFS'] = calibration
    output=a.output or a.wav.with_name('audio-analysis.json')
    output.write_text(json.dumps(result,indent=2,ensure_ascii=False)+'\n')
    print(json.dumps(result,ensure_ascii=False))
