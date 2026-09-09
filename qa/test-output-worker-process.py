#!/usr/bin/env python3
"""Real child-process protocol/file tests; does not start an audio device; coalesced play/STOP is cancelled before engine creation."""
import json
import math
import os
from pathlib import Path
import select
import struct
import subprocess
import tempfile
import time
import unittest
import uuid
import wave

ROOT = Path(__file__).resolve().parents[1]
BINARY = Path(os.environ.get('CIRCLR_OUTPUT_WORKER', str(ROOT / '.build/output-protocol-tests/debug/circlr-output-worker')))

class Child:
    def __init__(self, directory):
        self.session = str(uuid.uuid4())
        self.sequence = 0
        self.event_sequence = 0
        self.pending = b''
        self.trace_events = []
        self.process = subprocess.Popen([str(BINARY), '--session', self.session, '--directory', str(directory)],
                                        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, bufsize=0)
    def event(self):
        deadline = time.monotonic() + 3
        while b'\n' not in self.pending:
            remaining = deadline - time.monotonic()
            if remaining <= 0 or not select.select([self.process.stdout], [], [], remaining)[0]:
                raise AssertionError('child event timed out')
            chunk = os.read(self.process.stdout.fileno(), 4096)
            if not chunk: raise AssertionError('unexpected child EOF')
            self.pending += chunk
            if len(self.pending) > 65536: raise AssertionError('unbounded child output')
        line, self.pending = self.pending.split(b'\n', 1)
        packet = json.loads(line)
        assert packet['version'] == 1 and packet['session'].lower() == self.session.lower()
        self.event_sequence += 1
        assert packet['sequence'] == self.event_sequence
        return packet['payload']
    def control_event(self):
        # The file-only suite must never reach engine creation. Validate every
        # trace packet rather than silently skipping arbitrary diagnostic output.
        while True:
            payload = self.event()
            if 'trace' not in payload: return payload
            event = payload['trace']
            expected = [('fileValidation', 'entered'), ('fileValidation', 'completed')]
            assert len(self.trace_events) < len(expected)
            assert (event['stage'], event['phase']) == expected[len(self.trace_events)]
            elapsed = event['elapsedSeconds']
            assert isinstance(elapsed, (int, float)) and math.isfinite(elapsed) and 0 <= elapsed <= 14400
            if self.trace_events: assert elapsed >= self.trace_events[-1]['elapsedSeconds']
            self.trace_events.append(event)
    def send(self, payload):
        self.sequence += 1
        packet = dict(version=1, session=self.session, sequence=self.sequence, payload=payload)
        self.process.stdin.write(json.dumps(packet).encode() + b'\n')
    def close(self):
        if self.process.stdin and not self.process.stdin.closed: self.process.stdin.close()
        try: self.process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            self.process.kill(); self.process.wait(timeout=3)
        self.process.stdout.close()

class OutputWorkerProcessTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='circlr-worker-qa-')
        self.directory = Path(self.temp.name)
        self.child = None
    def tearDown(self):
        if self.child: self.child.close()
        self.temp.cleanup()
    def audio(self, frames=32, rate=48000, channels=2):
        path = self.directory/'audio.caf'
        with wave.open(str(path), 'wb') as f:
            f.setnchannels(channels); f.setsampwidth(2); f.setframerate(rate)
            f.writeframes(b'\0' * frames * channels * 2)
        path.chmod(0o600)
        return path
    def start(self):
        self.child = Child(self.directory)
        self.assertEqual(self.child.event(), {'hello': {}})
        return self.child
    def failure(self, child):
        self.assertIn('failure', child.control_event())
        self.assertNotEqual(child.process.wait(timeout=3), 0)
    def testPrepareStopAndParentEOF(self):
        self.audio(); c = self.start()
        c.send({'prepare': {'frames': 32}}); self.assertEqual(c.control_event(), {'prepared': {}})
        self.assertEqual(len(c.trace_events), 2)
        run = str(uuid.uuid4()).upper()
        c.send({'stop': {'run': run}}); self.assertEqual(c.control_event(), {'stopped': {'run': run}})
        c.process.stdin.close(); self.assertEqual(c.process.wait(timeout=3), 0)
    def testCoalescedStopCancelsBeforeDeviceCreation(self):
        self.audio(); c = self.start(); run = str(uuid.uuid4()).upper()
        payloads = [{'prepare': {'frames': 32}}, {'play': {'run': run}}, {'stop': {'run': run}}]
        packets = []
        for payload in payloads:
            c.sequence += 1
            packets.append(json.dumps(dict(version=1, session=c.session, sequence=c.sequence, payload=payload)).encode() + b'\n')
        c.process.stdin.write(b''.join(packets))
        self.assertEqual(c.control_event(), {'prepared': {}})
        self.assertEqual(len(c.trace_events), 2)
        self.assertEqual(c.control_event(), {'stopped': {'run': run}})
        c.process.stdin.close(); self.assertEqual(c.process.wait(timeout=3), 0)
    def testEOFBeforePreparation(self):
        c = self.start(); c.process.stdin.close(); self.assertEqual(c.process.wait(timeout=3), 0)
    def testFrameMismatch(self):
        self.audio(); c = self.start(); c.send({'prepare': {'frames': 31}}); self.failure(c)
    def testMissingFile(self):
        c = self.start(); c.send({'prepare': {'frames': 32}}); self.failure(c)
    def testSymlinkFile(self):
        p = self.audio(); p.rename(self.directory/'original.wav'); p.symlink_to('original.wav')
        c = self.start(); c.send({'prepare': {'frames': 32}}); self.failure(c)
    def testPublicFilePermissions(self):
        self.audio().chmod(0o644); c = self.start(); c.send({'prepare': {'frames': 32}}); self.failure(c)
    def testWrongSampleRate(self):
        self.audio(rate=44100); c = self.start(); c.send({'prepare': {'frames': 32}}); self.failure(c)
    def testTruncatedWire(self):
        c = self.start(); c.process.stdin.write(b'{'); c.process.stdin.close(); self.failure(c)
    def testWrongSession(self):
        c = self.start(); c.session = str(uuid.uuid4())
        c.send({'prepare': {'frames': 32}})
        # Event remains attached to original session; inspect raw exit instead of using the session assertion.
        self.assertEqual(c.process.wait(timeout=3), 66)
    def testInvalidDirectoryPermissions(self):
        self.directory.chmod(0o755); self.child = Child(self.directory)
        self.assertEqual(self.child.process.wait(timeout=3), 65)
    def testRepeatedPrepare(self):
        self.audio(); c = self.start(); c.send({'prepare': {'frames': 32}})
        self.assertEqual(c.control_event(), {'prepared': {}})
        self.assertEqual(len(c.trace_events), 2)
        c.send({'prepare': {'frames': 32}}); self.failure(c)
    def testHardLinkedFile(self):
        p = self.audio(); os.link(p, self.directory/'second.wav')
        c = self.start(); c.send({'prepare': {'frames': 32}}); self.failure(c)
    def testMonoPCM(self):
        self.audio(channels=1); c = self.start(); c.send({'prepare': {'frames': 32}}); self.failure(c)
    def testFiniteFloatPCM(self):
        self.float_audio(0.125); c = self.start(); c.send({'prepare': {'frames': 32}})
        self.assertEqual(c.control_event(), {'prepared': {}})
        self.assertEqual(len(c.trace_events), 2)
    def float_audio(self, value):
        samples = struct.pack('<ff', value, 0.0) * 32
        fmt = struct.pack('<HHIIHH', 3, 2, 48000, 48000*8, 8, 32)
        body = b'WAVEfmt ' + struct.pack('<I', len(fmt)) + fmt + b'data' + struct.pack('<I', len(samples)) + samples
        p = self.directory/'audio.caf'; p.write_bytes(b'RIFF' + struct.pack('<I', len(body)) + body); p.chmod(0o600)
    def testNonfinitePCM(self):
        self.float_audio(math.nan)
        c = self.start(); c.send({'prepare': {'frames': 32}}); self.failure(c)

if __name__ == '__main__': unittest.main()
