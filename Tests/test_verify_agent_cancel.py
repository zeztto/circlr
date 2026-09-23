"""Safety and result-shape tests for the isolated native cancellation QA harness."""
import importlib.util
import json
from pathlib import Path
import socket
import tempfile
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / 'qa/verify-agent-cancel.py'
SPEC = importlib.util.spec_from_file_location('verify_agent_cancel', SCRIPT)
qa = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(qa)


class CancelQATests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        root = Path(self.temporary.name)
        self.qa_root = root / 'circlr-integration-qa'
        self.generated = root / 'qa/generated'
        self.project = self.qa_root / 'fixtures/disposable.circlr'
        self.project.mkdir(parents=True)
        (self.project / 'manifest.json').write_text(json.dumps({'id': 'QA-song'}))
        self.generated.mkdir(parents=True)
        self.socket = self.qa_root / 'Agent/agent.sock'
        self.socket.parent.mkdir(parents=True)
        self.listener = socket.socket(socket.AF_UNIX)
        self.listener.bind(str(self.socket))
        self.addCleanup(self.listener.close)
        self.patches = [patch.object(qa, 'QA_ROOT', self.qa_root),
                        patch.object(qa, 'GENERATED_ROOT', self.generated)]
        for item in self.patches:
            item.start()
            self.addCleanup(item.stop)

    def test_rejects_non_qa_socket_before_any_native_call(self):
        outside = Path(self.temporary.name) / 'normal-agent.sock'
        with patch.object(qa, 'native_call') as native:
            with self.assertRaisesRegex(AssertionError, 'integration-QA socket'):
                qa.run(outside, self.project, self.generated / 'unsafe', '185')
            native.assert_not_called()
        self.assertFalse((self.generated / 'unsafe').exists())

    def test_cancelled_job_is_idempotent_and_leaves_no_wav_or_mutation(self):
        state = {'runtime': {'bundleID': 'com.circlr.integrationqa', 'build': '185',
                             'capabilities': {'jobCancellation': 1}},
                 'path': str(self.project), 'projectID': 'QA-song', 'revision': 7,
                 'dirty': False, 'playback': {'playing': True},
                 'recording': {'audio': False, 'midi': False, 'busy': False, 'phase': 'idle'}}
        calls = []
        running = {'id': 'job-1', 'kind': 'export', 'state': 'running', 'progress': 0.25}
        cancelled = {'id': 'job-1', 'kind': 'export', 'state': 'cancelled', 'progress': 0.25}

        def fake_native(_socket, name, arguments=None):
            calls.append((name, arguments))
            if name == 'snapshot':
                return state
            if name == 'export':
                return {'jobID': 'job-1', 'state': 'running'}
            if name == 'job':
                return {'job': running if not any(n == 'cancel_job' for n, _ in calls) else cancelled}
            if name == 'cancel_job':
                return {'job': cancelled, 'revision': 7}
            self.fail(name)

        evidence = self.generated / 'cancel-test'
        with patch.object(qa, 'native_call', side_effect=fake_native), patch.object(qa.time, 'sleep'):
            result = qa.run(self.socket, self.project, evidence, '185',
                            require_playing=True, settle_seconds=0)
        self.assertEqual(result['status'], 'PASS_BOUNDED_NATIVE_CANCEL')
        self.assertEqual(result['beforeManifestSHA256'], result['afterManifestSHA256'])
        self.assertEqual(result['beforeTransport'], result['afterTransport'])
        self.assertEqual([name for name, _ in calls].count('cancel_job'), 2)
        self.assertFalse(Path(result['exportPath']).exists())
        self.assertFalse(Path(result['stagingPath']).exists())
        self.assertEqual(json.loads((evidence / 'report.json').read_text())['status'],
                         'PASS_BOUNDED_NATIVE_CANCEL')

    def test_completed_before_cancel_fails_and_preserves_evidence(self):
        state = {'runtime': {'bundleID': 'com.circlr.integrationqa', 'build': '185',
                             'capabilities': {'jobCancellation': 1}},
                 'path': str(self.project), 'projectID': 'QA-song', 'revision': 7,
                 'dirty': False, 'playback': {'playing': False},
                 'recording': {'audio': False, 'midi': False, 'busy': False, 'phase': 'idle'}}

        def fake_native(_socket, name, arguments=None):
            if name == 'snapshot':
                return state
            if name == 'export':
                return {'jobID': 'job-1', 'state': 'running'}
            if name == 'job':
                return {'job': {'id': 'job-1', 'kind': 'export', 'state': 'completed', 'progress': 1}}
            self.fail(name)

        evidence = self.generated / 'too-fast'
        with patch.object(qa, 'native_call', side_effect=fake_native):
            with self.assertRaisesRegex(AssertionError, 'before a cancellable render window'):
                qa.run(self.socket, self.project, evidence, '185')
        report = json.loads((evidence / 'report.json').read_text())
        self.assertEqual(report['status'], 'FAIL')
        self.assertIn('jobAtFailure', report)

    def test_late_staging_wav_fails_instead_of_reporting_success(self):
        state = {'runtime': {'bundleID': 'com.circlr.integrationqa', 'build': '185',
                             'capabilities': {'jobCancellation': 1}},
                 'path': str(self.project), 'projectID': 'QA-song', 'revision': 7,
                 'dirty': False, 'playback': {'playing': False},
                 'recording': {'audio': False, 'midi': False, 'busy': False, 'phase': 'idle'}}
        active = {'id': 'job-2', 'kind': 'export', 'state': 'running', 'progress': 0.5}
        done = {**active, 'state': 'cancelled'}

        def fake_native(_socket, name, arguments=None):
            if name == 'snapshot':
                return state
            if name == 'export':
                stage = Path(arguments['path']).parent / '.circlr-agent-job-2.wav'
                stage.write_bytes(b'late bytes')
                return {'jobID': 'job-2', 'state': 'running'}
            if name == 'job':
                return {'job': active if not cancelled[0] else done}
            if name == 'cancel_job':
                cancelled[0] = True
                return {'job': done, 'revision': 7}
            self.fail(name)

        cancelled = [False]
        evidence = self.generated / 'late-stage'
        with patch.object(qa, 'native_call', side_effect=fake_native), patch.object(qa.time, 'sleep'):
            with self.assertRaisesRegex(AssertionError, 'final or staging WAV'):
                qa.run(self.socket, self.project, evidence, '185', settle_seconds=0)
        report = json.loads((evidence / 'report.json').read_text())
        self.assertEqual(report['status'], 'FAIL')
        self.assertTrue((self.qa_root / 'fixtures/.circlr-agent-job-2.wav').exists())


if __name__ == '__main__':
    unittest.main()
