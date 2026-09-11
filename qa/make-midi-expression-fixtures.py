#!/usr/bin/env python3
"""Write deterministic, authored SMF files for isolated MIDI expression UI QA."""
from pathlib import Path
import struct
import sys

OUT = Path(__file__).resolve().parent / "generated/midi-expression"


def vlq(value):
    result = [value & 127]
    while value >> 7:
        value >>= 7
        result.insert(0, (value & 127) | 128)
    return bytes(result)


def track(events):
    data = b"".join(vlq(delta) + bytes(event) for delta, event in events)
    data += b"\x00\xff\x2f\x00"
    return b"MTrk" + struct.pack(">I", len(data)) + data


def file(name, controllers):
    # Controller-only track deliberately precedes the separate note source.
    conductor = track([(0, b"\xff\x51\x03\x07\xa1\x20")] + controllers)
    notes = track([(0, b"\xff\x03\x07Bend QA"),
                   (480, b"\x90\x45\x64"), (960, b"\x80\x45\x00")])
    data = b"MThd" + struct.pack(">IHHH", 6, 1, 2, 480) + conductor + notes
    path = OUT / name
    path.write_bytes(data)
    print(path)


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    file("supported-bend.mid", [(0, b"\xb0\x65\x00"), (0, b"\xb0\x64\x00"),
         (0, b"\xb0\x06\x0c"), (0, b"\xb0\x26\x00"),
         (0, b"\xe0\x00\x40"), (720, b"\xe0\x00\x60"),
         (240, b"\xe0\x00\x40")])
    file("unsupported-tuning.mid", [(0, b"\xb0\x65\x00"), (0, b"\xb0\x64\x01"),
         (0, b"\xb0\x06\x41"), (720, b"\xe0\x00\x60")])
    if "--stress" in sys.argv[1:]:
        controllers = [(0, b"\xb0\x65\x00"), (0, b"\xb0\x64\x00")]
        controllers += [(0, bytes((0xb0, 6 if i % 2 == 0 else 38, (i // 2) % 128)))
                        for i in range(100000)]
        notes = track([(0, b"\x90\x45\x64"), (480, b"\x80\x45\x00")])
        data = b"MThd" + struct.pack(">IHHH", 6, 1, 256, 480) + track(controllers) + notes * 255
        path = OUT / "stress-shared-channel.mid"
        path.write_bytes(data)
        print(path)
