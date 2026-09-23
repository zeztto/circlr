#!/usr/bin/env python3
"""Decode an MP4 audio track with macOS afconvert and report measured PCM levels."""

import argparse
import array
import hashlib
import json
import math
from pathlib import Path
import subprocess
import tempfile
import wave


def levels(samples):
    if not samples:
        return {"peak": 0.0, "rms": 0.0}
    return {
        "peak": max(abs(value) for value in samples) / 32768,
        "rms": math.sqrt(sum(value * value for value in samples) / len(samples)) / 32768,
    }


def inspect(movie):
    with tempfile.TemporaryDirectory(prefix="circlr-movie-audio-") as directory:
        wav = Path(directory) / "decoded.wav"
        subprocess.run(["/usr/bin/afconvert", str(movie), "-o", str(wav),
                        "-f", "WAVE", "-d", "LEI16@48000"], check=True)
        with wave.open(str(wav), "rb") as reader:
            channels, rate, frames, width = (reader.getnchannels(), reader.getframerate(),
                                             reader.getnframes(), reader.getsampwidth())
            if channels != 2 or rate != 48_000 or width != 2 or frames <= 0:
                raise ValueError("expected nonempty 48 kHz stereo PCM16")
            samples = array.array("h")
            samples.frombytes(reader.readframes(frames))
            if len(samples) != frames * channels:
                raise ValueError("decoded PCM frame count mismatch")
    windows = []
    for start in (0, frames // 2, frames * 9 // 10):
        count = min(rate, frames - start)
        windows.append({"atSeconds": round(start / rate, 3),
                        **levels(samples[start * channels:(start + count) * channels])})
    return {"schema": "circlr-movie-audio-qa-v1",
            "movieSHA256": hashlib.sha256(movie.read_bytes()).hexdigest(),
            "channels": channels, "sampleRate": rate, "frames": frames,
            "durationSeconds": frames / rate, **levels(samples), "windows": windows}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("movie", type=Path)
    args = parser.parse_args()
    print(json.dumps(inspect(args.movie), ensure_ascii=False, indent=2))
