#!/usr/bin/env python3
"""Bounded silent real-worker playback on one explicitly selected output device.

Run only with a trusted QA helper binary. This never changes the system default.
"""
import argparse
import hashlib
import json
from pathlib import Path
import runpy


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--worker-binary', type=Path, required=True)
    parser.add_argument('--device-uid', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    source = Path(__file__).with_name('diagnose-default-output.py')
    probe = runpy.run_path(str(source))['worker_playback']
    result = probe(args.worker_binary.resolve(), args.device_uid)
    # Device UIDs can contain hardware serials. The report keeps a digest only.
    for event in result['events']:
        if 'outputDevice' in event:
            descriptor = event['outputDevice']['descriptor']
            descriptor['uidSHA256'] = hashlib.sha256(descriptor.pop('uid').encode()).hexdigest()
    report = {
        'schema': 'circlr-worker-explicit-output-qa-v1',
        'sourceSHA256': hashlib.sha256(source.read_bytes()).hexdigest(),
        'workerSHA256': hashlib.sha256(args.worker_binary.read_bytes()).hexdigest(),
        'selectedUIDSHA256': hashlib.sha256(args.device_uid.encode()).hexdigest(),
        'result': result,
    }
    encoded = json.dumps(report, ensure_ascii=False, indent=2) + '\n'
    with args.output.open('x', encoding='utf-8') as handle:
        handle.write(encoded)
    print(json.dumps({'success': result['success'], 'stages': len(result['events'])}))


if __name__ == '__main__':
    main()
