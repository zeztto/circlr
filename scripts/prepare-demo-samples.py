#!/usr/bin/env python3
"""Fetch a pinned CC0 bank and prepare only the six sounds used by f0r h3r.

No Splice files, credentials or purchases are involved. Standard Python + macOS tar.
"""
import argparse
import hashlib
import io
import json
import math
from pathlib import Path
import subprocess
import tempfile
import urllib.request
import wave

URL = 'https://freepats.zenvoid.org/Percussion/SynthesizerPercussion/SynthesizerPercussion-SFZ-20220718.7z'
PAGE = 'https://freepats.zenvoid.org/Percussion/electric-percussion.html'
ARCHIVE_SHA = 'dbb2e5bb8268022fffa6dcc3d11a93368316038bf3ae81a965c58e9d490ed23b'
MANIFEST_SHA = '11275cbfd9d933bb293dc266faf373ea65efa918ca2f6136c2f69ce88e5b804b'
BANK = 'SynthesizerPercussion-SFZ-20220718'
SOUNDS = [('kick', 'Kick04.wav', .70), ('snare', 'Snare14.wav', .80),
          ('hat', 'ClosedHiHat01-01.wav', .28), ('shaker', 'ShakerLong01.wav', .22),
          ('tom', 'HighTom02-01.wav', .70), ('transition', 'Cymbal01-01.wav', .50)]


def sha(data):
    return hashlib.sha256(data).hexdigest()


def require(condition, message):
    if not condition:
        raise ValueError(message)


def member(archive, name):
    # Read only known members to stdout, never extract archive paths onto disk.
    return subprocess.check_output(['/usr/bin/tar', '-xOf', str(archive), BANK + '/' + name])


def prepare(data, peak):
    with wave.open(io.BytesIO(data)) as source:
        require((source.getnchannels(), source.getsampwidth(), source.getframerate()) == (1, 3, 48000), 'Unexpected source WAV format')
        raw = source.readframes(source.getnframes())
    values = [int.from_bytes(raw[i:i+3], 'little', signed=True) for i in range(0, len(raw), 3)]
    # Remove DC/subsonic offset before peak trim; a short zero-input tail lets the filter settle.
    coefficient = math.exp(-2 * math.pi * 20 / 48000)
    previous_input = previous_output = 0.
    filtered = []
    for value in values + [0] * 4800:
        previous_output = coefficient * (previous_output + value - previous_input)
        previous_input = value; filtered.append(previous_output)
    values = filtered
    maximum = max(map(abs, values)); require(maximum > 0, 'Silent source sample')
    gain = peak * 8388607 / maximum
    output = b''.join(round(v * gain).to_bytes(3, 'little', signed=True) for v in values)
    buffer = io.BytesIO()
    with wave.open(buffer, 'wb') as target:
        target.setparams((1, 3, 48000, 0, 'NONE', 'not compressed')); target.writeframes(output)
    return buffer.getvalue(), len(values) / 48000, gain


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive', type=Path, help='Reuse a downloaded archive; SHA-256 is still required')
    parser.add_argument('--output', type=Path, default=Path(__file__).resolve().parents[1] / 'music/f0r-h3r/samples/freepats')
    args = parser.parse_args(); output = args.output.resolve()
    if output.exists():
        require(sha((output / 'manifest.json').read_bytes()) == MANIFEST_SHA, 'Existing sample manifest changed; use a new output folder')
        manifest = json.loads((output / 'manifest.json').read_text())
        require(manifest['archiveSHA256'] == ARCHIVE_SHA, 'Unexpected source archive')
        missing = []
        for item in manifest['files']:
            sample = output / item['file']
            if sample.exists():
                require(sha(sample.read_bytes()) == item['sha256'], 'Existing sample was edited; use a new output folder')
            else:
                missing.append(sample)
        if not missing:
            print('검증 완료, 기존 샘플 보존:', output); return
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.cc0-samples-', dir=output.parent) as temporary:
        work = Path(temporary); archive = work / 'bank.7z'
        if args.archive:
            data = args.archive.read_bytes()
        else:
            with urllib.request.urlopen(URL, timeout=45) as response:
                data = response.read(8_000_001)
        require(len(data) <= 8_000_000 and sha(data) == ARCHIVE_SHA, 'Archive hash/size mismatch; no samples installed')
        archive.write_bytes(data); stage = work / 'samples'; stage.mkdir()
        for name in ['LICENSE', 'readme.txt']:
            (stage / name).write_bytes(member(archive, name))
        manifest = {'name': 'FreePats synthesizer percussion', 'version': '2022-07-18',
                    'creator': 'Roberto', 'license': 'CC0-1.0',
                    'licenseURL': 'https://creativecommons.org/publicdomain/zero/1.0/',
                    'sourceURL': PAGE, 'archiveURL': URL, 'archiveSHA256': ARCHIVE_SHA,
                    'files': []}
        for role, source, peak in SOUNDS:
            original = member(archive, 'samples/' + source)
            audio, duration, gain = prepare(original, peak)
            name = role + '.wav'; (stage / name).write_bytes(audio)
            manifest['files'].append({'role': role, 'file': name, 'sourceFile': source,
                                      'sourceSHA256': sha(original), 'sha256': sha(audio),
                                      'duration': duration, 'sampleRate': 48000, 'channels': 1,
                                      'transformation': '20 Hz one-pole DC removal, 100 ms settling tail, linear peak trim', 'gain': gain, 'targetPeak': peak})
        (stage / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
        require(sha((stage / 'manifest.json').read_bytes()) == MANIFEST_SHA, 'Prepared sample manifest differs from the pinned version')
        if output.exists():
            # A fresh Git checkout contains provenance but no WAVs. Fill missing files only.
            for source in stage.iterdir():
                destination = output / source.name
                if destination.exists():
                    require(destination.read_bytes() == source.read_bytes(), 'Existing provenance differs; no files replaced')
            for source in stage.iterdir():
                destination = output / source.name
                if not destination.exists():
                    source.rename(destination)
        else:
            stage.rename(output)
    print('CC0 샘플 6개 준비 완료:', output)


if __name__ == '__main__':
    main()
