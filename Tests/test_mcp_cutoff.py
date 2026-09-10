"""No socket or audio: parameter schemas and capability-gated IPC packets."""
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('cutoff_mcp', Path(__file__).resolve().parents[1] / 'mcp/server.py')
server = importlib.util.module_from_spec(spec)
spec.loader.exec_module(server)


class CutoffMCPTests(unittest.TestCase):
    def operation(self, parameter='synthCutoff', value=400):
        return dict(kind='set_automation', useID='u', nodeID='n', parameter=parameter,
                    automationPoints=[dict(beat=0, value=value)])

    def packet(self, operations):
        return dict(projectID='p', expectedRevision=8, operations=operations)

    def snapshot(self, capability=1, project='p', revision=8):
        return dict(ok=True, result=dict(projectID=project, revision=revision,
                    runtime=dict(capabilities=dict(synthCutoffAutomation=capability))))

    def test_parameter_ranges_are_in_advertised_schema(self):
        schema = server.BY_NAME['circlr_apply']['inputSchema']
        for parameter, bounds in server.AUTOMATION_RANGES.items():
            for value in bounds:
                server.validate(self.packet([self.operation(parameter, value)]), schema)
            for value in (bounds[0] - 0.1, bounds[1] + 0.1, None, True, float('nan'), float('inf'), '400'):
                with self.subTest(parameter=parameter, value=value), patch.object(server, 'rpc') as rpc:
                    with self.assertRaises(ValueError):
                        server.call_tool('/unused', 'circlr_apply', self.packet([self.operation(parameter, value)]))
                    rpc.assert_not_called()

    def test_cutoff_forwards_exact_batch_after_capability_read(self):
        for points in ([], [dict(beat=0, value=400)], None):
            operation = self.operation()
            if points is None:
                del operation['automationPoints']
                operation['enabled'] = False
            else:
                operation['automationPoints'] = points
            operation['original'] = True
            batch = [self.operation('gain', 0.7), operation]
            with patch.object(server, 'rpc', side_effect=[self.snapshot(), dict(ok=True)]) as rpc:
                self.assertFalse(server.call_tool('/qa', 'circlr_apply', self.packet(batch))['isError'])
                self.assertEqual([call.args[1]['method'] for call in rpc.call_args_list], ['snapshot', 'apply'])
                sent = rpc.call_args.args[1]
                self.assertEqual(sent['arguments']['operations'], batch)
                self.assertEqual(sent['projectID'], 'p')
                self.assertEqual(sent['expectedRevision'], 8)

    def test_old_or_malformed_capability_and_stale_snapshot_never_apply(self):
        probes = [None, [], dict(ok=True, result=[]), dict(ok=False), dict(ok=True, result={}), self.snapshot(project='other'), self.snapshot(revision=9)]
        probes += [self.snapshot(capability=value) for value in (None, 0, 2, True, '1')]
        for probe in probes:
            with self.subTest(probe=probe), patch.object(server, 'rpc', return_value=probe) as rpc:
                result = server.call_tool('/qa', 'circlr_apply', self.packet([self.operation()]))
                self.assertTrue(result['isError'])
                rpc.assert_called_once()
                self.assertEqual(rpc.call_args.args[1]['method'], 'snapshot')

    def test_existing_parameters_have_no_new_preflight(self):
        for parameter, value in [('gain', 4), ('pan', -1)]:
            with patch.object(server, 'rpc', return_value=dict(ok=True)) as rpc:
                self.assertFalse(server.call_tool('/qa', 'circlr_apply', self.packet([self.operation(parameter, value)]))['isError'])
                rpc.assert_called_once()
                self.assertEqual(rpc.call_args.args[1]['method'], 'apply')

    def test_invalid_later_operation_rejects_whole_batch_before_snapshot(self):
        bad = self.operation('pan', 100)
        with patch.object(server, 'rpc') as rpc:
            with self.assertRaises(ValueError):
                server.call_tool('/qa', 'circlr_apply', self.packet([self.operation(), bad]))
            rpc.assert_not_called()

    def test_read_only_or_wrong_kind_never_probes(self):
        with patch.object(server, 'rpc') as rpc:
            with self.assertRaises(ValueError):
                server.call_tool('/qa', 'circlr_apply', self.packet([self.operation()]), read_only=True)
            bad = self.operation(); bad['kind'] = 'set_node'
            with self.assertRaises(ValueError):
                server.call_tool('/qa', 'circlr_apply', self.packet([bad]))
            rpc.assert_not_called()

    def test_app_final_revision_rejection_is_returned(self):
        with patch.object(server, 'rpc', side_effect=[self.snapshot(), dict(ok=False, error='stale_revision')]) as rpc:
            result = server.call_tool('/qa', 'circlr_apply', self.packet([self.operation()]))
            self.assertTrue(result['isError'])
            self.assertEqual(result['structuredContent']['error'], 'stale_revision')
            self.assertEqual(rpc.call_count, 2)


if __name__ == '__main__':
    unittest.main()
