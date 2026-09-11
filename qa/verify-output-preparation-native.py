#!/usr/bin/env python3
"""Explicit two-case silent native diagnostic. Never a product automatic retry policy."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import select
import struct
import subprocess
import tempfile
import time
import uuid

STAGES = ['fileValidation', 'engineCreation', 'mixerAcquisition', 'routing', 'scheduling', 'engineStart', 'playerPlay']


def save(path, value):
    with path.open('x', encoding='utf-8') as handle:
        json.dump(value, handle, ensure_ascii=False, indent=2, allow_nan=False)
        handle.write('\n')
        handle.flush()
        os.fsync(handle.fileno())


def audio(path):
    # Actual CAF container: signed packed little-endian 16-bit stereo LPCM.
    pcm = bytes(48000 * 2 * 2)
    desc = struct.pack('>d4sIIIII', 48000.0, b'lpcm', 2, 4, 1, 2, 16)
    data = b'caff\x00\x01\x00\x00' + b'desc' + struct.pack('>q', len(desc)) + desc
    data += b'data' + struct.pack('>q', len(pcm) + 4) + bytes(4) + pcm
    with path.open('xb') as handle:
        handle.write(data)
    path.chmod(0o600)
    actual = path.read_bytes()
    assert actual == data and len(actual[68:]) == 192000 and not any(actual[68:])
    return dict(sha256=hashlib.sha256(actual).hexdigest(), bytes=len(actual), container='CAF', frames=48000,
                channels=2, sampleRate=48000, sampleBits=16, pcmBytes=192000, allZero=True)


def attempt(binary, number):
    result = dict(case='first-attempt' if number == 1 else 'explicit-retry', session=str(uuid.uuid4()),
                  events=[], started=False, clockObserved=False, naturallyFinished=False, stdoutEOF=False,
                  status='partial', lastStage=None, lastEvent=None)
    process = None
    origin = time.monotonic()
    try:
        with tempfile.TemporaryDirectory(prefix='circlr-preparation-native-') as temporary:
            result['audio'] = audio(Path(temporary) / 'audio.caf')
            try:
                process = subprocess.Popen([str(binary), '--session', result['session'], '--directory', temporary],
                                           stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, bufsize=0)
                result['pid'] = process.pid
                pending = b''
                sequence = 0
                command_sequence = 0
                trace_index = 0
                trace_time = 0.0
                clock_time = -1.0
                run = str(uuid.uuid4())
                result['run'] = run
                deadline = origin + 10
                hello = prepared = False

                def send(payload):
                    nonlocal command_sequence
                    command_sequence += 1
                    packet = dict(version=1, session=result['session'], sequence=command_sequence, payload=payload)
                    process.stdin.write(json.dumps(packet).encode() + b'\n')

                while True:
                    remaining = deadline - time.monotonic()
                    if remaining <= 0:
                        result['status'] = 'timeout'
                        break
                    if b'\n' not in pending:
                        if not select.select([process.stdout], [], [], remaining)[0]:
                            result['status'] = 'timeout'
                            break
                        chunk = os.read(process.stdout.fileno(), 4096)
                        if not chunk:
                            result['stdoutEOF'] = True
                            result['status'] = 'truncated-wire' if pending else 'eof-before-finished'
                            break
                        pending += chunk
                        if len(pending) > 65536:
                            raise ValueError('bounded-buffer-exceeded')
                        if b'\n' not in pending:
                            if len(pending) > 16384:
                                raise ValueError('bounded-frame-exceeded')
                            continue
                    line, pending = pending.split(b'\n', 1)
                    if not line or len(line) > 16384 or len(result['events']) >= 512:
                        raise ValueError('bounded-events-exceeded')
                    packet = json.loads(line)
                    if packet.get('version') != 1 or packet.get('session', '').lower() != result['session'].lower():
                        raise ValueError('wrong-version-or-session')
                    sequence += 1
                    if type(packet.get('sequence')) is not int or packet['sequence'] != sequence:
                        raise ValueError('wrong-sequence')
                    payload = packet.get('payload')
                    if not isinstance(payload, dict) or len(payload) != 1:
                        raise ValueError('invalid-payload')
                    kind, value = next(iter(payload.items()))
                    if kind not in ['hello', 'prepared', 'trace', 'started', 'clock', 'finished', 'failure', 'stopped'] or not isinstance(value, dict):
                        raise ValueError('invalid-event')
                    if kind in ['started', 'clock', 'finished', 'stopped'] and value.get('run', '').lower() != run.lower():
                        raise ValueError('wrong-run')
                    if kind == 'trace':
                        elapsed = value.get('elapsedSeconds')
                        if (trace_index >= 14 or value.get('stage') != STAGES[trace_index // 2]
                                or value.get('phase') != ['entered', 'completed'][trace_index % 2]
                                or type(elapsed) not in (int, float) or not math.isfinite(elapsed)
                                or not trace_time <= elapsed <= 14400):
                            raise ValueError('invalid-trace-order-or-time')
                        trace_index += 1
                        trace_time = elapsed
                        result['lastStage'] = dict(stage=value['stage'], phase=value['phase'], elapsedSeconds=elapsed)
                    if kind == 'clock':
                        seconds = value.get('seconds')
                        if type(seconds) not in (int, float) or not math.isfinite(seconds) or not max(0, clock_time) <= seconds <= 14400:
                            raise ValueError('invalid-clock-time')
                        clock_time = seconds
                    # Do not persist arbitrary child strings, including stderr or failure messages.
                    safe = ({'stage': value['stage'], 'phase': value['phase'], 'elapsedSeconds': value['elapsedSeconds']}
                            if kind == 'trace' else {'seconds': value['seconds'], 'run': run} if kind == 'clock'
                            else {'run': run} if kind in ['started', 'finished', 'stopped']
                            else {'messageOmitted': True} if kind == 'failure' else {})
                    result['events'].append(dict(sequence=sequence, observedSeconds=time.monotonic() - origin, event=kind, value=safe))
                    result['lastEvent'] = kind
                    if kind == 'hello':
                        if hello or sequence != 1:
                            raise ValueError('unexpected-hello')
                        hello = True
                        send({'prepare': {'frames': 48000}})
                    elif kind == 'prepared':
                        if not hello or prepared or trace_index != 2:
                            raise ValueError('unexpected-prepared')
                        prepared = True
                        send({'play': {'run': run}})
                    elif kind == 'started':
                        if not prepared or trace_index != 14 or result['started']:
                            raise ValueError('unexpected-started')
                        result['started'] = True
                    elif kind == 'clock':
                        if not result['started']:
                            raise ValueError('clock-before-started')
                        result['clockObserved'] = True
                    elif kind == 'finished':
                        if not result['started']:
                            raise ValueError('finished-before-started')
                        result['naturallyFinished'] = True
                        result['status'] = 'completed' if result['clockObserved'] else 'finished-without-clock'
                        break
                    elif kind in ['failure', 'stopped']:
                        result['status'] = kind
                        break
            finally:
                if process is not None:
                    cleanup = time.monotonic()
                    result['cleanup'] = dict(commandEOFRequested=True, forcedKill=False)
                    process.stdin.close()
                    try:
                        process.wait(timeout=3)
                    except subprocess.TimeoutExpired:
                        result['cleanup']['forcedKill'] = True
                        process.kill()  # Only this Popen-owned child.
                        try:
                            process.wait(timeout=3)
                        except subprocess.TimeoutExpired:
                            result['cleanup']['reapTimedOut'] = True
                    result['cleanup'].update(exitCode=process.poll(), seconds=time.monotonic() - cleanup)
                    process.stdout.close()
        result['temporaryDirectoryRemoved'] = not Path(temporary).exists()
    except KeyboardInterrupt:
        result['status'] = 'interrupted'
    except Exception as error:
        result['status'] = 'error'
        result['errorType'] = type(error).__name__
        # Our validation codes only; never copy child output or OS error strings.
        if isinstance(error, ValueError) and str(error) in ['wrong-version-or-session', 'wrong-sequence', 'invalid-payload',
                'invalid-event', 'wrong-run', 'invalid-trace-order-or-time', 'invalid-clock-time', 'unexpected-hello',
                'unexpected-prepared', 'unexpected-started', 'clock-before-started', 'finished-before-started',
                'bounded-buffer-exceeded', 'bounded-frame-exceeded', 'bounded-events-exceeded']:
            result['errorCode'] = str(error)
    finally:
        result['elapsedSeconds'] = time.monotonic() - origin
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary', required=True, type=Path, help='Explicit final release helper binary')
    parser.add_argument('--out', required=True, type=Path, help='New independent evidence directory; must not exist')
    args = parser.parse_args()
    binary = args.binary.expanduser().resolve(strict=True)
    if not binary.is_file() or not os.access(binary, os.X_OK):
        parser.error('--binary must be an executable file')
    args.out.mkdir(parents=True, exist_ok=False)
    save(args.out / 'invocation.json', dict(binary=str(binary), binarySHA256=hashlib.sha256(binary.read_bytes()).hexdigest(),
         diagnosticCases=['first-attempt', 'explicit-retry'], productAutomaticRetry=False, attemptDeadlineSeconds=10,
         cleanupEOFDeadlineSeconds=3, cleanupKillDeadlineSeconds=3, stderr='discarded'))
    results = []
    try:
        for number in (1, 2):
            item = attempt(binary, number)
            save(args.out / f'attempt-{number}.json', item)
            results.append(item)
            if item['status'] == 'interrupted':
                break
    finally:
        save(args.out / 'summary.json', dict(attempts=len(results),
            distinctSessions=len({r['session'] for r in results}) == 2,
            distinctPIDs=len({r.get('pid') for r in results if r.get('pid')}) == 2,
            identicalAudio=len({r.get('audio', {}).get('sha256') for r in results}) == 1,
            statuses=[r['status'] for r in results], complete=len(results) == 2 and all(r['status'] == 'completed' for r in results)))
    print(json.dumps(dict(out=str(args.out.resolve()), statuses=[r['status'] for r in results])))
    return 0 if len(results) == 2 and all(r['status'] == 'completed' for r in results) else 1


if __name__ == '__main__':
    raise SystemExit(main())
