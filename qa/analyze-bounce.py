"""Compare the actual 24-bit native MCP exports. Requires numpy."""
import argparse
import json
from pathlib import Path
import struct
import numpy as np


def pcm(path):
    data = Path(path).read_bytes()
    assert data[:4] == b'RIFF' and data[8:12] == b'WAVE'
    offset = 12
    audio = None
    while offset + 8 <= len(data):
        name = data[offset:offset + 4]
        size = struct.unpack_from('<I', data, offset + 4)[0]
        chunk = data[offset + 8:offset + 8 + size]
        if name == b'fmt ':
            fmt, channels, rate, _, _, bits = struct.unpack_from('<HHIIHH', chunk)
            assert fmt in (1, 65534) and channels == 2 and rate == 48000 and bits == 24
        if name == b'data':
            raw = np.frombuffer(chunk, dtype=np.uint8).reshape(-1, 3).astype(np.int32)
            audio = raw[:, 0] | (raw[:, 1] << 8) | (raw[:, 2] << 16)
            audio = (audio ^ 0x800000) - 0x800000
        offset += 8 + size + size % 2
    assert audio is not None and audio.size
    return audio


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('directory', type=Path)
    args = parser.parse_args()
    before = pcm(args.directory / '0.9-mcp-before.wav')
    after = pcm(args.directory / '0.9-mcp-bounced.wav')
    assert before.shape == after.shape
    difference = before.astype(np.int64) - after
    maximum = int(np.abs(difference).max())
    result = {'sampleCount': int(before.size), 'seconds': before.size / (48000 * 2),
              'maxDifferenceLSB24': maximum, 'maxDifference': maximum / 8388608,
              'rmsDifference': float(np.sqrt(np.mean((difference / 8388608) ** 2))),
              'passed': maximum <= 4}
    (args.directory / 'bounce-audio-comparison.json').write_text(json.dumps(result, indent=2))
    print(json.dumps(result))
    assert result['passed'], result


if __name__ == '__main__':
    main()
