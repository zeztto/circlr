"""Pure safety and outcome tests for verify-agent-stage-cancel.py."""
import importlib.util
from pathlib import Path
import shutil
import socket
import tempfile
import unittest
from unittest import mock

MODULE_PATH = Path(__file__).with_name('verify-agent-stage-cancel.py')
SPEC = importlib.util.spec_from_file_location('verify_agent_stage_cancel', MODULE_PATH)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class AgentStageCancelSafetyTests(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp(prefix='r80-stage-', dir='/tmp'))
        self.qa = self.root / 'qa-app'
        self.generated = self.root / 'generated'
        self.qa.joinpath('Agent').mkdir(parents=True)
        self.fixture = self.qa / 'fixtures' / 'long-song.circlr'
        self.fixture.mkdir(parents=True)
        self.fixture.joinpath('manifest.json').write_text('{}')
        self.generated.mkdir()
        self.socket_path = self.qa / 'Agent' / 'agent.sock'
        self.listener = socket.socket(socket.AF_UNIX)
        self.listener.bind(str(self.socket_path))
        self.listener.listen(1)
        self.patches = [mock.patch.object(MODULE, 'QA_ROOT', self.qa),
                        mock.patch.object(MODULE, 'GENERATED_ROOT', self.generated)]
        for patch in self.patches:
            patch.start()

    def tearDown(self):
        for patch in reversed(self.patches):
            patch.stop()
        self.listener.close()
        shutil.rmtree(self.root)

    def test_accepts_only_new_evidence_for_open_qa_fixture(self):
        evidence = self.generated / 'run-1'
        self.assertEqual(MODULE.validate_paths(self.socket_path, self.fixture, evidence),
                         (self.socket_path.resolve(), self.fixture.resolve(), evidence.resolve()))
        evidence.mkdir()
        with self.assertRaisesRegex(AssertionError, 'Evidence'):
            MODULE.validate_paths(self.socket_path, self.fixture, evidence)

    def test_rejects_non_qa_socket_and_project(self):
        other_socket = self.root / 'normal.sock'
        other = socket.socket(socket.AF_UNIX)
        try:
            other.bind(str(other_socket))
            with self.assertRaisesRegex(AssertionError, 'integration-QA socket'):
                MODULE.validate_paths(other_socket, self.fixture, self.generated / 'new')
        finally:
            other.close()
        external = self.root / 'external.circlr'
        external.mkdir()
        external.joinpath('manifest.json').write_text('{}')
        with self.assertRaisesRegex(AssertionError, 'integration-QA .circlr'):
            MODULE.validate_paths(self.socket_path, external, self.generated / 'new')

    def test_rejects_symlink_escape_for_project_and_evidence(self):
        external = self.root / 'external.circlr'
        external.mkdir()
        external.joinpath('manifest.json').write_text('{}')
        linked_project = self.qa / 'fixtures' / 'escape.circlr'
        linked_project.symlink_to(external)
        with self.assertRaisesRegex(AssertionError, 'integration-QA .circlr'):
            MODULE.validate_paths(self.socket_path, linked_project, self.generated / 'new')
        linked_evidence = self.generated / 'escape'
        linked_evidence.symlink_to(self.root)
        with self.assertRaisesRegex(AssertionError, 'Evidence'):
            MODULE.validate_paths(self.socket_path, self.fixture, linked_evidence / 'new')

    def test_only_data_bearing_regular_stage_counts(self):
        stage = self.root / 'stage.wav'
        self.assertEqual(MODULE.stage_bytes(stage), 0)
        stage.write_bytes(b'R' * 44)
        self.assertEqual(MODULE.stage_bytes(stage), 44)
        stage.write_bytes(b'R' * 45)
        self.assertEqual(MODULE.stage_bytes(stage), 45)
        link = self.root / 'linked.wav'
        link.symlink_to(stage)
        with self.assertRaisesRegex(AssertionError, 'regular file'):
            MODULE.stage_bytes(link)

    def test_job_id_cannot_escape_stage_directory(self):
        with self.assertRaisesRegex(AssertionError, 'UUID'):
            MODULE.require_job_id('../manifest.json')
        self.assertEqual(MODULE.require_job_id('56a061d3-0f3e-4b75-b7c1-2ef5b28f6c80'),
                         '56a061d3-0f3e-4b75-b7c1-2ef5b28f6c80')


class StageDecisionTests(unittest.TestCase):
    def test_short_stage_or_terminal_before_cancel_is_not_observed(self):
        self.assertEqual(MODULE.classify_stage_cancel(44, 'running', 'cancelled'),
                         'NOT_OBSERVED')
        self.assertEqual(MODULE.classify_stage_cancel(4096, 'completed', 'completed'),
                         'NOT_OBSERVED')
        self.assertEqual(MODULE.classify_stage_cancel(4096, 'running', 'completed'),
                         'NOT_OBSERVED')

    def test_only_running_data_stage_and_cancelled_response_can_verify(self):
        self.assertEqual(MODULE.classify_stage_cancel(4096, 'running', 'cancelled'),
                         'VERIFY_CANCELLED')
        with self.assertRaisesRegex(AssertionError, 'Unexpected cancel_job result'):
            MODULE.classify_stage_cancel(4096, 'running', 'failed')

    def test_result_exit_codes_preserve_inconclusive_vs_failure(self):
        self.assertEqual(MODULE.exit_code_for_status('PASS_BOUNDED_NATIVE_STAGE_CANCEL'), 0)
        self.assertEqual(MODULE.exit_code_for_status('NOT_OBSERVED'), 3)
        self.assertEqual(MODULE.exit_code_for_status('FAIL'), 1)


if __name__ == '__main__':
    unittest.main()
