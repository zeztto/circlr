#!/usr/bin/env python3
"""QA-only bounded default-output comparison. Restore before exiting, even on probe timeout.

Never run while another user is actively using output. Requires explicit original UID.
"""
import argparse
import hashlib
import json
from pathlib import Path
import select
import subprocess
import tempfile
import time
import uuid
import wave

CONTROL = Path(__file__).with_name('default-output-control.swift')
PROBE = Path(__file__).with_name('avaudioengine-output-probe.swift')


def command(binary, *args, timeout=5):
    return subprocess.run([str(binary), *args], capture_output=True, text=True,
                          timeout=timeout, check=True)


def current(control):
    result = command(control, 'get')
    device_id, uid = result.stdout.strip().split('\t', 1)
    return {'id': int(device_id), 'uid': uid}


def public_device(device):
    return {'id': device['id'],
            'uidSHA256': hashlib.sha256(device['uid'].encode()).hexdigest()}


def run_probe(binary, timeout):
    started = time.monotonic()
    try:
        result = subprocess.run([str(binary)], capture_output=True, text=True,
                                timeout=timeout)
        return {'status': 'completed' if result.returncode == 0 else 'error',
                'exitCode': result.returncode, 'stages': result.stderr.splitlines(),
                'elapsedSeconds': round(time.monotonic() - started, 3)}
    except subprocess.TimeoutExpired as error:
        return {'status': 'timeout', 'exitCode': None,
                'stages': (error.stderr or b'').decode(errors='replace').splitlines(),
                'elapsedSeconds': round(time.monotonic() - started, 3)}


def worker_playback(binary, selection_uid=None):
    """Play three seconds of zeros through the real bundled worker, then STOP."""
    result = {'status': 'incomplete', 'events': []}
    with tempfile.TemporaryDirectory(prefix='circlr-default-output-worker-') as directory:
        path = Path(directory)
        with wave.open(str(path / 'audio.caf'), 'wb') as audio:
            audio.setnchannels(2); audio.setsampwidth(2); audio.setframerate(48_000)
            audio.writeframes(bytes(48_000 * 3 * 4))
        (path / 'audio.caf').chmod(0o600)
        session = str(uuid.uuid4()).upper()
        child = subprocess.Popen([str(binary), '--session', session, '--directory', str(path)],
                                 stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                 stderr=subprocess.DEVNULL, bufsize=0)
        sequence = 0
        try:
            def next_event(timeout=10):
                if not select.select([child.stdout], [], [], timeout)[0]:
                    raise TimeoutError('worker event timeout')
                line = child.stdout.readline()
                if not line:
                    raise RuntimeError('worker EOF')
                packet = json.loads(line)
                if packet['session'].upper() != session:
                    raise RuntimeError('wrong worker session')
                payload = packet['payload']
                result['events'].append(payload)
                return payload

            def send(payload):
                nonlocal sequence
                sequence += 1
                child.stdin.write(json.dumps({'version': 1, 'session': session,
                                              'sequence': sequence, 'payload': payload}).encode() + b'\n')
                child.stdin.flush()

            hello = next_event(3)
            if not any(key.startswith('hello') for key in hello):
                raise RuntimeError('missing worker hello')
            if selection_uid is None:
                send({'prepare': {'frames': 48_000 * 3}})
            else:
                send({'prepareOutput': {'frames': 48_000 * 3,
                                        'selection': {'deviceUID': {'_0': selection_uid}}}})
            for _ in range(5):
                if 'prepared' in next_event(3):
                    break
            else:
                raise RuntimeError('worker did not prepare')
            run = str(uuid.uuid4()).upper()
            send({'play': {'run': run}})
            for _ in range(25):
                event = next_event(10)
                if 'started' in event:
                    result['status'] = 'started'
                    break
                if 'failure' in event:
                    raise RuntimeError(str(event['failure']))
            if result['status'] == 'started':
                for _ in range(30):
                    event = next_event(3)
                    if 'clock' in event and event['clock']['seconds'] >= 0.08:
                        result['clockObserved'] = True
                        result['progressSeconds'] = event['clock']['seconds']
                        break
                send({'stop': {'run': run}})
                for _ in range(10):
                    if 'stopped' in next_event(3):
                        result['stopped'] = True
                        break
            child.stdin.close()
            result['exitCode'] = child.wait(timeout=3)
        except (TimeoutError, RuntimeError, ValueError, BrokenPipeError) as error:
            result['error'] = str(error)
        finally:
            if child.poll() is None:
                child.kill(); child.wait(timeout=3)
            if not child.stdin.closed:
                child.stdin.close()
            child.stdout.close()
        result['success'] = (result['status'] == 'started' and result.get('clockObserved')
                             and result.get('stopped') and result.get('exitCode') == 0)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--expected-default-uid', required=True)
    parser.add_argument('--temporary-uid', required=True)
    parser.add_argument('--timeout', type=float, default=10)
    parser.add_argument('--worker-binary', type=Path,
                        help='also test silent playback through this real output worker after switching')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    if not 1 <= args.timeout <= 20 or args.expected_default_uid == args.temporary_uid:
        parser.error('invalid timeout or identical device UIDs')

    with tempfile.TemporaryDirectory(prefix='circlr-default-output-qa-') as directory:
        control, probe = (Path(directory) / name for name in ('control', 'probe'))
        for source, target in ((CONTROL, control), (PROBE, probe)):
            subprocess.run(['xcrun', 'swiftc', str(source), '-o', str(target)],
                           check=True, capture_output=True, timeout=90)
        original = current(control)
        if original['uid'] != args.expected_default_uid:
            raise RuntimeError('system default differs from explicit expectation; no change made')
        result = {'schema': 'circlr-default-output-qa-v1',
                  'sourceSHA256': {source.name: hashlib.sha256(source.read_bytes()).hexdigest()
                                   for source in (CONTROL, PROBE)},
                  'originalDefault': public_device(original),
                  'temporaryUIDSHA256': hashlib.sha256(args.temporary_uid.encode()).hexdigest(),
                  'timeoutSeconds': args.timeout,
                  'beforeSwitch': run_probe(probe, args.timeout)}
        switched = False
        try:
            command(control, 'set', original['uid'], args.temporary_uid)
            switched = True
            result['temporaryDefault'] = public_device(current(control))
            result['afterSwitch'] = run_probe(probe, args.timeout)
            if args.worker_binary:
                result['workerPlayback'] = worker_playback(args.worker_binary.resolve())
        finally:
            # Compare-and-set protects a new external selection. A failed setter may
            # still have taken effect, so inspect even when `switched` is false.
            observed = current(control)
            if observed['uid'] == args.temporary_uid:
                command(control, 'set', args.temporary_uid, original['uid'])
            elif observed['uid'] != original['uid']:
                raise RuntimeError('default changed externally; manual restoration required')
            restored = current(control)
            result['restoredDefault'] = public_device(restored)
            if restored['uid'] != original['uid']:
                raise RuntimeError('original default was not restored')
        result['changedTemporarily'] = switched

    encoded = json.dumps(result, ensure_ascii=False, indent=2) + '\n'
    if args.output:
        with args.output.open('x', encoding='utf-8') as handle:
            handle.write(encoded)
    print(encoded, end='')


if __name__ == '__main__':
    main()
