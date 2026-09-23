#!/usr/bin/env python3
"""Bounded direct CoreAudio IOProc probe, with no project audio or device-setting change.

Example: python3 qa/diagnose-direct-ioproc.py --device built-in BuiltInSpeakerDevice
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import time


SOURCE = Path(__file__).with_name('direct-ioproc-probe.swift')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', action='append', nargs=2, metavar=('LABEL', 'UID'), required=True)
    parser.add_argument('--timeout', type=float, default=10)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    if not 1 <= args.timeout <= 30:
        parser.error('timeout must be 1–30 seconds')
    if len({label for label, _ in args.device}) != len(args.device):
        parser.error('device labels must be unique')

    with tempfile.TemporaryDirectory(prefix='circlr-direct-io-probe-') as directory:
        binary = Path(directory) / 'direct-ioproc-probe'
        subprocess.run(['xcrun', 'swiftc', str(SOURCE), '-o', str(binary)],
                       check=True, capture_output=True, timeout=90)
        results = []
        for label, uid in args.device:
            started = time.monotonic()
            try:
                process = subprocess.run([str(binary), uid], capture_output=True,
                                         text=True, timeout=args.timeout)
                status = 'completed' if process.returncode == 0 else 'error'
                stderr = process.stderr
                code = process.returncode
            except subprocess.TimeoutExpired as error:
                status = 'timeout'
                stderr = (error.stderr or b'').decode(errors='replace')
                code = None
            results.append({
                'device': label,
                'status': status,
                'exitCode': code,
                'elapsedSeconds': round(time.monotonic() - started, 3),
                'stages': stderr.splitlines(),
            })
    report = {
        'schema': 'circlr-direct-ioproc-probe-v1',
        'sourceSHA256': hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
        'timeoutSeconds': args.timeout,
        'results': results,
    }
    encoded = json.dumps(report, ensure_ascii=False, indent=2) + '\n'
    if args.output:
        with args.output.open('x', encoding='utf-8') as handle:
            handle.write(encoded)
    print(encoded, end='')


if __name__ == '__main__':
    main()
