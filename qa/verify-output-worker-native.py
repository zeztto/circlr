#!/usr/bin/env python3
"""Explicit silent device probe. Records actual output separately from process recovery."""
import json
from pathlib import Path
import runpy
import tempfile
import time
import wave

ROOT = Path(__file__).resolve().parents[1]
Child = runpy.run_path(str(ROOT/'qa/test-output-worker-process.py'))['Child']
OUT = ROOT/'qa/generated/output-worker'

def main():
    OUT.mkdir(parents=True, exist_ok=True)
    target = OUT/'native.json'
    if target.exists(): raise SystemExit('Existing evidence preserved; choose a new run directory')
    result = {'silent': True, 'events': [], 'physicalStarted': False, 'clockObserved': False}
    with tempfile.TemporaryDirectory(prefix='circlr-output-native-') as directory:
        directory = Path(directory)
        path = directory/'audio.caf'
        with wave.open(str(path), 'wb') as f:
            f.setnchannels(2); f.setsampwidth(2); f.setframerate(48000); f.writeframes(b'\0' * 48000 * 4)
        path.chmod(0o600)
        child = Child(directory)
        try:
            result['pid'] = child.process.pid
            result['events'].append(child.event())
            child.send({'prepare': {'frames': 48000}})
            ready = child.event(); result['events'].append(ready); assert ready == {'prepared': {}}
            import uuid
            run = str(uuid.uuid4()).upper()
            child.send({'play': {'run': run}})
            try:
                event = child.event(); result['events'].append(event)
                result['physicalStarted'] = 'started' in event
                if result['physicalStarted']:
                    event = child.event(); result['events'].append(event)
                    result['clockObserved'] = 'clock' in event
                    child.send({'stop': {'run': run}})
                    deadline = time.monotonic() + 3
                    while time.monotonic() < deadline:
                        event = child.event(); result['events'].append(event)
                        if 'stopped' in event: break
            except AssertionError as error:
                result['observation'] = str(error)
            # Closing the command pipe is the host-death path, not a device STOP acknowledgement.
            begin = time.monotonic(); child.process.stdin.close()
            result['eofExit'] = child.process.wait(timeout=3)
            result['eofExitSeconds'] = time.monotonic() - begin
        finally: child.close()
        assert result['eofExit'] == 0
        replacement = Child(directory)
        try:
            result['replacementPID'] = replacement.process.pid
            assert replacement.process.pid != child.process.pid
            result['replacementHello'] = replacement.event()
            replacement.process.stdin.close()
            result['replacementExit'] = replacement.process.wait(timeout=3)
        finally: replacement.close()
    result['temporaryDirectoryRemoved'] = not directory.exists()
    with target.open('x') as f: json.dump(result, f, ensure_ascii=False, indent=2)
    print(json.dumps(result, ensure_ascii=False))

if __name__ == '__main__': main()
