"""Adversarial checks for the one-turn Codex -> circlr MCP evidence boundary."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock


SPEC = importlib.util.spec_from_file_location(
    'circlr_model_e2e', Path(__file__).with_name('run-0.80-model-e2e.py'))
HARNESS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(HARNESS)
REFERENCE_COMMAND = (
    '/bin/zsh -lc "sed -n \'1,240p\' '
    '.agents/skills/circlr-studio/references/session-contract.md && '
    'sed -n \'1,300p\' '
    '.agents/skills/circlr-studio/references/circlr-operations.md"')
PLAN = {
    'projectID': 'qa-project', 'revision': 3, 'runID': 'qa-run', 'build': '239',
    'operation': {'kind': 'set_step', 'arrangementID': 'qa-arrangement',
                  'useID': 'qa-use', 'laneID': 'qa-lane', 'stepIndex': 0,
                  'pitch': 65, 'enabled': True, 'subdivisions': 4,
                  'velocity': 80, 'gate': 1},
}


def item_event(phase, item):
    return {'type': 'item.' + phase, 'item': copy.deepcopy(item)}


def valid_events():
    context = {'id': 'context', 'type': 'mcp_tool_call', 'server': 'circlr',
               'tool': 'circlr_context', 'arguments': {}, 'status': 'in_progress'}
    inspect = {'id': 'inspect', 'type': 'mcp_tool_call', 'server': 'circlr',
               'tool': 'circlr_inspect',
               'arguments': {'arrangementID': 'qa-arrangement', 'useID': 'qa-use'},
               'status': 'in_progress'}
    apply = {'id': 'apply', 'type': 'mcp_tool_call', 'server': 'circlr',
             'tool': 'circlr_apply',
             'arguments': {'projectID': 'qa-project', 'expectedRevision': 3,
                           'operations': [PLAN['operation']]},
             'status': 'in_progress'}
    done = []
    for item in (context, inspect, apply):
        result = copy.deepcopy(item)
        result['status'] = 'completed'
        result['error'] = None
        detail = ({'project': {'id': 'qa-project', 'revision': 3}}
                  if item['tool'] == 'circlr_context' else
                  {'projectID': 'qa-project', 'revision': 3, 'use': {'id': 'qa-use'}}
                  if item['tool'] == 'circlr_inspect' else {'revision': 4})
        result['result'] = {'structured_content': {'ok': True, 'result': detail}}
        done.append(result)
    return [item_event('started', context), item_event('completed', done[0]),
            item_event('started', inspect), item_event('completed', done[1]),
            item_event('started', apply), item_event('completed', done[2]),
            {'type': 'turn.completed'}]


class ModelTraceTest(unittest.TestCase):
    def check_trace(self, events, expected_error=None):
        with tempfile.TemporaryDirectory() as folder:
            evidence = Path(folder)
            raw = ''.join(json.dumps(event) + '\n' for event in events).encode()
            (evidence / 'model.jsonl').write_bytes(raw)
            (evidence / 'model-exit.json').write_text(json.dumps({
                'exitCode': 0, 'traceSHA256': hashlib.sha256(raw).hexdigest()}))
            if expected_error:
                with self.assertRaisesRegex(RuntimeError, expected_error):
                    HARNESS.model_trace(evidence, PLAN)
            else:
                self.assertEqual(HARNESS.model_trace(evidence, PLAN),
                                 ['circlr_context', 'circlr_inspect', 'circlr_apply'])

    def test_one_completed_write_after_completed_reads(self):
        self.check_trace(valid_events())

    def test_write_started_before_inspect_completed(self):
        events = valid_events()
        events[3], events[4] = events[4], events[3]
        self.check_trace(events, 'after completed context and target inspect')

    def test_second_write_start_is_rejected_even_without_completion(self):
        events = valid_events()
        extra = copy.deepcopy(events[4]); extra['item']['id'] = 'extra'
        events.insert(-1, extra)
        self.check_trace(events, 'Expected one write')

    def test_pending_first_write_is_rejected(self):
        events = valid_events()
        del events[5]
        self.check_trace(events, 'unfinished tools')

    def test_file_change_is_rejected(self):
        events = valid_events()
        events.insert(-1, item_event('completed',
                                     {'id': 'file', 'type': 'file_change'}))
        self.check_trace(events, 'file change')

    def test_shell_write_is_rejected(self):
        events = valid_events()
        events.insert(-1, item_event('started',
                                     {'id': 'shell', 'type': 'command_execution',
                                      'command': 'touch unexpected', 'status': 'in_progress'}))
        self.check_trace(events, 'unexpected shell command')

    def test_exact_bundled_reference_read_is_allowed_once(self):
        events = valid_events()
        command = {'id': 'shell', 'type': 'command_execution',
                   'command': REFERENCE_COMMAND, 'status': 'in_progress'}
        finished = {**command, 'status': 'completed', 'exit_code': 0}
        events[0:0] = [item_event('started', command),
                       item_event('completed', finished)]
        self.check_trace(events)

    def test_duplicate_tool_completion_is_rejected(self):
        events = valid_events()
        events.insert(-1, copy.deepcopy(events[5]))
        self.check_trace(events, 'lacked a start')

    def test_different_target_inspection_is_rejected(self):
        events = valid_events()
        events[2]['item']['arguments']['useID'] = 'other'
        events[3]['item']['arguments']['useID'] = 'other'
        self.check_trace(events, 'different target')

    def test_same_fixture_cannot_start_after_app_restart(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            fixture = root / 'song.circlr'
            fixture.mkdir()
            first = HARNESS.claim_model_once(PLAN, fixture, root / 'evidence-a', root)
            self.assertEqual(first.stat().st_mode & 0o777, 0o600)
            restarted = {**PLAN, 'runID': 'qa-run-after-restart'}
            with self.assertRaisesRegex(RuntimeError, 'already started a model turn'):
                HARNESS.claim_model_once(restarted, fixture, root / 'evidence-b', root)

    def test_changed_installed_file_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            target = root / '.agents/skills/circlr-studio/SKILL.md'
            target.parent.mkdir(parents=True)
            target.write_text('original')
            state = root / '.codex/circlr-agent-kit.json'
            state.parent.mkdir()
            state.write_text(json.dumps({
                'schema': 'circlr-agent-install-v1',
                'files': {'.agents/skills/circlr-studio/SKILL.md':
                          hashlib.sha256(b'original').hexdigest()}}))
            HARNESS.installed_kit_state(root)
            target.write_text('changed')
            with self.assertRaisesRegex(RuntimeError, 'file changed'):
                HARNESS.installed_kit_state(root)

    def test_gateway_checks_current_target_immediately_before_the_only_write(self):
        sequence = []

        def forward(_path, name, _arguments, read_only=False):
            sequence.append(name)
            detail = ({'project': {'id': 'qa-project', 'revision': 3},
                       'runtime': {'build': '239'}} if name == 'circlr_context' else
                      {'projectID': 'qa-project', 'revision': 3,
                       'use': {'id': 'qa-use'}} if name == 'circlr_inspect' else
                      {'revision': 4})
            return {'structuredContent': {'ok': True, 'result': detail}, 'isError': False}

        def prewrite():
            sequence.append('checked_target')

        gate = HARNESS.ModelCallGate(PLAN, forward, prewrite)
        gate(None, 'circlr_context', {})
        gate(None, 'circlr_inspect', {'arrangementID': 'qa-arrangement',
                                      'useID': 'qa-use'})
        gate(None, 'circlr_apply', {'projectID': 'qa-project',
                                     'expectedRevision': 3,
                                     'operations': [PLAN['operation']]})
        self.assertEqual(sequence, ['circlr_context', 'circlr_inspect',
                                    'checked_target', 'circlr_apply'])
        with self.assertRaisesRegex(ValueError, 'already attempted'):
            gate(None, 'circlr_apply', {'projectID': 'qa-project',
                                         'expectedRevision': 3,
                                         'operations': [PLAN['operation']]})

    def test_gateway_blocks_changed_target_without_forwarding_write(self):
        sequence = []

        def forward(_path, name, _arguments, read_only=False):
            sequence.append(name)
            detail = ({'project': {'id': 'qa-project', 'revision': 3},
                       'runtime': {'build': '239'}} if name == 'circlr_context' else
                      {'projectID': 'qa-project', 'revision': 3,
                       'use': {'id': 'qa-use'}})
            return {'structuredContent': {'ok': True, 'result': detail}, 'isError': False}

        def changed():
            raise ValueError('target_changed')

        gate = HARNESS.ModelCallGate(PLAN, forward, changed)
        gate(None, 'circlr_context', {})
        gate(None, 'circlr_inspect', {'arrangementID': 'qa-arrangement',
                                      'useID': 'qa-use'})
        with self.assertRaisesRegex(ValueError, 'target_changed'):
            gate(None, 'circlr_apply', {'projectID': 'qa-project',
                                         'expectedRevision': 3,
                                         'operations': [PLAN['operation']]})
        self.assertEqual(sequence, ['circlr_context', 'circlr_inspect'])
        with self.assertRaisesRegex(ValueError, 'already attempted'):
            gate(None, 'circlr_apply', {'projectID': 'qa-project',
                                         'expectedRevision': 3,
                                         'operations': [PLAN['operation']]})

    def test_codex_environment_omits_inherited_secrets_and_sockets(self):
        with tempfile.TemporaryDirectory() as folder, mock.patch.dict(
                HARNESS.os.environ, {'OPENAI_API_KEY': 'do-not-inherit',
                                     'SSH_AUTH_SOCK': '/tmp/unrelated.sock',
                                     'CIRCLR_SOCKET': '/tmp/unrelated-circlr.sock'}):
            _codex, environment = HARNESS.restricted_codex_environment(Path(folder))
            self.assertEqual(environment['HOME'], folder)
            self.assertNotIn('OPENAI_API_KEY', environment)
            self.assertNotIn('SSH_AUTH_SOCK', environment)
            self.assertNotIn('CIRCLR_SOCKET', environment)
            self.assertTrue(Path(environment['CODEX_HOME']).is_dir())


if __name__ == '__main__':
    unittest.main()
